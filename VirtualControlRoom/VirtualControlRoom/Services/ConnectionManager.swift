import SwiftUI
import Combine
import Foundation

@MainActor
class ConnectionManager: ObservableObject {
    static let shared = ConnectionManager()
    
    // Dictionary to store VNC clients by connection profile ID
    private var vncClients: [UUID: LibVNCClient] = [:]
    
    // Published properties to notify UI of changes
    @Published var activeConnections: Set<UUID> = []
    
    // Connection lifecycle states
    enum ConnectionLifecycleState {
        case idle           // No connection
        case connecting     // Attempting to connect
        case connected      // Successfully connected
        case windowOpen     // Window is open and displaying
        case disconnecting  // Disconnection in progress
        case windowClosed   // Window closed but cleanup pending
    }
    
    // Track lifecycle state per connection
    private var connectionStates: [UUID: ConnectionLifecycleState] = [:]
    
    // Track Combine subscriptions per connection
    private var connectionSubscriptions: [UUID: AnyCancellable] = [:]
    
    private init() {}
    
    // Get or create a VNC client for a specific connection profile
    func getVNCClient(for profileID: UUID) -> LibVNCClient {
        let currentState = getLifecycleState(for: profileID)
        
        // If we have an existing client that's in a good state, use it
        if let existingClient = vncClients[profileID] {
            let clientState = existingClient.connectionState
            
            // Only reuse if client is in a clean state
            if currentState == .connecting || currentState == .connected || currentState == .windowOpen {
                return existingClient
            }
            
            // If client is disconnected or failed, clean it up synchronously before creating new one
            if case .disconnected = clientState {
                print("🧹 ConnectionManager: Removing stale disconnected client for \(profileID)")
                // Perform synchronous cleanup to avoid race condition
                cleanupConnectionSync(profileID: profileID)
            }
        }
        
        // Create a fresh client
        print("🆕 ConnectionManager: Creating new VNC client for \(profileID)")
        let newClient = LibVNCClient()
        newClient.setConnectionID(profileID.uuidString)
        vncClients[profileID] = newClient
        
        // Monitor connection state changes
        let subscription = newClient.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleConnectionStateChange(profileID: profileID, state: state)
            }
        
        // Store subscription for this specific connection
        connectionSubscriptions[profileID] = subscription
        
        return newClient
    }
    
    // Get connection state for a specific profile
    func getConnectionState(for profileID: UUID) -> VNCConnectionState {
        return vncClients[profileID]?.connectionState ?? .disconnected
    }
    
    // Get lifecycle state for a specific profile
    func getLifecycleState(for profileID: UUID) -> ConnectionLifecycleState {
        return connectionStates[profileID] ?? .idle
    }
    
    // Transition to a new lifecycle state
    private func transitionToState(_ newState: ConnectionLifecycleState, for profileID: UUID) {
        let oldState = connectionStates[profileID] ?? .idle
        connectionStates[profileID] = newState
        print("🔄 Connection \(profileID): \(oldState) → \(newState)")
        
        // Handle state-specific actions
        switch newState {
        case .connected, .windowOpen:
            // Add to active connections when connected (ready for window display)
            activeConnections.insert(profileID)
        case .idle, .windowClosed:
            activeConnections.remove(profileID)
        case .disconnecting:
            // Keep in activeConnections during disconnecting to avoid UI flicker
            break
        default:
            break
        }
    }
    
    // Check if a profile is connected
    func isConnected(profileID: UUID) -> Bool {
        return activeConnections.contains(profileID)
    }
    
    // Check if a VNC client exists for a profile
    func hasClient(for profileID: UUID) -> Bool {
        return vncClients[profileID] != nil
    }
    
    // Disconnect a specific profile
    func disconnect(profileID: UUID) {
        guard let client = vncClients[profileID] else { 
            print("⚠️ ConnectionManager: Cannot disconnect - no client for \(profileID)")
            return 
        }
        
        let currentState = getLifecycleState(for: profileID)
        
        // Only disconnect if not already disconnecting or idle
        if currentState == .disconnecting || currentState == .idle {
            print("⚠️ ConnectionManager: Already disconnecting or idle for \(profileID), state: \(currentState)")
            return
        }
        
        print("🔌 ConnectionManager: Manual disconnect requested for \(profileID)")
        transitionToState(.disconnecting, for: profileID)
        
        // Close SSH tunnel if exists
        SSHTunnelManager.shared.closeTunnel(connectionID: profileID.uuidString)
        
        client.disconnect()
    }
    
    // Notify that a window opened for a connection
    func windowDidOpen(for profileID: UUID) {
        transitionToState(.windowOpen, for: profileID)
    }
    
    // Notify that a window closed for a connection
    func windowDidClose(for profileID: UUID) {
        let currentState = getLifecycleState(for: profileID)
        
        // Only disconnect if we're not already disconnecting, disconnected, or idle
        if currentState == .windowOpen || (currentState == .connected && windowIsOpen(for: profileID)) {
            print("🪟 ConnectionManager: Window closing for \(profileID), state: \(currentState)")
            transitionToState(.disconnecting, for: profileID)
            
            // Close SSH tunnel if exists
            SSHTunnelManager.shared.closeTunnel(connectionID: profileID.uuidString)
            
            vncClients[profileID]?.disconnect()
            // Transition to windowClosed after initiating disconnect
            transitionToState(.windowClosed, for: profileID)
        } else {
            print("⚠️ ConnectionManager: Ignoring window close for \(profileID), state: \(currentState)")
        }
    }
    
    // Helper to check if window is actually open
    private func windowIsOpen(for profileID: UUID) -> Bool {
        // Check if the VNC client exists and has an open window
        return vncClients[profileID]?.windowIsOpen ?? false
    }
    
    // Disconnect all connections
    func disconnectAll() {
        for client in vncClients.values {
            client.disconnect()
        }
    }
    
    // Clean up disconnected clients
    func cleanupDisconnectedClients() {
        let disconnectedIDs = vncClients.compactMap { (id, client) in
            client.connectionState == .disconnected ? id : nil
        }
        
        for id in disconnectedIDs {
            vncClients.removeValue(forKey: id)
            activeConnections.remove(id)
        }
    }
    
    
    private func handleConnectionStateChange(profileID: UUID, state: VNCConnectionState) {
        let currentLifecycleState = getLifecycleState(for: profileID)
        
        switch state {
        case .connecting:
            if currentLifecycleState == .idle {
                transitionToState(.connecting, for: profileID)
            }
        case .connected:
            transitionToState(.connected, for: profileID)
        case .disconnected:
            // Clean transition based on current state - only cleanup if not already cleaned up
            if currentLifecycleState == .disconnecting || currentLifecycleState == .windowClosed {
                transitionToState(.idle, for: profileID)
                // Immediately clean up the client after disconnection for fresh reconnection
                // Check if client still exists to avoid double cleanup
                if vncClients[profileID] != nil {
                    print("🧹 ConnectionManager: Cleaning up VNC client for \(profileID) to allow fresh reconnection")
                    self.cleanupConnection(profileID: profileID)
                } else {
                    print("⚠️ ConnectionManager: VNC client for \(profileID) already cleaned up")
                }
            }
        case .failed:
            transitionToState(.idle, for: profileID)
            // Also clean up failed clients immediately - check if client still exists
            if vncClients[profileID] != nil {
                print("🧹 ConnectionManager: Cleaning up failed VNC client for \(profileID)")
                self.cleanupConnection(profileID: profileID)
            } else {
                print("⚠️ ConnectionManager: Failed VNC client for \(profileID) already cleaned up")
            }
        }
    }
    
    // Clean up all resources for a specific connection (synchronous version)
    private func cleanupConnectionSync(profileID: UUID) {
        // Double-check that client still exists (avoid double cleanup)
        guard vncClients[profileID] != nil else {
            print("⚠️ ConnectionManager: Client for \(profileID) already cleaned up")
            return
        }
        
        // Cancel the subscription for this connection
        connectionSubscriptions[profileID]?.cancel()
        connectionSubscriptions.removeValue(forKey: profileID)
        
        // Remove the VNC client
        vncClients.removeValue(forKey: profileID)
        
        // Reset the lifecycle state
        connectionStates.removeValue(forKey: profileID)
        
        print("🧹 ConnectionManager: Complete cleanup for \(profileID)")
    }
    
    // Clean up all resources for a specific connection (async version)
    private func cleanupConnection(profileID: UUID) {
        // Synchronize access to prevent race conditions during cleanup
        DispatchQueue.main.async {
            self.cleanupConnectionSync(profileID: profileID)
        }
    }
}