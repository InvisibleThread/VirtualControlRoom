import Foundation
import Combine

/// Manages VNC connection resilience and failover
@MainActor
class VNCResilienceManager: ObservableObject {
    static let shared = VNCResilienceManager()
    
    @Published var connectionStates: [String: VNCConnectionHealth] = [:]
    
    private var healthCheckTasks: [String: Task<Void, Never>] = [:]
    private var reconnectionTasks: [String: Task<Void, Never>] = [:]
    
    // Configuration
    private let healthCheckInterval: TimeInterval = 15
    private let maxReconnectionAttempts = 2
    private let reconnectionDelay: TimeInterval = 3
    
    private init() {
        print("🔌 VNCResilienceManager initialized")
    }
    
    // MARK: - Connection Management
    
    func registerConnection(_ connectionID: String) {
        print("🔌 VNCResilience: Registering connection \(connectionID)")
        connectionStates[connectionID] = VNCConnectionHealth(
            connectionID: connectionID,
            status: .connecting,
            lastHealthCheck: Date(),
            reconnectionAttempts: 0,
            lastError: nil
        )
        
        startHealthMonitoring(for: connectionID)
    }
    
    func unregisterConnection(_ connectionID: String) {
        print("🔌 VNCResilience: Unregistering connection \(connectionID)")
        
        // Cancel tasks
        healthCheckTasks[connectionID]?.cancel()
        reconnectionTasks[connectionID]?.cancel()
        
        // Cleanup
        healthCheckTasks.removeValue(forKey: connectionID)
        reconnectionTasks.removeValue(forKey: connectionID)
        connectionStates.removeValue(forKey: connectionID)
    }
    
    func updateConnectionStatus(_ connectionID: String, status: VNCConnectionStatus, error: Error? = nil) {
        guard var health = connectionStates[connectionID] else { return }
        
        let previousStatus = health.status
        health.status = status
        health.lastHealthCheck = Date()
        health.lastError = error
        
        // Reset reconnection attempts on successful connection
        if status == .connected && previousStatus != .connected {
            health.reconnectionAttempts = 0
            print("✅ VNCResilience: Connection \(connectionID) restored")
        }
        
        connectionStates[connectionID] = health
        
        // Handle status changes
        if status == .disconnected && previousStatus == .connected {
            handleUnexpectedDisconnection(connectionID)
        } else if status == .failed {
            handleConnectionFailure(connectionID, error: error)
        }
    }
    
    // MARK: - Health Monitoring
    
    private func startHealthMonitoring(for connectionID: String) {
        healthCheckTasks[connectionID] = Task {
            // Wait initial period before starting health checks
            try? await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
            
            while !Task.isCancelled {
                await performHealthCheck(for: connectionID)
                try? await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
            }
        }
    }
    
    private func performHealthCheck(for connectionID: String) async {
        guard let health = connectionStates[connectionID],
              health.status == .connected else { return }
        
        // Get VNC client from ConnectionManager
        let isHealthy = await testVNCHealth(connectionID)
        
        if !isHealthy {
            print("❌ VNCResilience: Health check failed for \(connectionID)")
            updateConnectionStatus(connectionID, status: .disconnected)
        } else {
            // Update last health check time
            updateConnectionStatus(connectionID, status: .connected)
        }
    }
    
    private func testVNCHealth(_ connectionID: String) async -> Bool {
        // Test VNC connection by checking if the client is still active
        guard let profileID = UUID(uuidString: connectionID) else { return false }
        
        let connectionManager = ConnectionManager.shared
        let connectionState = connectionManager.getLifecycleState(for: profileID)
        
        return connectionState == .connected || connectionState == .windowOpen
    }
    
    // MARK: - Failover and Recovery
    
    private func handleUnexpectedDisconnection(_ connectionID: String) {
        print("🔌 VNCResilience: Handling unexpected disconnection for \(connectionID)")
        
        // Check if SSH tunnel is still alive
        if SSHTunnelManager.shared.hasTunnel(for: connectionID) {
            // SSH tunnel is alive, VNC server might be down or restarting
            startVNCReconnection(for: connectionID)
        } else {
            // SSH tunnel is also down, let SSH resilience handle it
            print("🔌 VNCResilience: SSH tunnel also down, deferring to SSH resilience")
        }
    }
    
    private func handleConnectionFailure(_ connectionID: String, error: Error?) {
        print("🔌 VNCResilience: Handling connection failure for \(connectionID)")
        
        if let error = error {
            print("🔌 VNCResilience: Error details: \(error.localizedDescription)")
        }
        
        // Post user-friendly notification
        let userMessage = generateUserFriendlyError(from: error)
        NotificationCenter.default.post(
            name: .vncConnectionFailed,
            object: connectionID,
            userInfo: ["error": userMessage]
        )
    }
    
    private func startVNCReconnection(for connectionID: String) {
        // Cancel existing reconnection task
        reconnectionTasks[connectionID]?.cancel()
        
        reconnectionTasks[connectionID] = Task {
            guard var health = connectionStates[connectionID] else { return }
            
            print("🔄 VNCResilience: Starting VNC reconnection for \(connectionID)")
            
            while health.reconnectionAttempts < maxReconnectionAttempts && !Task.isCancelled {
                health.reconnectionAttempts += 1
                connectionStates[connectionID] = health
                
                print("🔄 VNCResilience: Reconnection attempt \(health.reconnectionAttempts)/\(maxReconnectionAttempts) for \(connectionID)")
                
                // Wait before attempting reconnection
                try? await Task.sleep(nanoseconds: UInt64(reconnectionDelay * 1_000_000_000))
                
                if Task.isCancelled { break }
                
                // Attempt VNC reconnection
                let success = await attemptVNCReconnection(connectionID)
                
                if success {
                    print("✅ VNCResilience: VNC reconnection successful for \(connectionID)")
                    return
                }
                
                // Update health state
                if let updatedHealth = connectionStates[connectionID] {
                    health = updatedHealth
                }
            }
            
            if health.reconnectionAttempts >= maxReconnectionAttempts {
                print("❌ VNCResilience: Max VNC reconnection attempts reached for \(connectionID)")
                updateConnectionStatus(connectionID, status: .failed)
            }
        }
    }
    
    private func attemptVNCReconnection(_ connectionID: String) async -> Bool {
        // Notify ConnectionManager to attempt VNC reconnection
        NotificationCenter.default.post(
            name: .vncReconnectionAttempt,
            object: connectionID
        )
        
        // Wait a moment for the reconnection attempt
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Check if reconnection was successful
        return connectionStates[connectionID]?.status == .connected
    }
    
    // MARK: - User-Friendly Error Messages
    
    private func generateUserFriendlyError(from error: Error?) -> String {
        guard let error = error else {
            return "VNC connection lost. Please check your network connection and try again."
        }
        
        let errorDescription = error.localizedDescription.lowercased()
        
        if errorDescription.contains("timeout") {
            return "Connection timed out. The VNC server may be busy or unreachable."
        } else if errorDescription.contains("refused") || errorDescription.contains("connection refused") {
            return "Connection refused. The VNC server may not be running or may be blocking connections."
        } else if errorDescription.contains("authentication") || errorDescription.contains("password") {
            return "Authentication failed. Please check your VNC password and try again."
        } else if errorDescription.contains("network") || errorDescription.contains("unreachable") {
            return "Network error. Please check your internet connection and try again."
        } else if errorDescription.contains("protocol") {
            return "Protocol error. The VNC server may be using an incompatible version."
        } else {
            return "VNC connection failed. Please check your settings and try again."
        }
    }
}

// MARK: - Supporting Types

struct VNCConnectionHealth {
    let connectionID: String
    var status: VNCConnectionStatus
    var lastHealthCheck: Date
    var reconnectionAttempts: Int
    var lastError: Error?
}

enum VNCConnectionStatus {
    case connecting
    case connected
    case disconnected
    case failed
    
    var displayName: String {
        switch self {
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .failed: return "Failed"
        }
    }
    
    var isHealthy: Bool {
        return self == .connected
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let vncConnectionFailed = Notification.Name("VNCConnectionFailed")
    static let vncReconnectionAttempt = Notification.Name("VNCReconnectionAttempt")
}