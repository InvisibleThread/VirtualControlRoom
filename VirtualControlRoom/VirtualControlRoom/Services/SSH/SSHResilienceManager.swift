import Foundation
import Combine
import NIOCore

/// Manages SSH connection resilience, timeouts, and auto-reconnection
@MainActor
class SSHResilienceManager: ObservableObject {
    static let shared = SSHResilienceManager()
    
    @Published var connectionStates: [String: SSHConnectionHealth] = [:]
    
    private var reconnectionTasks: [String: Task<Void, Never>] = [:]
    private var healthCheckTasks: [String: Task<Void, Never>] = [:]
    private var networkCancellable: AnyCancellable?
    
    // Configuration
    private let healthCheckInterval: TimeInterval = 30
    private let reconnectionDelay: TimeInterval = 5
    private let maxReconnectionAttempts = 3
    private let connectionTimeout: TimeInterval = 15
    
    private init() {
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkCancellable = NetworkMonitor.shared.networkChangePublisher
            .sink { [weak self] event in
                Task { @MainActor [weak self] in
                    await self?.handleNetworkChange(event)
                }
            }
    }
    
    // MARK: - Connection Management
    
    func registerConnection(_ connectionID: String) {
        print("🔒 SSHResilience: Registering connection \(connectionID)")
        connectionStates[connectionID] = SSHConnectionHealth(
            connectionID: connectionID,
            status: .connecting,
            lastHealthCheck: Date(),
            reconnectionAttempts: 0
        )
        
        startHealthMonitoring(for: connectionID)
    }
    
    func unregisterConnection(_ connectionID: String) {
        print("🔒 SSHResilience: Unregistering connection \(connectionID)")
        
        // Cancel tasks
        reconnectionTasks[connectionID]?.cancel()
        healthCheckTasks[connectionID]?.cancel()
        
        // Cleanup
        reconnectionTasks.removeValue(forKey: connectionID)
        healthCheckTasks.removeValue(forKey: connectionID)
        connectionStates.removeValue(forKey: connectionID)
    }
    
    func updateConnectionStatus(_ connectionID: String, status: SSHConnectionStatus) {
        guard var health = connectionStates[connectionID] else { return }
        
        let previousStatus = health.status
        health.status = status
        health.lastHealthCheck = Date()
        
        // Reset reconnection attempts on successful connection
        if status == .connected && previousStatus != .connected {
            health.reconnectionAttempts = 0
            print("✅ SSHResilience: Connection \(connectionID) restored")
        }
        
        connectionStates[connectionID] = health
        
        // Handle status changes
        if status == .disconnected && previousStatus == .connected {
            startReconnection(for: connectionID)
        }
    }
    
    // MARK: - Health Monitoring
    
    private func startHealthMonitoring(for connectionID: String) {
        healthCheckTasks[connectionID] = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
                
                if Task.isCancelled { break }
                
                await performHealthCheck(for: connectionID)
            }
        }
    }
    
    private func performHealthCheck(for connectionID: String) async {
        guard let health = connectionStates[connectionID],
              health.status == .connected else { return }
        
        // Test SSH tunnel health
        let isHealthy = await testTunnelHealth(connectionID)
        
        if !isHealthy {
            print("❌ SSHResilience: Health check failed for \(connectionID)")
            updateConnectionStatus(connectionID, status: .disconnected)
        } else {
            updateConnectionStatus(connectionID, status: .connected)
        }
    }
    
    private func testTunnelHealth(_ connectionID: String) async -> Bool {
        // Get the tunnel from SSHTunnelManager
        guard let tunnel = SSHTunnelManager.shared.getTunnel(for: connectionID) else {
            return false
        }
        
        // Test if the tunnel is still active
        return tunnel.isActive
    }
    
    // MARK: - Auto-Reconnection
    
    private func startReconnection(for connectionID: String) {
        // Cancel existing reconnection task
        reconnectionTasks[connectionID]?.cancel()
        
        reconnectionTasks[connectionID] = Task {
            guard var health = connectionStates[connectionID] else { return }
            
            print("🔄 SSHResilience: Starting reconnection for \(connectionID)")
            
            while health.reconnectionAttempts < maxReconnectionAttempts && !Task.isCancelled {
                health.reconnectionAttempts += 1
                connectionStates[connectionID] = health
                
                print("🔄 SSHResilience: Reconnection attempt \(health.reconnectionAttempts)/\(maxReconnectionAttempts) for \(connectionID)")
                
                // Wait before attempting reconnection
                try? await Task.sleep(nanoseconds: UInt64(reconnectionDelay * 1_000_000_000))
                
                if Task.isCancelled { break }
                
                // Attempt reconnection
                let success = await attemptReconnection(connectionID)
                
                if success {
                    print("✅ SSHResilience: Reconnection successful for \(connectionID)")
                    return
                }
                
                // Update health state
                if let updatedHealth = connectionStates[connectionID] {
                    health = updatedHealth
                }
            }
            
            if health.reconnectionAttempts >= maxReconnectionAttempts {
                print("❌ SSHResilience: Max reconnection attempts reached for \(connectionID)")
                updateConnectionStatus(connectionID, status: .failed)
            }
        }
    }
    
    private func attemptReconnection(_ connectionID: String) async -> Bool {
        // Notify ConnectionManager to attempt reconnection
        NotificationCenter.default.post(
            name: .sshReconnectionAttempt,
            object: connectionID
        )
        
        // Wait a moment for the reconnection attempt
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Check if reconnection was successful
        return connectionStates[connectionID]?.status == .connected
    }
    
    // MARK: - Network Change Handling
    
    private func handleNetworkChange(_ event: NetworkChangeEvent) async {
        switch event {
        case .disconnected:
            print("🌐 SSHResilience: Network disconnected - marking all connections as unstable")
            for connectionID in connectionStates.keys {
                updateConnectionStatus(connectionID, status: .unstable)
            }
            
        case .connected(let type):
            print("🌐 SSHResilience: Network reconnected (\(type)) - checking connections")
            for connectionID in connectionStates.keys {
                if connectionStates[connectionID]?.status == .unstable {
                    startReconnection(for: connectionID)
                }
            }
            
        case .typeChanged(let from, let to):
            print("🌐 SSHResilience: Network type changed \(from) → \(to) - validating connections")
            // Give connections a moment to adapt to new network
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            for connectionID in connectionStates.keys {
                await performHealthCheck(for: connectionID)
            }
        }
    }
    
    // MARK: - Timeout Management
    
    func withTimeout<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                return try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(connectionTimeout * 1_000_000_000))
                throw SSHResilienceError.connectionTimeout
            }
            
            guard let result = try await group.next() else {
                throw SSHResilienceError.unknownError
            }
            
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Supporting Types

struct SSHConnectionHealth {
    let connectionID: String
    var status: SSHConnectionStatus
    var lastHealthCheck: Date
    var reconnectionAttempts: Int
}

enum SSHConnectionStatus {
    case connecting
    case connected
    case disconnected
    case unstable
    case failed
    
    var displayName: String {
        switch self {
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .unstable: return "Unstable"
        case .failed: return "Failed"
        }
    }
    
    var isHealthy: Bool {
        return self == .connected
    }
}

enum SSHResilienceError: LocalizedError {
    case connectionTimeout
    case networkUnavailable
    case maxRetriesExceeded
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .connectionTimeout:
            return "SSH connection timed out"
        case .networkUnavailable:
            return "Network is not available"
        case .maxRetriesExceeded:
            return "Maximum reconnection attempts exceeded"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let sshReconnectionAttempt = Notification.Name("SSHReconnectionAttempt")
}