import Foundation
import SwiftUI
import Combine

/// Manages SSH tunnels for VNC connections
/// This service handles the integration between SSH tunneling and VNC connections
@MainActor
class SSHTunnelManager: ObservableObject {
    static let shared = SSHTunnelManager()
    
    @Published var activeTunnels: [String: ActiveSSHTunnel] = [:]  // UUID -> Tunnel
    @Published var tunnelErrors: [String: String] = [:]  // UUID -> Error message
    
    private var sshServices: [String: SSHConnectionService] = [:]  // UUID -> SSH service
    private var tunnelSubscriptions: [String: AnyCancellable] = [:]
    
    private init() {
        print("🚇 SSHTunnelManager initialized for Sprint 2")
    }
    
    /// Create SSH tunnel for a VNC connection
    /// Returns the local port that VNC should connect to
    func createTunnel(
        connectionID: String,
        sshConfig: SSHConnectionConfig,
        vncHost: String,
        vncPort: Int
    ) async throws -> Int {
        
        print("🚇 Creating SSH tunnel for connection \(connectionID)")
        print("   SSH: \(sshConfig.username)@\(sshConfig.host):\(sshConfig.port)")
        print("   VNC: \(vncHost):\(vncPort)")
        
        // Create SSH service for this connection
        let sshService = SSHConnectionService()
        sshServices[connectionID] = sshService
        
        // Monitor SSH service state
        let subscription = sshService.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleSSHStateChange(connectionID: connectionID, state: state)
            }
        tunnelSubscriptions[connectionID] = subscription
        
        // Test SSH connection first
        await sshService.testConnection(config: sshConfig)
        
        guard case .connected = sshService.connectionState else {
            throw SSHTunnelError.connectionFailed(sshService.lastError ?? "Unknown error")
        }
        
        // Test authentication
        await sshService.testAuthentication(config: sshConfig)
        
        guard case .authenticated = sshService.connectionState else {
            throw SSHTunnelError.authenticationFailed(sshService.lastError ?? "Authentication failed")
        }
        
        // Create tunnel configuration
        let tunnelConfig = SSHTunnelConfig(
            localPort: nil,  // Auto-allocate
            remoteHost: vncHost,
            remotePort: vncPort,
            tunnelType: .local
        )
        
        // Create the tunnel
        await sshService.testTunnel(sshConfig: sshConfig, tunnelConfig: tunnelConfig)
        
        guard let tunnelInfo = sshService.activeTunnels.first else {
            throw SSHTunnelError.tunnelCreationFailed("No tunnel created")
        }
        
        // Store active tunnel information
        let activeTunnel = ActiveSSHTunnel(
            connectionID: connectionID,
            localPort: tunnelInfo.localPort,
            remoteHost: vncHost,
            remotePort: vncPort,
            sshHost: sshConfig.host,
            sshPort: sshConfig.port,
            sshUsername: sshConfig.username,
            createdAt: Date()
        )
        
        activeTunnels[connectionID] = activeTunnel
        
        print("✅ SSH tunnel created for connection \(connectionID): localhost:\(tunnelInfo.localPort)")
        
        return tunnelInfo.localPort
    }
    
    /// Close SSH tunnel for a connection
    func closeTunnel(connectionID: String) {
        print("🚇 Closing SSH tunnel for connection \(connectionID)")
        
        // Disconnect SSH service
        sshServices[connectionID]?.disconnect()
        sshServices.removeValue(forKey: connectionID)
        
        // Cancel subscription
        tunnelSubscriptions[connectionID]?.cancel()
        tunnelSubscriptions.removeValue(forKey: connectionID)
        
        // Remove active tunnel
        activeTunnels.removeValue(forKey: connectionID)
        tunnelErrors.removeValue(forKey: connectionID)
        
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
    
    // MARK: - Private Methods
    
    private func handleSSHStateChange(connectionID: String, state: SSHConnectionState) {
        switch state {
        case .failed(let error):
            tunnelErrors[connectionID] = error
            print("❌ SSH tunnel error for connection \(connectionID): \(error)")
            
        case .disconnected:
            // Clean up if tunnel was unexpectedly disconnected
            if activeTunnels[connectionID] != nil {
                print("⚠️ SSH tunnel unexpectedly disconnected for connection \(connectionID)")
                closeTunnel(connectionID: connectionID)
            }
            
        default:
            // Clear any previous errors
            tunnelErrors.removeValue(forKey: connectionID)
        }
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
        }
    }
}