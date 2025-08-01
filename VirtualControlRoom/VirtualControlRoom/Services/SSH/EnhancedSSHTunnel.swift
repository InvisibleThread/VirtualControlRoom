import Foundation
import NIOCore
import NIOPosix
import NIOSSH

/// Enhanced SSH tunnel with diagnostics, retry logic, and robust error handling
final class EnhancedSSHTunnel {
    let connectionID: String
    let localPort: Int
    private(set) var remoteHost: String  // Can be modified if using IP fallback
    let remotePort: Int
    let configuration: SSHTunnelConfiguration
    
    private let sshChannel: Channel
    private let sshHandler: NIOSSHHandler
    private let eventLoop: EventLoop
    private var portForwarder: SSHPortForwardingHandler?
    private var keepAliveTimer: RepeatedTask?
    private var isActive = false
    
    init(
        connectionID: String,
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        sshChannel: Channel,
        sshHandler: NIOSSHHandler,
        eventLoop: EventLoop,
        configuration: SSHTunnelConfiguration = .default
    ) {
        self.connectionID = connectionID
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.sshChannel = sshChannel
        self.sshHandler = sshHandler
        self.eventLoop = eventLoop
        self.configuration = configuration
        
        print("🚇 EnhancedSSHTunnel initialized for connection \(connectionID)")
    }
    
    /// Validate and start the SSH tunnel with enhanced error handling
    func start() async throws {
        print("🚇 Starting enhanced SSH tunnel for connection \(connectionID)")
        
        // Validate tunnel configuration if enabled
        if configuration.validateBeforeConnect {
            print("🔍 Starting tunnel validation...")
            let validationResult = await validateTunnel()
            print("✅ Tunnel validation completed: \(validationResult.isValid)")
            
            if !validationResult.isValid {
                throw SSHTunnelError.validationFailed(validationResult.summary)
            }
            
            // Update target host if validation suggests using IP
            if validationResult.targetHost != remoteHost {
                print("📝 Using validated target: \(validationResult.targetHost) instead of \(remoteHost)")
                self.remoteHost = validationResult.targetHost
            }
            
            // Show warnings if any
            if validationResult.hasWarnings {
                for warning in validationResult.warnings {
                    print("⚠️ \(warning)")
                }
            }
        }
        
        // Create port forwarder with retry logic
        try await createPortForwarderWithRetry()
        
        // Start keep-alive if enabled
        if configuration.enableKeepAlive {
            startKeepAlive()
        }
        
        isActive = true
        print("✅ Enhanced SSH tunnel started successfully")
    }
    
    /// Stop the SSH tunnel
    func stop() async {
        print("🛑 Stopping enhanced SSH tunnel for connection \(connectionID)")
        
        isActive = false
        
        // Cancel keep-alive
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        
        // Stop port forwarding
        if let forwarder = portForwarder {
            _ = try? await forwarder.stop().get()
        }
        
        // Close SSH channel
        _ = try? await sshChannel.close().get()
        
        print("✅ Enhanced SSH tunnel stopped")
    }
    
    // MARK: - Private Methods
    
    /// Validate tunnel configuration
    private func validateTunnel() async -> SSHTunnelValidationResult {
        print("🔍 Validating SSH tunnel configuration")
        
        var warnings: [String] = []
        var errors: [String] = []
        var targetHost = self.remoteHost
        
        // Test connectivity with hostname
        let (hostnameWorks, hostnameError) = await SSHDiagnostics.testRemoteConnectivity(
            sshChannel: sshChannel,
            sshHandler: sshHandler,
            targetHost: targetHost,
            targetPort: remotePort
        )
        
        if hostnameWorks {
            return SSHTunnelValidationResult(
                isValid: true,
                targetHost: targetHost,
                targetPort: remotePort,
                warnings: warnings,
                errors: errors
            )
        }
        
        // Hostname doesn't work, add error
        if let error = hostnameError {
            errors.append("Cannot reach \(targetHost):\(remotePort) - \(error)")
        }
        
        // Try IP address fallback if enabled
        if configuration.fallbackToIPAddress {
            if let ipAddress = await SSHDiagnostics.resolveHostname(targetHost) {
                let (ipWorks, ipError) = await SSHDiagnostics.testRemoteConnectivity(
                    sshChannel: sshChannel,
                    sshHandler: sshHandler,
                    targetHost: ipAddress,
                    targetPort: remotePort
                )
                
                if ipWorks {
                    warnings.append("Using IP address \(ipAddress) instead of hostname \(targetHost)")
                    targetHost = ipAddress
                    errors.removeAll()  // Clear errors since IP works
                    
                    return SSHTunnelValidationResult(
                        isValid: true,
                        targetHost: targetHost,
                        targetPort: remotePort,
                        warnings: warnings,
                        errors: errors
                    )
                } else if let error = ipError {
                    errors.append("Cannot reach \(ipAddress):\(remotePort) - \(error)")
                }
            } else {
                warnings.append("Could not resolve hostname to IP address")
            }
        }
        
        // Add diagnostic information
        errors.append("""
        Diagnostics:
        - SSH connection to bastion: ✅ Working
        - Target host from bastion: ❌ Unreachable
        - Possible causes:
          • Target host is on a different network segment
          • Firewall rules blocking connection
          • Target service not running on port \(remotePort)
          • Need to use different hostname/IP from bastion's perspective
        """)
        
        return SSHTunnelValidationResult(
            isValid: false,
            targetHost: targetHost,
            targetPort: remotePort,
            warnings: warnings,
            errors: errors
        )
    }
    
    /// Create port forwarder with retry logic - DISABLED retries to prevent auth lockout
    private func createPortForwarderWithRetry() async throws {
        print("🔄 Creating port forwarder (single attempt - retries disabled to prevent auth lockout)")
        
        // SINGLE ATTEMPT ONLY - no retries to prevent SSH authentication spam
        let forwarder = SSHPortForwardingHandler(
            sshHandler: sshHandler,
            eventLoop: eventLoop,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            connectionID: connectionID
        )
        
        // Start port forwarding - single attempt
        try await forwarder.start().get()
        self.portForwarder = forwarder
        
        print("✅ Port forwarder created successfully")
    }
    
    /// Start keep-alive timer
    private func startKeepAlive() {
        print("🫀 Starting SSH tunnel keep-alive")
        
        keepAliveTimer = eventLoop.scheduleRepeatedTask(
            initialDelay: .seconds(Int64(configuration.keepAliveInterval)),
            delay: .seconds(Int64(configuration.keepAliveInterval))
        ) { task in
            self.performKeepAlive()
        }
    }
    
    /// Perform keep-alive check
    private func performKeepAlive() {
        guard isActive else { return }
        
        // Check if SSH channel is still active
        if !sshChannel.isActive {
            print("❌ SSH channel is no longer active")
            Task {
                await self.stop()
            }
            return
        }
        
        // TODO: Could add a lightweight channel test here
        print("🫀 SSH tunnel keep-alive: OK")
    }
    
    deinit {
        print("🗑️ EnhancedSSHTunnel deinit for connection \(connectionID)")
    }
}

/// Factory for creating enhanced SSH tunnels
struct EnhancedSSHTunnelFactory {
    
    /// Create an enhanced SSH tunnel with validation and retry logic
    static func createTunnel(
        connectionID: String,
        sshConfig: SSHConnectionConfig,
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        eventLoopGroup: EventLoopGroup,
        configuration: SSHTunnelConfiguration = .default
    ) async throws -> EnhancedSSHTunnel {
        
        print("🏭 Creating enhanced SSH tunnel: localhost:\(localPort) → \(sshConfig.host) → \(remoteHost):\(remotePort)")
        
        return try await withCheckedThrowingContinuation { continuation in
            
            let bootstrap = ClientBootstrap(group: eventLoopGroup)
            var sshHandler: NIOSSHHandler?
            
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
            
            // Connect to SSH server with timeout
            let connectFuture = bootstrap.connect(host: sshConfig.host, port: sshConfig.port)
            
            // Set connection timeout
            let timeoutTask = eventLoopGroup.next().scheduleTask(
                deadline: .now() + .seconds(Int64(configuration.connectionTimeout))
            ) {
                connectFuture.whenComplete { result in
                    if case .failure = result {
                        // Already failed, nothing to do
                    } else {
                        // Force close the channel if still connecting
                        _ = connectFuture.flatMap { $0.close() }
                    }
                }
            }
            
            connectFuture
                .flatMap { channel -> EventLoopFuture<Channel> in
                    timeoutTask.cancel()
                    print("✅ TCP connection established to \(sshConfig.host):\(sshConfig.port)")
                    
                    // Create and add SSH handler
                    let handler = NIOSSHHandler(
                        role: .client(clientConfig),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
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
                        
                        // Create enhanced SSH tunnel
                        let tunnel = EnhancedSSHTunnel(
                            connectionID: connectionID,
                            localPort: localPort,
                            remoteHost: remoteHost,
                            remotePort: remotePort,
                            sshChannel: channel,
                            sshHandler: handler,
                            eventLoop: channel.eventLoop,
                            configuration: configuration
                        )
                        
                        // Start the tunnel
                        Task {
                            do {
                                try await tunnel.start()
                                continuation.resume(returning: tunnel)
                            } catch {
                                await tunnel.stop()
                                continuation.resume(throwing: error)
                            }
                        }
                        
                    case .failure(let error):
                        timeoutTask.cancel()
                        print("❌ SSH connection failed: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
        }
    }
    
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

// Extend SSHTunnelError with new cases
extension SSHTunnelError {
    static let connectionTimeout = SSHTunnelError.connectionFailed("Connection timeout")
    
    static func validationFailed(_ reason: String) -> SSHTunnelError {
        return .tunnelCreationFailed("Validation failed: \(reason)")
    }
}