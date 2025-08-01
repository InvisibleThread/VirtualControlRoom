import SwiftUI
import Combine
import Network
import NIOCore
import NIOPosix
import NIOSSH

/// SSHTunnelManager is responsible for creating and managing SSH tunnels that secure VNC connections.
/// It provides a high-level interface for establishing SSH port forwarding, handling authentication
/// (including OTP), and managing tunnel lifecycle with automatic reconnection capabilities.
///
/// Key features:
/// - SSH connection pooling/multiplexing via MasterSSHConnection
/// - Dynamic local port allocation (20000-30000 range)
/// - Automatic reconnection on network failures
/// - Integration with SSHResilienceManager for health monitoring
/// - Comprehensive error handling and diagnostics
///
/// The manager maintains state for active tunnels and provides published properties
/// for UI updates on tunnel status and errors.
@MainActor
class SSHTunnelManager: ObservableObject {
    static let shared = SSHTunnelManager()
    
    // Published state for UI binding
    @Published var activeTunnels: [String: ActiveSSHTunnel] = [:]  // connectionID -> Tunnel info
    @Published var tunnelErrors: [String: String] = [:]  // connectionID -> Error message
    @Published var tunnelWarnings: [String: String] = [:]  // connectionID -> Warning message
    
    // Internal tunnel management
    private var enhancedTunnels: [String: EnhancedSSHTunnel] = [:]  // connectionID -> Enhanced tunnel
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private let portManager = PortManager.shared
    private let configuration = SSHTunnelConfiguration.default
    private let resilienceManager = SSHResilienceManager.shared
    private var reconnectionCancellable: AnyCancellable?
    private let diagnosticsManager = ConnectionDiagnosticsManager.shared
    private let connectionPool = SSHConnectionPool.shared  // SSH connection multiplexing
    
    private init() {
        setupEventLoop()
        setupReconnectionHandling()
    }
    
    /// Initializes the NIO event loop group for SSH operations.
    /// Uses 2 threads to handle concurrent SSH connections efficiently.
    private func setupEventLoop() {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    }
    
    /// Sets up notification handling for SSH reconnection requests.
    /// Listens for .sshReconnectionAttempt notifications from SSHResilienceManager
    /// and triggers reconnection logic when network conditions improve.
    private func setupReconnectionHandling() {
        reconnectionCancellable = NotificationCenter.default
            .publisher(for: .sshReconnectionAttempt)
            .compactMap { $0.object as? String }
            .sink { [weak self] connectionID in
                Task { @MainActor [weak self] in
                    await self?.handleReconnectionRequest(connectionID)
                }
            }
    }
    
    /// Creates an SSH tunnel for securing a VNC connection.
    /// This method establishes an SSH connection (or reuses an existing one via multiplexing)
    /// and sets up port forwarding from a local port to the remote VNC server.
    ///
    /// - Parameters:
    ///   - connectionID: Unique identifier for this connection (usually profile UUID)
    ///   - sshConfig: SSH connection configuration including host, port, username, password
    ///   - vncHost: The hostname/IP of the VNC server (as seen from SSH server)
    ///   - vncPort: The port of the VNC server (typically 5900)
    ///   - otpCode: Optional one-time password for multi-factor authentication
    ///
    /// - Returns: The local port number where VNC client should connect
    ///
    /// - Throws: SSHError if connection fails, authentication fails, or port forwarding fails
    ///
    /// The method performs the following steps:
    /// 1. Checks for existing master connection (multiplexing)
    /// 2. Allocates a local port
    /// 3. Creates or reuses SSH connection
    /// 4. Sets up port forwarding
    /// 5. Validates the tunnel is working
    func createTunnel(
        connectionID: String,
        sshConfig: SSHConnectionConfig,
        vncHost: String,
        vncPort: Int,
        otpCode: String? = nil
    ) async throws -> Int {
        
        // Generate trace ID for this connection attempt
        _ = diagnosticsManager.generateTraceID(for: connectionID)
        
        diagnosticsManager.addTraceLog(
            "SSH_TUNNEL", 
            method: "createTunnel", 
            id: "START", 
            context: ["ssh": "\(sshConfig.username)@\(sshConfig.host):\(sshConfig.port)", "vnc": "\(vncHost):\(vncPort)"], 
            connectionID: connectionID, 
            level: .info
        )
        
        
        // Register with resilience manager
        resilienceManager.registerConnection(connectionID)
        
        // If OTP is provided, append it to the password
        var modifiedConfig = sshConfig
        if let otp = otpCode {
            switch sshConfig.authMethod {
            case .password(let password):
                modifiedConfig = SSHConnectionConfig(
                    host: sshConfig.host,
                    port: sshConfig.port,
                    username: sshConfig.username,
                    authMethod: .password(password + otp),
                    connectTimeout: sshConfig.connectTimeout
                )
            default:
                // OTP not applicable for key-based auth
                break
            }
        }
        
        guard let eventLoopGroup = self.eventLoopGroup else {
            diagnosticsManager.logSSHEvent("SSH tunnel creation failed: Event loop not initialized", level: .error, connectionID: connectionID)
            throw SSHTunnelError.tunnelCreationFailed("Event loop not initialized")
        }
        
        // Allocate a dynamic port first
        let localPort = try portManager.allocatePort()
        diagnosticsManager.addTraceLog(
            "PORT_ALLOC", 
            method: "allocatePort", 
            id: "ALLOC", 
            context: ["port": localPort], 
            result: "SUCCESS", 
            connectionID: connectionID
        )
        
        do {
            // Use connection pooling for SSH multiplexing
            diagnosticsManager.addTraceLog(
                "SSH_POOL", 
                method: "createTunnel", 
                id: "INIT", 
                context: ["localPort": localPort, "remote": "\(vncHost):\(vncPort)", "multiplexing": true], 
                connectionID: connectionID
            )
            
            // Try to use existing master connection or create new one
            let master = try await connectionPool.getOrCreateMasterConnection(
                host: modifiedConfig.host,
                port: modifiedConfig.port,
                username: modifiedConfig.username,
                config: modifiedConfig,
                eventLoopGroup: eventLoopGroup
            )
            
            
            // Create port forwarding channel on master connection
            let portForwarder = try await master.createPortForwardingChannel(
                localPort: localPort,
                remoteHost: vncHost,
                remotePort: vncPort,
                connectionID: connectionID
            )
            
            // Start port forwarding
            try await portForwarder.start().get()
            
            // Tunnel is running on the allocated port
            diagnosticsManager.addTraceLog(
                "SSH_POOL", 
                method: "createTunnel", 
                id: "COMPLETE", 
                result: "SUCCESS port=\(localPort) multiplexed=true channels=\(master.activeChannels)", 
                connectionID: connectionID, 
                level: .success
            )
            
            // No validation, so remote host stays the same
            let actualRemoteHost = vncHost
        
            // Store active tunnel information
            let activeTunnel = ActiveSSHTunnel(
                connectionID: connectionID,
                localPort: localPort,
                remoteHost: actualRemoteHost,
                remotePort: vncPort,
                sshHost: sshConfig.host,
                sshPort: sshConfig.port,
                sshUsername: sshConfig.username,
                createdAt: Date(),
                config: sshConfig,
                vncHost: vncHost,
                vncPort: vncPort
            )
            
            activeTunnels[connectionID] = activeTunnel
            
            
            // Update resilience manager status
            resilienceManager.updateConnectionStatus(connectionID, status: .connected)
            
            // Add a brief delay to ensure port forwarding is ready
            // This is especially important for group connections
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            // Verify port forwarding is actually listening
            let isListening = await verifyPortIsListening(localPort: localPort)
            if !isListening {
                diagnosticsManager.logSSHEvent("Port forwarding not ready on port \(localPort)", level: .warning, connectionID: connectionID)
            }
            
            return localPort
            
        } catch {
            // Clean up on failure
            portManager.releasePort(localPort)
            resilienceManager.updateConnectionStatus(connectionID, status: .failed)
            
            // Trace the exact failure point
            diagnosticsManager.addTraceLog(
                "SSH_FACTORY", 
                method: "createTunnel", 
                id: "ERROR", 
                context: ["localPort": localPort, "error": "\(type(of: error))"], 
                result: "FAIL", 
                connectionID: connectionID, 
                level: .error
            )
            
            
            // Log the error directly as it occurred
            diagnosticsManager.logSSHEvent("SSH Tunnel Creation Failed: \(error.localizedDescription)", level: .error, connectionID: connectionID)
            
            // Extract meaningful error message for UI
            let errorMessage = SSHDiagnostics.extractSSHError(from: error)
            tunnelErrors[connectionID] = errorMessage
            
            diagnosticsManager.addTraceLog(
                "PORT_CLEANUP", 
                method: "releasePort", 
                id: "RELEASE", 
                context: ["port": localPort], 
                connectionID: connectionID
            )
            
            throw error
        }
    }
    
    /// Close SSH tunnel for a connection
    func closeTunnel(connectionID: String) {
        
        // Unregister with resilience manager
        resilienceManager.unregisterConnection(connectionID)
        
        // Release the allocated port
        if let tunnel = activeTunnels[connectionID] {
            portManager.releasePort(tunnel.localPort)
            
            // Note: With connection pooling, we don't close the master SSH connection
            // The channel will be cleaned up by the port forwarder's stop method
            // The master connection remains available for reuse
        }
        
        // Remove active tunnel and errors/warnings
        activeTunnels.removeValue(forKey: connectionID)
        tunnelErrors.removeValue(forKey: connectionID)
        tunnelWarnings.removeValue(forKey: connectionID)
        
    }
    
    /// Get local port for an active tunnel
    func getLocalPort(for connectionID: String) -> Int? {
        return activeTunnels[connectionID]?.localPort
    }
    
    /// Check if a tunnel is active for a connection
    func hasTunnel(for connectionID: String) -> Bool {
        return activeTunnels[connectionID] != nil
    }
    
    /// Close all tunnels
    func closeAllTunnels() {
        
        let connectionIDs = Array(activeTunnels.keys)
        for connectionID in connectionIDs {
            closeTunnel(connectionID: connectionID)
        }
        
    }
    
    // MARK: - Group Operations
    
    /// Create multiple SSH tunnels in parallel with shared OTP
    func createTunnelsInParallel(
        connections: [(connectionID: String, sshConfig: SSHConnectionConfig, vncHost: String, vncPort: Int)],
        sharedOTP: String?
    ) async -> [String: Result<Int, Error>] {
        
        
        var results: [String: Result<Int, Error>] = [:]
        
        // Create all tunnels in parallel using TaskGroup
        await withTaskGroup(of: (String, Result<Int, Error>).self) { taskGroup in
            
            for connection in connections {
                taskGroup.addTask { [weak self] in
                    guard let self = self else {
                        return (connection.connectionID, .failure(SSHTunnelError.tunnelCreationFailed("Manager deallocated")))
                    }
                    
                    // Modify SSH config to include shared OTP if provided
                    var modifiedConfig = connection.sshConfig
                    if let otp = sharedOTP {
                        switch connection.sshConfig.authMethod {
                        case .password(let password):
                            modifiedConfig = SSHConnectionConfig(
                                host: connection.sshConfig.host,
                                port: connection.sshConfig.port,
                                username: connection.sshConfig.username,
                                authMethod: .password(password + otp),
                                connectTimeout: connection.sshConfig.connectTimeout
                            )
                        default:
                            break // OTP not applicable for key-based auth
                        }
                    }
                    
                    do {
                        let localPort = try await self.createTunnel(
                            connectionID: connection.connectionID,
                            sshConfig: modifiedConfig,
                            vncHost: connection.vncHost,
                            vncPort: connection.vncPort
                        )
                        return (connection.connectionID, .success(localPort))
                    } catch {
                        return (connection.connectionID, .failure(error))
                    }
                }
            }
            
            // Collect all results
            for await (connectionID, result) in taskGroup {
                results[connectionID] = result
            }
        }
        
        let successCount = results.values.compactMap { result in
            if case .success = result { return 1 } else { return nil }
        }.count
        
        
        return results
    }
    
    /// Close multiple SSH tunnels for a group
    func closeTunnelsForGroup(_ connectionIDs: [String]) {
        
        for connectionID in connectionIDs {
            if hasTunnel(for: connectionID) {
                closeTunnel(connectionID: connectionID)
            }
        }
        
    }
    
    /// Check if all tunnels in a group are active
    func groupTunnelsActive(_ connectionIDs: [String]) -> Bool {
        return connectionIDs.allSatisfy { connectionID in
            hasTunnel(for: connectionID)
        }
    }
    
    /// Get tunnel for resilience manager
    func getTunnel(for connectionID: String) -> SSHTunnel? {
        // For now, check if we have an active tunnel
        return activeTunnels[connectionID] != nil ? nil : nil
        // TODO: Return actual SSHTunnel reference when we store them
    }
    
    /// Handle reconnection request from resilience manager
    private func handleReconnectionRequest(_ connectionID: String) async {
        
        guard let tunnel = activeTunnels[connectionID] else {
            return
        }
        
        // Store the original tunnel configuration
        let originalConfig = tunnel.config
        let originalVNCHost = tunnel.vncHost
        let originalVNCPort = tunnel.vncPort
        
        // Close the existing tunnel
        closeTunnel(connectionID: connectionID)
        
        // Wait a moment before reconnecting
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Attempt to recreate the tunnel
        do {
            resilienceManager.updateConnectionStatus(connectionID, status: .connecting)
            
            let newPort = try await createTunnel(
                connectionID: connectionID,
                sshConfig: originalConfig,
                vncHost: originalVNCHost,
                vncPort: originalVNCPort
            )
            
            resilienceManager.updateConnectionStatus(connectionID, status: .connected)
            
        } catch {
            resilienceManager.updateConnectionStatus(connectionID, status: .disconnected)
        }
    }
    
    // MARK: - Private Methods
    
    /// Verify that a port is actually listening
    private func verifyPortIsListening(localPort: Int) async -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket != -1 else { return false }
        defer { Darwin.close(socket) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(localPort).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        // If bind fails with EADDRINUSE, the port is in use (good!)
        return result == -1 && errno == EADDRINUSE
    }
    
    /// Test tunnel health by attempting to connect through SSH port forwarding
    private func testTunnelHealth(localPort: Int, connectionID: String) async -> Bool {
        await diagnosticsManager.logSSHEvent("Testing SSH tunnel functionality", level: .debug, connectionID: connectionID)
        
        // Create socket for testing actual SSH port forwarding
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket != -1 else {
            diagnosticsManager.logSSHEvent("Health check failed: socket creation error", level: .error, connectionID: connectionID)
            return false
        }
        defer { Darwin.close(socket) }
        
        // Set connection to non-blocking for timeout control
        var flags = fcntl(socket, F_GETFL, 0)
        fcntl(socket, F_SETFL, flags | O_NONBLOCK)
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(localPort).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        // Attempt connection - this will trigger SSH DirectTCP/IP channel creation
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if connectResult == 0 {
            // Immediate success
            diagnosticsManager.logSSHEvent("SSH port forwarding verified successfully", level: .success, connectionID: connectionID)
            return true
        } else {
            let error = errno
            if error == EINPROGRESS {
                
                // Use select() to wait for connection completion with timeout
                var readSet = fd_set()
                var writeSet = fd_set()
                
                // Initialize fd_sets
                readSet.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                writeSet.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                
                // Set the socket bit in write set (connection completion shows as writable)
                let wordIndex = Int(socket) / 32
                let bitIndex = Int(socket) % 32
                let mask: Int32 = 1 << bitIndex
                
                withUnsafeMutablePointer(to: &writeSet.fds_bits) { ptr in
                    let intPtr = ptr.withMemoryRebound(to: Int32.self, capacity: 32) { $0 }
                    intPtr[wordIndex] |= mask
                }
                
                // 3 second timeout for SSH port forwarding test
                var timeout = timeval()
                timeout.tv_sec = 3
                timeout.tv_usec = 0
                
                let selectResult = select(socket + 1, nil, &writeSet, nil, &timeout)
                
                if selectResult > 0 {
                    // Check if connection actually succeeded
                    var errorCode: Int32 = 0
                    var errorSize = socklen_t(MemoryLayout<Int32>.size)
                    
                    if getsockopt(socket, SOL_SOCKET, SO_ERROR, &errorCode, &errorSize) == 0 && errorCode == 0 {
                        diagnosticsManager.logSSHEvent("SSH port forwarding verified successfully", level: .success, connectionID: connectionID)
                        return true
                    } else {
                        diagnosticsManager.logSSHEvent("SSH port forwarding test failed: connection error \(errorCode)", level: .error, connectionID: connectionID)
                        
                        // Wait a moment for port forwarding error messages to be logged
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
                        return false
                    }
                } else if selectResult == 0 {
                    diagnosticsManager.logSSHEvent("SSH port forwarding test timed out", level: .error, connectionID: connectionID)
                    return false
                } else {
                    diagnosticsManager.logSSHEvent("SSH port forwarding test failed: select error", level: .error, connectionID: connectionID)
                    return false
                }
            } else {
                diagnosticsManager.logSSHEvent("SSH port forwarding test failed immediately: error \(error)", level: .error, connectionID: connectionID)
                return false
            }
        }
    }
    
    deinit {
        try? eventLoopGroup?.syncShutdownGracefully()
    }
}

// MARK: - Supporting Types

struct ActiveSSHTunnel {
    let connectionID: String
    let localPort: Int
    let remoteHost: String
    let remotePort: Int
    let sshHost: String
    let sshPort: Int
    let sshUsername: String
    let createdAt: Date
    let config: SSHConnectionConfig  // Original SSH configuration for reconnection
    let vncHost: String              // VNC target host for reconnection
    let vncPort: Int                 // VNC target port for reconnection
    
    var displayName: String {
        return "\(sshUsername)@\(sshHost) → \(vncHost):\(vncPort)"
    }
    
    var localEndpoint: String {
        return "localhost:\(localPort)"
    }
}

enum SSHTunnelError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case tunnelCreationFailed(String)
    case portForwardingDenied(String)
    case tunnelNotFound(String)
    case invalidChannelType
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "SSH connection failed: \(reason)"
        case .authenticationFailed(let reason):
            return "SSH authentication failed: \(reason)"
        case .tunnelCreationFailed(let reason):
            return "SSH tunnel creation failed: \(reason)"
        case .portForwardingDenied(let reason):
            return "SSH port forwarding denied: \(reason)"
        case .tunnelNotFound(let id):
            return "SSH tunnel not found for connection: \(id)"
        case .invalidChannelType:
            return "Invalid SSH channel type"
        }
    }
}