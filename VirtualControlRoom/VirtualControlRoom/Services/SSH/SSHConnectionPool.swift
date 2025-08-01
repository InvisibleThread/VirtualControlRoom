import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// Manages a pool of master SSH connections for channel multiplexing
/// Similar to OpenSSH's ControlMaster functionality
@MainActor
class SSHConnectionPool: ObservableObject {
    static let shared = SSHConnectionPool()
    
    // Configuration
    private let maxChannelsPerConnection = 10
    private let connectionTimeout: TimeInterval = 600 // 10 minutes
    private let healthCheckInterval: TimeInterval = 30
    
    // Storage
    private var masterConnections: [SSHConnectionKey: MasterSSHConnection] = [:]
    private var healthCheckTasks: [SSHConnectionKey: Task<Void, Never>] = [:]
    
    private init() {
        print("🏊 SSHConnectionPool initialized for connection multiplexing")
        setupConnectionCleanup()
    }
    
    /// Get or create a master SSH connection for the given parameters
    func getOrCreateMasterConnection(
        host: String,
        port: Int,
        username: String,
        config: SSHConnectionConfig,
        eventLoopGroup: EventLoopGroup
    ) async throws -> MasterSSHConnection {
        let key = SSHConnectionKey(host: host, port: port, username: username)
        
        print("🔍 SSHConnectionPool: Looking for existing connection to \(username)@\(host):\(port)")
        
        // Check for existing healthy connection with available capacity
        if let existing = masterConnections[key],
           existing.isHealthy,
           existing.activeChannels < maxChannelsPerConnection {
            print("✅ SSHConnectionPool: Reusing existing connection (channels: \(existing.activeChannels)/\(maxChannelsPerConnection))")
            existing.updateLastUsed()
            return existing
        }
        
        // Remove unhealthy connection if exists
        if let existing = masterConnections[key], !existing.isHealthy {
            print("🔄 SSHConnectionPool: Removing unhealthy connection")
            masterConnections.removeValue(forKey: key)
            healthCheckTasks[key]?.cancel()
            healthCheckTasks.removeValue(forKey: key)
        }
        
        // Create new master connection
        print("🆕 SSHConnectionPool: Creating new master connection")
        let master = try await createNewMasterConnection(
            key: key,
            config: config,
            eventLoopGroup: eventLoopGroup
        )
        
        // Store and start health monitoring
        masterConnections[key] = master
        startHealthMonitoring(for: key)
        
        return master
    }
    
    /// Create a new master SSH connection
    private func createNewMasterConnection(
        key: SSHConnectionKey,
        config: SSHConnectionConfig,
        eventLoopGroup: EventLoopGroup
    ) async throws -> MasterSSHConnection {
        print("🔧 Creating master SSH connection to \(key.username)@\(key.host):\(key.port)")
        
        return try await withCheckedThrowingContinuation { continuation in
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
            
            // Create authentication delegate
            let authDelegate = SSHPasswordAuthenticationMethod(
                username: config.username,
                password: extractPassword(from: config.authMethod),
                connectionID: "master-\(UUID().uuidString)"
            )
            
            let clientConfig = SSHClientConfiguration(
                userAuthDelegate: authDelegate,
                serverAuthDelegate: AcceptAllHostKeysDelegate()
            )
            
            var sshHandler: NIOSSHHandler?
            
            bootstrap.connect(host: key.host, port: key.port)
                .flatMap { channel -> EventLoopFuture<Channel> in
                    print("✅ TCP connection established for master")
                    
                    // Create SSH handler with support for multiple channels
                    let handler = NIOSSHHandler(
                        role: .client(clientConfig),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: { childChannel, channelType in
                            // Handle DirectTCP/IP channels
                            guard case .directTCPIP = channelType else {
                                return childChannel.eventLoop.makeSucceededVoidFuture()
                            }
                            
                            // Add data unwrapping for DirectTCP/IP channels
                            return childChannel.pipeline.addHandler(SSHChannelDataUnwrappingHandler())
                        }
                    )
                    
                    sshHandler = handler
                    return channel.pipeline.addHandler(handler).map { channel }
                }
                .whenComplete { result in
                    switch result {
                    case .success(let channel):
                        guard let handler = sshHandler else {
                            continuation.resume(throwing: SSHConnectionPoolError.handlerNotFound)
                            return
                        }
                        
                        print("✅ Master SSH connection established")
                        let master = MasterSSHConnection(
                            key: key,
                            channel: channel,
                            handler: handler,
                            config: config
                        )
                        
                        continuation.resume(returning: master)
                        
                    case .failure(let error):
                        print("❌ Failed to create master connection: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
        }
    }
    
    /// Extract password from authentication method
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
    
    /// Start health monitoring for a connection
    private func startHealthMonitoring(for key: SSHConnectionKey) {
        healthCheckTasks[key] = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
                
                if Task.isCancelled { break }
                
                await checkConnectionHealth(key: key)
            }
        }
    }
    
    /// Check health of a specific connection
    private func checkConnectionHealth(key: SSHConnectionKey) async {
        guard let master = masterConnections[key] else { return }
        
        if !master.isHealthy {
            print("⚠️ SSHConnectionPool: Connection to \(key.host) is unhealthy")
            masterConnections.removeValue(forKey: key)
            healthCheckTasks[key]?.cancel()
            healthCheckTasks.removeValue(forKey: key)
        }
    }
    
    /// Setup periodic cleanup of idle connections
    private func setupConnectionCleanup() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // Check every minute
                
                if Task.isCancelled { break }
                
                await cleanupIdleConnections()
            }
        }
    }
    
    /// Remove connections that have been idle too long
    private func cleanupIdleConnections() async {
        let now = Date()
        var keysToRemove: [SSHConnectionKey] = []
        
        for (key, master) in masterConnections {
            let idleTime = now.timeIntervalSince(master.lastUsed)
            
            if idleTime > connectionTimeout && master.activeChannels == 0 {
                print("🧹 SSHConnectionPool: Removing idle connection to \(key.host) (idle: \(Int(idleTime))s)")
                keysToRemove.append(key)
            }
        }
        
        for key in keysToRemove {
            if let master = masterConnections.removeValue(forKey: key) {
                await master.close()
            }
            healthCheckTasks[key]?.cancel()
            healthCheckTasks.removeValue(forKey: key)
        }
    }
    
    /// Get statistics about the connection pool
    func getPoolStatistics() -> SSHConnectionPoolStats {
        var stats = SSHConnectionPoolStats()
        
        for (_, master) in masterConnections {
            stats.totalConnections += 1
            stats.totalChannels += master.activeChannels
            
            if master.isHealthy {
                stats.healthyConnections += 1
            }
            
            if master.activeChannels < maxChannelsPerConnection {
                stats.availableConnections += 1
            }
        }
        
        return stats
    }
    
    /// Close all connections in the pool
    func closeAllConnections() async {
        print("🛑 SSHConnectionPool: Closing all connections")
        
        // Cancel all health checks
        for task in healthCheckTasks.values {
            task.cancel()
        }
        healthCheckTasks.removeAll()
        
        // Close all connections
        for master in masterConnections.values {
            await master.close()
        }
        masterConnections.removeAll()
        
        print("✅ SSHConnectionPool: All connections closed")
    }
}

// MARK: - Supporting Types

/// Key for identifying unique SSH connections
struct SSHConnectionKey: Hashable {
    let host: String
    let port: Int
    let username: String
    
    var description: String {
        return "\(username)@\(host):\(port)"
    }
}

/// Statistics about the connection pool
struct SSHConnectionPoolStats {
    var totalConnections: Int = 0
    var healthyConnections: Int = 0
    var availableConnections: Int = 0
    var totalChannels: Int = 0
}

/// Errors specific to connection pooling
enum SSHConnectionPoolError: LocalizedError {
    case handlerNotFound
    case connectionUnhealthy
    case channelLimitReached
    
    var errorDescription: String? {
        switch self {
        case .handlerNotFound:
            return "SSH handler not found during connection creation"
        case .connectionUnhealthy:
            return "Master SSH connection is unhealthy"
        case .channelLimitReached:
            return "Maximum channels per connection reached"
        }
    }
}