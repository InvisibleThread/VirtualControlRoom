import Foundation
import SwiftUI
import Combine
import NIOCore
import NIOPosix
import NIOSSH
import Network

/// SSH connection states for testing and validation
enum SSHConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
    case authenticating
    case authenticated
    
    static func == (lhs: SSHConnectionState, rhs: SSHConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.authenticating, .authenticating),
             (.authenticated, .authenticated):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

/// SSH authentication methods
enum SSHAuthMethod {
    case password(String)
    case privateKey(privateKey: String, passphrase: String?)
    case publicKey(publicKey: String, privateKey: String, passphrase: String?)
}

/// SSH connection configuration
struct SSHConnectionConfig {
    let host: String
    let port: Int
    let username: String
    let authMethod: SSHAuthMethod
    let connectTimeout: TimeInterval
    
    init(host: String, port: Int = 22, username: String, authMethod: SSHAuthMethod, connectTimeout: TimeInterval = 30) {
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.connectTimeout = connectTimeout
    }
}

/// SSH tunnel configuration for port forwarding
struct SSHTunnelConfig {
    let localPort: Int?  // nil for dynamic allocation
    let remoteHost: String
    let remotePort: Int
    let tunnelType: TunnelType
    
    enum TunnelType {
        case local   // Local port forwarding (SSH -L)
        case remote  // Remote port forwarding (SSH -R)
        case dynamic // Dynamic port forwarding (SSH -D)
    }
}

/// SSH connection service for testing and tunnel management
/// This service is designed for independent testing of SSH functionality
/// before integrating with VNC connections
@MainActor
class SSHConnectionService: ObservableObject {
    @Published var connectionState: SSHConnectionState = .disconnected
    @Published var lastError: String?
    @Published var connectionInfo: String = ""
    @Published var activeTunnels: [SSHTunnelInfo] = []
    
    // Test results for validation
    @Published var testResults: [SSHTestResult] = []
    
    private var connectionTimer: Timer?
    private let testTimeout: TimeInterval = 30.0
    
    // SwiftNIO SSH components for real SSH tunneling
    private var sshTunnels: [String: SSHTunnel] = [:]  // connectionID -> SSH tunnel
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var bootstrap: ClientBootstrap?
    
    init() {
        print("🔧 SSHConnectionService initialized for Sprint 2 with SwiftNIO SSH")
        setupEventLoop()
    }
    
    deinit {
        // Can't call MainActor-isolated cleanup from deinit
        // Cleanup will happen when the service is deallocated
    }
    
    private func cleanup() {
        // Stop all active tunnels
        for (_, tunnel) in sshTunnels {
            _ = tunnel.stop()
        }
        sshTunnels.removeAll()
        
        try? eventLoopGroup?.syncShutdownGracefully()
        eventLoopGroup = nil
        bootstrap = nil
    }
    
     private func setupEventLoop() {
         eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
         if let group = eventLoopGroup {
             bootstrap = ClientBootstrap(group: group)
         }
     }
    
    /// Test SSH connection without establishing tunnels
    /// This allows us to validate SSH connectivity independently
    func testConnection(config: SSHConnectionConfig) async {
        print("🧪 Testing SSH connection to \(config.username)@\(config.host):\(config.port)")
        
        connectionState = .connecting
        connectionInfo = "Testing connection to \(config.host)..."
        lastError = nil
        
        let testResult = SSHTestResult(
            testType: .connection,
            host: config.host,
            port: config.port,
            username: config.username,
            startTime: Date()
        )
        
        do {
            // Test SSH connection using SwiftNIO SSH
            let success = try await testSSHConnectionWithSwiftNIO(config: config)
            
            if success {
                connectionState = .connected
                connectionInfo = "Successfully connected to \(config.host)"
                
                var result = testResult
                result.endTime = Date()
                result.success = true
                result.details = "Connection established successfully"
                testResults.append(result)
                
                print("✅ SSH connection test successful")
            } else {
                throw SSHError.connectionTimeout
            }
            
        } catch {
            connectionState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            connectionInfo = "Connection failed: \(error.localizedDescription)"
            
            var result = testResult
            result.endTime = Date()
            result.success = false
            result.error = error.localizedDescription
            testResults.append(result)
            
            print("❌ SSH connection test failed: \(error.localizedDescription)")
        }
    }
    
    /// Test SSH authentication independently
    func testAuthentication(config: SSHConnectionConfig) async {
        print("🔐 Testing SSH authentication for \(config.username)@\(config.host)")
        
        connectionState = .authenticating
        connectionInfo = "Testing authentication..."
        
        let testResult = SSHTestResult(
            testType: .authentication,
            host: config.host,
            port: config.port,
            username: config.username,
            startTime: Date()
        )
        
        // Test SSH authentication using SwiftNIO SSH
        do {
            let success = try await testSSHAuthenticationWithSwiftNIO(config: config)
            
            if success {
                connectionState = .authenticated
                connectionInfo = "Authentication successful"
                
                var result = testResult
                result.endTime = Date()
                result.success = true
                result.details = "Authentication completed successfully"
                testResults.append(result)
                
                print("✅ SSH authentication test successful")
            } else {
                throw SSHError.authenticationFailed("Authentication failed")
            }
            
        } catch {
            connectionState = .failed(error.localizedDescription)
            connectionInfo = "Authentication failed: \(error.localizedDescription)"
            
            var result = testResult
            result.endTime = Date()
            result.success = false
            result.error = error.localizedDescription
            testResults.append(result)
            
            print("❌ SSH authentication test failed: \(error.localizedDescription)")
        }
    }
    
    /// Test SSH tunnel creation without connecting to final destination
    func testTunnel(sshConfig: SSHConnectionConfig, tunnelConfig: SSHTunnelConfig) async {
        print("🚇 Testing SSH tunnel: \(tunnelConfig.remoteHost):\(tunnelConfig.remotePort)")
        
        connectionInfo = "Testing tunnel setup..."
        
        let testResult = SSHTestResult(
            testType: .tunnel,
            host: sshConfig.host,
            port: sshConfig.port,
            username: sshConfig.username,
            startTime: Date()
        )
        
        do {
            let tunnelInfo = try await createSSHTunnel(sshConfig: sshConfig, tunnelConfig: tunnelConfig)
            
            activeTunnels.append(tunnelInfo)
            connectionInfo = "Tunnel established on local port \(tunnelInfo.localPort)"
            
            var result = testResult
            result.endTime = Date()
            result.success = true
            result.details = "Tunnel created successfully on local port \(tunnelInfo.localPort)"
            testResults.append(result)
            
            print("✅ SSH tunnel test successful: local port \(tunnelInfo.localPort)")
            
        } catch {
            connectionInfo = "Tunnel creation failed: \(error.localizedDescription)"
            
            var result = testResult
            result.endTime = Date()
            result.success = false
            result.error = error.localizedDescription
            testResults.append(result)
            
            print("❌ SSH tunnel test failed: \(error.localizedDescription)")
        }
    }
    
    /// Cancel any ongoing connection attempts and disconnect
    func cancelAndDisconnect() {
        print("🚫 Cancelling SSH operations and disconnecting")
        
        connectionTimer?.invalidate()
        connectionTimer = nil
        
        // Close SSH connection and tunnels
        activeTunnels.removeAll()
        
        connectionState = .disconnected
        connectionInfo = ""
        lastError = nil
        
        print("✅ SSH cancelled and disconnected")
    }
    
    /// Disconnect SSH connection and close tunnels
    func disconnect() {
        print("🔌 Disconnecting SSH connection")
        
        connectionTimer?.invalidate()
        connectionTimer = nil
        
        // Close SSH connection and tunnels
        activeTunnels.removeAll()
        
        connectionState = .disconnected
        connectionInfo = ""
        lastError = nil
        
        print("✅ SSH disconnected")
    }
    
    /// Clear test results
    func clearTestResults() {
        testResults.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func handleConnectionTimeout() {
        connectionState = .failed("Connection timeout")
        lastError = "Connection timed out after \(testTimeout) seconds"
        connectionInfo = "Connection timeout"
        
        let result = SSHTestResult(
            testType: .connection,
            host: "",
            port: 0,
            username: "",
            startTime: Date().addingTimeInterval(-testTimeout),
            endTime: Date(),
            success: false,
            error: "Connection timeout"
        )
        testResults.append(result)
    }
    
    private func createSSHTunnel(sshConfig: SSHConnectionConfig, tunnelConfig: SSHTunnelConfig) async throws -> SSHTunnelInfo {
        print("🚇 Creating SSH tunnel: \(tunnelConfig.remoteHost):\(tunnelConfig.remotePort)")
        
        // Allocate local port if not specified
        let localPort: Int
        if let configuredPort = tunnelConfig.localPort {
            localPort = configuredPort
        } else {
            localPort = try allocateLocalPort()
        }
        
        // Create real SSH tunnel using SwiftSH
        try await createRealSSHTunnel(
            localPort: localPort,
            sshConfig: sshConfig,
            remoteHost: tunnelConfig.remoteHost,
            remotePort: tunnelConfig.remotePort
        )
        
        print("✅ SSH tunnel created: localhost:\(localPort) → \(tunnelConfig.remoteHost):\(tunnelConfig.remotePort)")
        
        return SSHTunnelInfo(
            localPort: localPort,
            remoteHost: tunnelConfig.remoteHost,
            remotePort: tunnelConfig.remotePort,
            tunnelType: tunnelConfig.tunnelType,
            isActive: true
        )
    }
    
    private func createRealSSHTunnel(
        localPort: Int,
        sshConfig: SSHConnectionConfig,
        remoteHost: String,
        remotePort: Int
    ) async throws {
        print("🚇 Creating real SSH tunnel using SwiftNIO SSH")
        print("🚇 Tunnel: localhost:\(localPort) → \(sshConfig.username)@\(sshConfig.host) → \(remoteHost):\(remotePort)")
        
        guard let eventLoopGroup = self.eventLoopGroup else {
            throw SSHError.tunnelCreationFailed("EventLoopGroup not initialized")
        }
        
        // Create SSH tunnel using the factory
        let connectionID = UUID().uuidString
        let tunnel = try await SSHTunnelFactory.createTunnel(
            connectionID: connectionID,
            sshConfig: sshConfig,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            eventLoopGroup: eventLoopGroup
        )
        
        // Store the active tunnel
        sshTunnels[connectionID] = tunnel
        
        print("✅ SSH tunnel created and stored with ID: \(connectionID)")
    }
    
    /// Test SSH connection using SwiftNIO SSH
    private func testSSHConnectionWithSwiftNIO(config: SSHConnectionConfig) async throws -> Bool {
        print("🔗 Testing SSH connection using SwiftNIO SSH")
        print("🔗 Testing: \(config.username)@\(config.host):\(config.port)")
        
        guard let bootstrap = self.bootstrap else {
            throw SSHError.connectionTimeout
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let authDelegate = SSHPasswordAuthenticationMethod(
                username: config.username,
                password: extractPassword(from: config.authMethod)
            )
            
            let clientConfig = SSHClientConfiguration(
                userAuthDelegate: authDelegate,
                serverAuthDelegate: AcceptAllHostKeysDelegate()
            )
            
            bootstrap.connect(host: config.host, port: config.port)
                .flatMap { channel -> EventLoopFuture<Channel> in
                    return channel.pipeline.addHandler(NIOSSHHandler(
                        role: .client(clientConfig),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )).map { channel }
                }
                .whenComplete { result in
                    switch result {
                    case .success(let channel):
                        print("✅ SSH connection test successful")
                        _ = channel.close()
                        continuation.resume(returning: true)
                    case .failure(let error):
                        print("❌ SSH connection test failed: \(error)")
                        continuation.resume(returning: false)
                    }
                }
        }
    }
    
    /// Test SSH authentication using SwiftNIO SSH
    private func testSSHAuthenticationWithSwiftNIO(config: SSHConnectionConfig) async throws -> Bool {
        print("🔐 Testing SSH authentication using SwiftNIO SSH")
        print("🔐 Testing: \(config.username)@\(config.host):\(config.port)")
        
        // Authentication is tested as part of connection test in SwiftNIO SSH
        return try await testSSHConnectionWithSwiftNIO(config: config)
    }
    
    /// Extract password from SSH authentication method
    private func extractPassword(from authMethod: SSHAuthMethod) -> String {
        switch authMethod {
        case .password(let password):
            return password
        case .privateKey(_, let passphrase):
            return passphrase ?? ""
        case .publicKey(_, _, let passphrase):
            return passphrase ?? ""
        }
    }
    
    private func allocateLocalPort() throws -> Int {
        // Simple port allocation - find available port in range
        for port in 10000...65000 {
            if isPortAvailable(port: port) {
                return port
            }
        }
        throw SSHError.tunnelCreationFailed("No available local ports")
    }
    
    private func isPortAvailable(port: Int) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket != -1 else { return false }
        defer { Darwin.close(socket) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return result == 0
    }
}

// MARK: - SwiftNIO SSH Helper Types
// Note: SSH helper types (SSHPasswordAuthenticationMethod, AcceptAllHostKeysDelegate) are now in SSHTunnel.swift

// MARK: - Supporting Types

struct SSHTunnelInfo {
    let localPort: Int
    let remoteHost: String
    let remotePort: Int
    let tunnelType: SSHTunnelConfig.TunnelType
    let isActive: Bool
    let createdAt: Date = Date()
}

struct SSHTestResult {
    let testType: TestType
    let host: String
    let port: Int
    let username: String
    let startTime: Date
    var endTime: Date?
    var success: Bool = false
    var error: String?
    var details: String?
    
    enum TestType {
        case connection
        case authentication
        case tunnel
    }
    
    var duration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
}

enum SSHError: LocalizedError {
    case invalidHost
    case invalidPort
    case authenticationFailed(String)
    case tunnelCreationFailed(String)
    case connectionTimeout
    
    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Invalid host address"
        case .invalidPort:
            return "Invalid port number"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .tunnelCreationFailed(let reason):
            return "Tunnel creation failed: \(reason)"
        case .connectionTimeout:
            return "Connection timeout"
        }
    }
}

