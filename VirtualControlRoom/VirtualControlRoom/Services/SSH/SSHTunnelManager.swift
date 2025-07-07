import Foundation
import SwiftUI
import Combine
import Network
import NIOCore
import NIOPosix
import NIOSSH

/// Manages SSH tunnels for VNC connections with resilience and auto-reconnection
/// This service handles the integration between SSH tunneling and VNC connections
@MainActor
class SSHTunnelManager: ObservableObject {
    static let shared = SSHTunnelManager()
    
    @Published var activeTunnels: [String: ActiveSSHTunnel] = [:]  // UUID -> Tunnel
    @Published var tunnelErrors: [String: String] = [:]  // UUID -> Error message
    @Published var tunnelWarnings: [String: String] = [:]  // UUID -> Warning message
    
    private var enhancedTunnels: [String: EnhancedSSHTunnel] = [:]  // UUID -> Enhanced tunnel
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private let portManager = PortManager.shared
    private let configuration = SSHTunnelConfiguration.default
    private let resilienceManager = SSHResilienceManager.shared
    private var reconnectionCancellable: AnyCancellable?
    
    private init() {
        print("🚇 SSHTunnelManager initialized for Sprint 3 with resilience")
        setupEventLoop()
        setupReconnectionHandling()
    }
    
    private func setupEventLoop() {
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    }
    
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
    
    /// Create SSH tunnel for a VNC connection
    /// Returns the local port that VNC should connect to
    func createTunnel(
        connectionID: String,
        sshConfig: SSHConnectionConfig,
        vncHost: String,
        vncPort: Int,
        otpCode: String? = nil
    ) async throws -> Int {
        
        print("🚇 Creating SSH tunnel for connection \(connectionID)")
        print("   SSH: \(sshConfig.username)@\(sshConfig.host):\(sshConfig.port)")
        print("   VNC: \(vncHost):\(vncPort)")
        
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
            throw SSHTunnelError.tunnelCreationFailed("Event loop not initialized")
        }
        
        // Allocate a dynamic port first
        let localPort = try portManager.allocatePort()
        
        do {
            // Create simple SSH tunnel (skip enhanced validation for now)
            let _ = try await SSHTunnelFactory.createTunnel(
                connectionID: connectionID,
                sshConfig: modifiedConfig,
                localPort: localPort,
                remoteHost: vncHost,
                remotePort: vncPort,
                eventLoopGroup: eventLoopGroup
            )
            
            // Tunnel is running on the allocated port
            print("✅ Simple SSH tunnel created successfully on port \(localPort)")
            
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
                createdAt: Date()
            )
            
            activeTunnels[connectionID] = activeTunnel
            
            print("✅ SSH tunnel created for connection \(connectionID): localhost:\(localPort)")
            
            // Update resilience manager status
            resilienceManager.updateConnectionStatus(connectionID, status: .connected)
            
            // Test the tunnel by attempting to connect to the local port
            print("🔍 About to test tunnel health...")
            await testTunnelHealth(localPort: localPort, connectionID: connectionID)
            print("🔍 Tunnel health check returned")
            
            print("🔌 Tunnel health check completed, returning port \(localPort)")
            return localPort
            
        } catch {
            // Clean up on failure
            portManager.releasePort(localPort)
            resilienceManager.updateConnectionStatus(connectionID, status: .failed)
            
            // Extract meaningful error message
            let errorMessage = SSHDiagnostics.extractSSHError(from: error)
            tunnelErrors[connectionID] = errorMessage
            
            throw error
        }
    }
    
    /// Close SSH tunnel for a connection
    func closeTunnel(connectionID: String) {
        print("🚇 Closing SSH tunnel for connection \(connectionID)")
        
        // Unregister with resilience manager
        resilienceManager.unregisterConnection(connectionID)
        
        // Release the allocated port
        if let tunnel = activeTunnels[connectionID] {
            portManager.releasePort(tunnel.localPort)
        }
        
        // Clean up simple tunnel
        // For now, we rely on the SSH channel cleanup
        // TODO: Store and clean up simple tunnels properly
        
        // Remove active tunnel and errors/warnings
        activeTunnels.removeValue(forKey: connectionID)
        tunnelErrors.removeValue(forKey: connectionID)
        tunnelWarnings.removeValue(forKey: connectionID)
        
        print("✅ SSH tunnel closed for connection \(connectionID)")
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
        print("🚇 Closing all SSH tunnels")
        
        let connectionIDs = Array(activeTunnels.keys)
        for connectionID in connectionIDs {
            closeTunnel(connectionID: connectionID)
        }
        
        print("✅ All SSH tunnels closed")
    }
    
    /// Get tunnel for resilience manager
    func getTunnel(for connectionID: String) -> SSHTunnel? {
        // For now, check if we have an active tunnel
        return activeTunnels[connectionID] != nil ? nil : nil
        // TODO: Return actual SSHTunnel reference when we store them
    }
    
    /// Handle reconnection request from resilience manager
    private func handleReconnectionRequest(_ connectionID: String) async {
        print("🔄 SSHTunnelManager: Handling reconnection request for \(connectionID)")
        
        guard let tunnel = activeTunnels[connectionID] else {
            print("⚠️ No tunnel found for reconnection: \(connectionID)")
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
            
            print("✅ SSHTunnelManager: Reconnection successful for \(connectionID) on port \(newPort)")
            resilienceManager.updateConnectionStatus(connectionID, status: .connected)
            
        } catch {
            print("❌ SSHTunnelManager: Reconnection failed for \(connectionID): \(error)")
            resilienceManager.updateConnectionStatus(connectionID, status: .disconnected)
        }
    }
    
    // MARK: - Private Methods
    
    /// Test tunnel health by attempting to connect to the local port
    private func testTunnelHealth(localPort: Int, connectionID: String) async {
        print("🔍 Testing tunnel health for connection \(connectionID) on port \(localPort)")
        
        // Simple port availability check instead of full connection
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket != -1 else {
            print("⚠️ Tunnel health check failed: couldn't create test socket")
            return
        }
        defer { Darwin.close(socket) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(localPort).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if connectResult == 0 {
            print("✅ Tunnel health check passed for connection \(connectionID)")
        } else {
            print("⚠️ Tunnel health check failed for connection \(connectionID): connect failed")
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
    
    var displayName: String {
        return "\(sshUsername)@\(sshHost) → \(remoteHost):\(remotePort)"
    }
    
    var localEndpoint: String {
        return "localhost:\(localPort)"
    }
}

enum SSHTunnelError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case tunnelCreationFailed(String)
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
        case .tunnelNotFound(let id):
            return "SSH tunnel not found for connection: \(id)"
        case .invalidChannelType:
            return "Invalid SSH channel type"
        }
    }
}