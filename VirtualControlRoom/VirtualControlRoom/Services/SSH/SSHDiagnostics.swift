import Foundation
import NIOCore
import NIOSSH

/// SSH diagnostics and validation utilities
struct SSHDiagnostics {
    
    /// Test if the SSH server can reach a target host/port
    /// This helps diagnose "No route to host" errors before attempting tunnel creation
    static func testRemoteConnectivity(
        sshChannel: Channel,
        sshHandler: NIOSSHHandler,
        targetHost: String,
        targetPort: Int
    ) async -> (success: Bool, error: String?) {
        
        print("🔍 Testing SSH server connectivity to \(targetHost):\(targetPort)")
        
        return await withCheckedContinuation { continuation in
            
            // Create a test DirectTCP/IP channel
            let promise = sshChannel.eventLoop.makePromise(of: Channel.self)
            
            let channelType = SSHChannelType.directTCPIP(
                SSHChannelType.DirectTCPIP(
                    targetHost: targetHost,
                    targetPort: targetPort,
                    originatorAddress: try! SocketAddress(ipAddress: "127.0.0.1", port: 0)
                )
            )
            
            sshHandler.createChannel(promise, channelType: channelType) { channel, _ in
                // If we get here, the channel was created successfully
                print("✅ SSH server can reach \(targetHost):\(targetPort)")
                
                // Close the test channel immediately
                return channel.close().map {
                    print("✅ Test channel closed successfully")
                }
            }
            
            promise.futureResult.whenComplete { result in
                switch result {
                case .success:
                    continuation.resume(returning: (true, nil))
                case .failure(let error):
                    let errorMessage = extractSSHError(from: error)
                    print("❌ SSH server cannot reach \(targetHost):\(targetPort): \(errorMessage)")
                    continuation.resume(returning: (false, errorMessage))
                }
            }
        }
    }
    
    /// Extract meaningful error message from SSH errors
    static func extractSSHError(from error: Error) -> String {
        // Check error message for common SSH issues
        let errorMessage = error.localizedDescription
        
        if errorMessage.contains("channelSetupRejected") {
            if errorMessage.contains("Reason: 2") {
                return "Channel rejected: No route to host"
            } else if errorMessage.contains("Reason: 3") {
                return "Channel rejected: Connection refused"
            } else if errorMessage.contains("Reason: 4") {
                return "Channel rejected: Connection timeout"
            }
            return "Channel rejected"
        }
        
        if errorMessage.contains("No route to host") {
            return "No route to host"
        }
        
        if errorMessage.contains("Connection refused") {
            return "Connection refused"
        }
        
        return errorMessage
    }
    
    /// Resolve hostname to IP address
    /// Sometimes SSH servers can reach IP addresses but not hostnames
    static func resolveHostname(_ hostname: String) async -> String? {
        // For now, return nil to indicate we couldn't resolve
        // In a real implementation, you could use system DNS or other methods
        print("⚠️ Hostname resolution not implemented, using hostname as-is: \(hostname)")
        return nil
    }
    
    /// Validate SSH tunnel configuration before attempting to create it
    static func validateTunnelConfiguration(
        sshChannel: Channel,
        sshHandler: NIOSSHHandler,
        targetHost: String,
        targetPort: Int
    ) async -> (valid: Bool, suggestion: String?) {
        
        print("🔍 Validating SSH tunnel configuration")
        
        // Test connectivity with hostname
        let (hostnameWorks, hostnameError) = await testRemoteConnectivity(
            sshChannel: sshChannel,
            sshHandler: sshHandler,
            targetHost: targetHost,
            targetPort: targetPort
        )
        
        if hostnameWorks {
            return (true, nil)
        }
        
        // If hostname doesn't work, try IP address
        if let ipAddress = await resolveHostname(targetHost) {
            let (ipWorks, ipError) = await testRemoteConnectivity(
                sshChannel: sshChannel,
                sshHandler: sshHandler,
                targetHost: ipAddress,
                targetPort: targetPort
            )
            
            if ipWorks {
                return (true, "Use IP address \(ipAddress) instead of hostname \(targetHost)")
            }
        }
        
        // Neither hostname nor IP works
        let suggestion = """
        The SSH server cannot reach \(targetHost):\(targetPort).
        Possible issues:
        1. The target host is not accessible from the bastion
        2. The target port is not open or service is not running
        3. Firewall rules are blocking the connection
        4. The hostname should be different when accessed from the bastion
        
        Error: \(hostnameError ?? "Unknown error")
        """
        
        return (false, suggestion)
    }
}