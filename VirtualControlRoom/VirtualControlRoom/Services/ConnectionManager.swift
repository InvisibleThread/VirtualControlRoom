import SwiftUI
import Combine

/// ConnectionManager is the central orchestrator for all VNC connections in the app.
/// It manages the lifecycle of VNC clients, tracks connection states, and coordinates
/// between the UI layer and the underlying VNC/SSH services.
/// 
/// Key responsibilities:
/// - Creates and manages LibVNCClient instances per connection profile
/// - Tracks connection lifecycle states (idle → connecting → connected → windowOpen)
/// - Publishes active connections for UI updates
/// - Handles window lifecycle events
/// - Ensures proper cleanup and resource management
///
/// This class is marked with @MainActor to ensure all operations happen on the main thread,
/// preventing race conditions in UI updates and state management.
@MainActor
class ConnectionManager: ObservableObject {
    static let shared = ConnectionManager()
    
    // Dictionary to store VNC clients by connection profile ID
    // Each connection profile gets its own VNC client instance
    private var vncClients: [UUID: LibVNCClient] = [:]
    
    // Published properties to notify UI of changes
    // This set contains profile IDs of connections that are ready for display
    @Published var activeConnections: Set<UUID> = []
    
    /// Connection lifecycle states track the complete journey of a VNC connection
    /// from initial request through cleanup. This state machine ensures proper
    /// resource management and prevents race conditions.
    enum ConnectionLifecycleState {
        case idle           // No connection - initial state or after cleanup
        case connecting     // SSH tunnel and VNC connection being established
        case connected      // VNC connected and ready for window display
        case windowOpen     // Window is actively displaying the VNC content
        case disconnecting  // Disconnect initiated, cleanup in progress
        case windowClosed   // Window closed but final cleanup still pending
    }
    
    // Track lifecycle state per connection
    private var connectionStates: [UUID: ConnectionLifecycleState] = [:]
    
    // Track Combine subscriptions per connection
    private var connectionSubscriptions: [UUID: AnyCancellable] = [:]
    
    private init() {}
    
    /// Gets or creates a VNC client for a specific connection profile.
    /// This method ensures that each profile has at most one VNC client instance,
    /// and handles cleanup of stale clients before creating new ones.
    ///
    /// - Parameter profileID: The UUID of the connection profile
    /// - Returns: A LibVNCClient instance ready for use
    ///
    /// The method performs the following checks:
    /// 1. If an existing client is in a good state (connecting/connected/windowOpen), reuse it
    /// 2. If an existing client is disconnected, clean it up first
    /// 3. Create a new client if none exists or after cleanup
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
                // Perform synchronous cleanup to avoid race condition
                cleanupConnectionSync(profileID: profileID)
            }
        }
        
        // Create a fresh client
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
    
    /// Manually disconnects a specific connection profile.
    /// This method handles the complete disconnection process including SSH tunnel cleanup.
    ///
    /// - Parameter profileID: The UUID of the connection profile to disconnect
    ///
    /// The disconnection process:
    /// 1. Validates that a client exists and isn't already disconnecting
    /// 2. Transitions to disconnecting state
    /// 3. Closes the SSH tunnel
    /// 4. Disconnects the VNC client
    func disconnect(profileID: UUID) {
        guard let client = vncClients[profileID] else { 
            return 
        }
        
        let currentState = getLifecycleState(for: profileID)
        
        // Only disconnect if not already disconnecting or idle
        if currentState == .disconnecting || currentState == .idle {
            return
        }
        
        transitionToState(.disconnecting, for: profileID)
        
        // Close SSH tunnel if exists
        SSHTunnelManager.shared.closeTunnel(connectionID: profileID.uuidString)
        
        client.disconnect()
    }
    
    /// Notifies the manager that a window has opened for a specific connection.
    /// This method should be called by VNCConnectionWindowView when it appears.
    ///
    /// - Parameter profileID: The UUID of the connection profile
    func windowDidOpen(for profileID: UUID) {
        transitionToState(.windowOpen, for: profileID)
    }
    
    // Notify that a window closed for a connection
    func windowDidClose(for profileID: UUID) {
        let currentState = getLifecycleState(for: profileID)
        
        // Only disconnect if we're not already disconnecting, disconnected, or idle
        if currentState == .windowOpen || (currentState == .connected && windowIsOpen(for: profileID)) {
            transitionToState(.disconnecting, for: profileID)
            
            // Close SSH tunnel if exists
            SSHTunnelManager.shared.closeTunnel(connectionID: profileID.uuidString)
            
            vncClients[profileID]?.disconnect()
            // Transition to windowClosed after initiating disconnect
            transitionToState(.windowClosed, for: profileID)
        } else {
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
                    self.cleanupConnection(profileID: profileID)
                }
            }
        case .failed:
            transitionToState(.idle, for: profileID)
            // Also clean up failed clients immediately - check if client still exists
            if vncClients[profileID] != nil {
                self.cleanupConnection(profileID: profileID)
            }
        }
    }
    
    /// Cleans up all resources associated with a specific connection.
    /// This includes canceling Combine subscriptions, removing the VNC client,
    /// and resetting the lifecycle state.
    ///
    /// - Parameter profileID: The UUID of the connection profile to clean up
    ///
    /// The cleanup is performed asynchronously on the main queue to ensure
    /// thread safety and prevent race conditions during concurrent cleanup attempts.
    private func cleanupConnection(profileID: UUID) {
        // Synchronize access to prevent race conditions during cleanup
        DispatchQueue.main.async {
            // Double-check that client still exists (avoid double cleanup)
            guard self.vncClients[profileID] != nil else {
                return
            }
            
            // Cancel the subscription for this connection
            self.connectionSubscriptions[profileID]?.cancel()
            self.connectionSubscriptions.removeValue(forKey: profileID)
            
            // Remove the VNC client
            self.vncClients.removeValue(forKey: profileID)
            
            // Reset the lifecycle state
            self.connectionStates.removeValue(forKey: profileID)
        }
    }
    
    /// Synchronous version of cleanup for use in contexts where async dispatch
    /// would cause race conditions (e.g., when creating a new client immediately
    /// after cleanup).
    ///
    /// - Parameter profileID: The UUID of the connection profile to clean up
    ///
    /// This method performs the same cleanup as cleanupConnection but executes
    /// synchronously on the current thread.
    private func cleanupConnectionSync(profileID: UUID) {
        // Double-check that client still exists (avoid double cleanup)
        guard vncClients[profileID] != nil else {
            return
        }
        
        // Cancel the subscription for this connection
        connectionSubscriptions[profileID]?.cancel()
        connectionSubscriptions.removeValue(forKey: profileID)
        
        // Remove the VNC client
        vncClients.removeValue(forKey: profileID)
        
        // Reset the lifecycle state
        connectionStates.removeValue(forKey: profileID)
    }
}