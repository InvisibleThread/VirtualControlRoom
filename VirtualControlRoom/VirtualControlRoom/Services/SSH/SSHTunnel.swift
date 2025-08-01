import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// Represents an active SSH tunnel with port forwarding
final class SSHTunnel {
    let connectionID: String
    let localPort: Int
    let remoteHost: String
    let remotePort: Int
    
    private let sshChannel: Channel
    private let sshHandler: NIOSSHHandler
    private let portForwarder: SSHPortForwardingHandler
    private let eventLoop: EventLoop
    
    init(
        connectionID: String,
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        sshChannel: Channel,
        sshHandler: NIOSSHHandler,
        eventLoop: EventLoop
    ) {
        self.connectionID = connectionID
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.sshChannel = sshChannel
        self.sshHandler = sshHandler
        self.eventLoop = eventLoop
        
        self.portForwarder = SSHPortForwardingHandler(
            sshHandler: sshHandler,
            eventLoop: eventLoop,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            connectionID: connectionID
        )
        
        print("🚇 SSHTunnel initialized for connection \(connectionID)")
    }
    
    /// Start the SSH tunnel port forwarding
    func start() -> EventLoopFuture<Void> {
        print("🚇 Starting SSH tunnel for connection \(connectionID)")
        return portForwarder.start()
    }
    
    /// Stop the SSH tunnel
    func stop() -> EventLoopFuture<Void> {
        print("🛑 Stopping SSH tunnel for connection \(connectionID)")
        
        // Stop port forwarding first
        return portForwarder.stop().flatMap {
            // Then close SSH channel
            self.sshChannel.close()
        }
    }
    
    /// Check if the tunnel is active
    var isActive: Bool {
        return sshChannel.isActive
    }
    
    deinit {
        print("🗑️ SSHTunnel deinit for connection \(connectionID)")
    }
}

/// Factory for creating SSH tunnels
struct SSHTunnelFactory {
    
    /// Create an SSH tunnel with the given configuration
    static func createTunnel(
        connectionID: String,
        sshConfig: SSHConnectionConfig,
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        eventLoopGroup: EventLoopGroup
    ) async throws -> SSHTunnel {
        
        print("🏭 Creating SSH tunnel: localhost:\(localPort) → \(sshConfig.host) → \(remoteHost):\(remotePort)")
        
        return try await withCheckedThrowingContinuation { continuation in
            
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
            var sshHandler: NIOSSHHandler?
            var sshChannel: Channel?
            
            // Create SSH client configuration
            let authDelegate = SSHPasswordAuthenticationMethod(
                username: sshConfig.username,
                password: extractPassword(from: sshConfig.authMethod),
                connectionID: connectionID
            )
            
            let clientConfig = SSHClientConfiguration(
                userAuthDelegate: authDelegate,
                serverAuthDelegate: AcceptAllHostKeysDelegate()
            )
            
            // Connect to SSH server
            bootstrap.connect(host: sshConfig.host, port: sshConfig.port)
                .flatMap { channel -> EventLoopFuture<Channel> in
                    print("✅ TCP connection established to \(sshConfig.host):\(sshConfig.port)")
                    sshChannel = channel
                    
                    // Create and add SSH handler with child channel initializer
                    let handler = NIOSSHHandler(
                        role: .client(clientConfig),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: { channel, channelType in
                            // This initializer is called for each DirectTCP/IP channel
                            // We need to add a handler to convert SSHChannelData to ByteBuffer
                            // for DirectTCP/IP channels so they can work with standard NIO handlers
                            guard case .directTCPIP = channelType else {
                                // For non-DirectTCP/IP channels, use default configuration
                                return channel.eventLoop.makeSucceededVoidFuture()
                            }
                            
                            // Add the unwrapping handler for DirectTCP/IP channels
                            return channel.pipeline.addHandler(SSHChannelDataUnwrappingHandler())
                        }
                    )
                    sshHandler = handler
                    
                    return channel.pipeline.addHandler(handler).map { channel }
                }
                .whenComplete { result in
                    switch result {
                    case .success(let channel):
                        print("✅ SSH handshake completed")
                        
                        guard let handler = sshHandler else {
                            continuation.resume(throwing: SSHTunnelError.tunnelCreationFailed("No SSH handler"))
                            return
                        }
                        
                        // Create SSH tunnel object
                        let tunnel = SSHTunnel(
                            connectionID: connectionID,
                            localPort: localPort,
                            remoteHost: remoteHost,
                            remotePort: remotePort,
                            sshChannel: channel,
                            sshHandler: handler,
                            eventLoop: channel.eventLoop
                        )
                        
                        // Start port forwarding
                        tunnel.start().whenComplete { startResult in
                            switch startResult {
                            case .success:
                                print("✅ SSH tunnel created and started successfully")
                                continuation.resume(returning: tunnel)
                            case .failure(let error):
                                let errorDescription = "\(error)"
                                print("❌ Failed to start port forwarding: \(error)")
                                
                                // Pass through the actual error without interpretation
                                continuation.resume(throwing: SSHTunnelError.tunnelCreationFailed(errorDescription))
                                
                                _ = tunnel.stop()
                            }
                        }
                        
                    case .failure(let error):
                        print("❌ SSH connection failed: \(error)")
                        
                        // Log the error directly without string matching
                        Task {
                            await ConnectionDiagnosticsManager.shared.logSSHEvent(
                                "SSH Connection Failed: \(error.localizedDescription)", 
                                level: .error, 
                                connectionID: connectionID
                            )
                        }
                        
                        // Pass through the original error - let the calling code decide categorization
                        continuation.resume(throwing: SSHTunnelError.connectionFailed(error.localizedDescription))
                    }
                }
        }
    }
    
    /// Extract password from authentication method
    private static func extractPassword(from authMethod: SSHAuthMethod) -> String {
        switch authMethod {
        case .password(let password):
            return password
        case .privateKey(_, let passphrase):
            return passphrase ?? ""
        case .publicKey(_, _, let passphrase):
            return passphrase ?? ""
        }
    }
}

/// SSH password authentication delegate - SINGLE USE to prevent server lockout
class SSHPasswordAuthenticationMethod: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let password: String
    private let connectionID: String
    private var hasAttemptedAuth = false
    
    init(username: String, password: String, connectionID: String) {
        self.username = username
        self.password = password
        self.connectionID = connectionID
    }
    
    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods, nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        print("🔐 SSH Authentication: Available methods: \(availableMethods)")
        
        // PREVENT MULTIPLE AUTHENTICATION ATTEMPTS - single use only
        if hasAttemptedAuth {
            print("⚠️ SSH Authentication: Already attempted - preventing duplicate authentication to avoid server lockout")
            nextChallengePromise.succeed(nil)
            return
        }
        
        guard availableMethods.contains(.password) else {
            print("❌ SSH Authentication: Password method not available")
            Task {
                await ConnectionDiagnosticsManager.shared.logAuthEvent(
                    "SSH Authentication Failed: Password method not supported by server", 
                    level: .error, 
                    connectionID: connectionID
                )
            }
            nextChallengePromise.succeed(nil)
            return
        }
        
        // Mark that we've attempted authentication
        hasAttemptedAuth = true
        
        print("✅ SSH Authentication: Attempting password authentication for user '\(username)' (SINGLE ATTEMPT)")
        Task {
            await ConnectionDiagnosticsManager.shared.logAuthEvent(
                "SSH Authentication: Attempting login for user '\(username)' (SINGLE ATTEMPT)", 
                level: .info, 
                connectionID: connectionID
            )
        }
        
        nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: .password(.init(password: password))))
    }
}

/// SSH host key validation delegate (accepts all for testing)
struct AcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate {
    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        print("⚠️ Accepting host key without validation (for testing)")
        validationCompletePromise.succeed(())
    }
}

