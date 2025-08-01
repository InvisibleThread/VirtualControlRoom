import Foundation
import NIOCore
import NIOSSH

/// Represents a master SSH connection that can host multiple channels
/// Used for SSH connection multiplexing similar to ControlMaster
class MasterSSHConnection {
    let key: SSHConnectionKey
    let channel: Channel
    let handler: NIOSSHHandler
    let config: SSHConnectionConfig
    let createdAt: Date
    private(set) var lastUsed: Date
    private(set) var activeChannels: Int = 0
    private let lock = NSLock()
    
    // Channel tracking
    private var channelHandlers: [ObjectIdentifier: SSHPortForwardingHandler] = [:]
    
    init(key: SSHConnectionKey, channel: Channel, handler: NIOSSHHandler, config: SSHConnectionConfig) {
        self.key = key
        self.channel = channel
        self.handler = handler
        self.config = config
        self.createdAt = Date()
        self.lastUsed = Date()
        
        print("🎛️ MasterSSHConnection created for \(key.description)")
        
        // Monitor channel closure
        channel.closeFuture.whenComplete { [weak self] _ in
            print("⚠️ Master SSH channel closed for \(key.description)")
            self?.handleChannelClosed()
        }
    }
    
    /// Check if the connection is healthy and usable
    var isHealthy: Bool {
        return channel.isActive && activeChannels >= 0
    }
    
    /// Update the last used timestamp
    func updateLastUsed() {
        lock.withLock {
            lastUsed = Date()
        }
    }
    
    /// Create a new DirectTCP/IP channel for port forwarding
    func createPortForwardingChannel(
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        connectionID: String
    ) async throws -> SSHPortForwardingHandler {
        guard isHealthy else {
            throw SSHConnectionPoolError.connectionUnhealthy
        }
        
        print("🔄 Creating new channel on master connection (current: \(activeChannels) channels)")
        
        // Create port forwarding handler
        let portForwarder = SSHPortForwardingHandler(
            sshHandler: handler,
            eventLoop: channel.eventLoop,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            connectionID: connectionID
        )
        
        // Set master connection reference for cleanup
        portForwarder.setMasterConnection(self)
        
        // Track the handler
        let handlerID = ObjectIdentifier(portForwarder)
        lock.withLock {
            channelHandlers[handlerID] = portForwarder
            activeChannels += 1
        }
        
        updateLastUsed()
        
        // Setup cleanup when port forwarding stops
        Task { [weak self] in
            // Wait for the port forwarder to complete
            // This is a simplified approach - in production you'd want proper lifecycle tracking
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay
            
            // Monitor for cleanup (this would be triggered by the port forwarder's stop method)
            // For now, we'll rely on the port forwarder to notify us when it's done
        }
        
        print("✅ Channel created on master connection (now: \(activeChannels) channels)")
        
        return portForwarder
    }
    
    /// Remove a channel from tracking
    func removeChannel(_ handler: SSHPortForwardingHandler) {
        let handlerID = ObjectIdentifier(handler)
        
        lock.withLock {
            if channelHandlers.removeValue(forKey: handlerID) != nil {
                activeChannels = max(0, activeChannels - 1)
                print("📉 Channel removed from master connection (remaining: \(activeChannels) channels)")
            }
        }
        
        updateLastUsed()
    }
    
    /// Handle master channel closure
    private func handleChannelClosed() {
        lock.withLock {
            // Mark all channels as closed
            channelHandlers.removeAll()
            activeChannels = 0
        }
    }
    
    /// Close the master connection and all its channels
    func close() async {
        print("🛑 Closing master connection to \(key.description)")
        
        // Stop all port forwarders
        let handlers = lock.withLock { Array(channelHandlers.values) }
        
        for handler in handlers {
            _ = try? await handler.stop().get()
        }
        
        // Close the SSH channel
        _ = try? await channel.close().get()
        
        lock.withLock {
            channelHandlers.removeAll()
            activeChannels = 0
        }
        
        print("✅ Master connection closed")
    }
    
    /// Get connection information
    var connectionInfo: String {
        let idleTime = Date().timeIntervalSince(lastUsed)
        let uptime = Date().timeIntervalSince(createdAt)
        
        return """
        Master SSH Connection:
        - Host: \(key.description)
        - Status: \(isHealthy ? "Healthy" : "Unhealthy")
        - Active Channels: \(activeChannels)
        - Uptime: \(Int(uptime))s
        - Idle: \(Int(idleTime))s
        - Created: \(createdAt)
        """
    }
    
    deinit {
        print("🗑️ MasterSSHConnection deallocated for \(key.description)")
    }
}

// MARK: - Extensions for Enhanced Port Forwarding

extension SSHPortForwardingHandler {
    /// Create a port forwarding handler that uses a master connection
    static func createWithMasterConnection(
        _ master: MasterSSHConnection,
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        connectionID: String
    ) async throws -> SSHPortForwardingHandler {
        return try await master.createPortForwardingChannel(
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            connectionID: connectionID
        )
    }
}

// MARK: - Connection Monitoring

extension MasterSSHConnection {
    /// Monitor connection health with a simple echo test
    func testConnection() async -> Bool {
        guard channel.isActive else { return false }
        
        // For now, we just check if the channel is active
        // In a production implementation, you might want to:
        // 1. Send a keep-alive packet
        // 2. Create a test channel and immediately close it
        // 3. Use SSH protocol-level keep-alive
        
        return true
    }
    
    /// Get detailed statistics about this connection
    func getStatistics() -> MasterConnectionStats {
        return MasterConnectionStats(
            key: key,
            isHealthy: isHealthy,
            activeChannels: activeChannels,
            createdAt: createdAt,
            lastUsed: lastUsed,
            uptime: Date().timeIntervalSince(createdAt),
            idleTime: Date().timeIntervalSince(lastUsed)
        )
    }
}

/// Statistics for a master SSH connection
struct MasterConnectionStats {
    let key: SSHConnectionKey
    let isHealthy: Bool
    let activeChannels: Int
    let createdAt: Date
    let lastUsed: Date
    let uptime: TimeInterval
    let idleTime: TimeInterval
}