import Foundation
import Network
import Combine

/// Monitors network connectivity and provides performance-based optimization
@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType = .other
    @Published var isExpensive = false
    @Published var connectionQuality: ConnectionQuality = .unknown
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    // Network change notifications
    let networkChangePublisher = PassthroughSubject<NetworkChangeEvent, Never>()
    let qualityChangePublisher = PassthroughSubject<ConnectionQuality, Never>()
    
    // Performance measurement
    private var performanceCache: [String: ConnectionPerformance] = [:]
    private let performanceCacheTimeout: TimeInterval = 300 // 5 minutes
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.updateNetworkStatus(path)
            }
        }
        monitor.start(queue: queue)
    }
    
    private func updateNetworkStatus(_ path: NWPath) {
        let wasConnected = isConnected
        let previousType = connectionType
        
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        
        // Determine connection type
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wiredEthernet
        } else {
            connectionType = .other
        }
        
        // Notify about changes
        if wasConnected != isConnected {
            let event: NetworkChangeEvent = isConnected ? .connected(connectionType) : .disconnected
            networkChangePublisher.send(event)
            print("🌐 Network \(isConnected ? "connected" : "disconnected") - \(connectionType)")
        } else if previousType != connectionType && isConnected {
            networkChangePublisher.send(.typeChanged(from: previousType, to: connectionType))
            print("🌐 Network type changed: \(previousType) → \(connectionType)")
        }
    }
    
    // MARK: - Performance Measurement
    
    /// Measure connection performance to a specific host
    func measurePerformance(to host: String, port: Int) async -> ConnectionPerformance {
        let cacheKey = "\(host):\(port)"
        
        // Check cache first
        if let cached = performanceCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < performanceCacheTimeout {
            print("📊 Using cached performance for \(host):\(port)")
            return cached
        }
        
        print("📊 Measuring connection performance to \(host):\(port)")
        
        // Measure latency
        let latency = await measureLatency(to: host, port: port)
        
        // Estimate bandwidth (simple test)
        let bandwidth = await estimateBandwidth(to: host, port: port)
        
        // Calculate quality tier
        let quality = determineConnectionQuality(latency: latency, bandwidth: bandwidth)
        
        let performance = ConnectionPerformance(
            host: host,
            port: port,
            latency: latency,
            bandwidth: bandwidth,
            quality: quality,
            timestamp: Date()
        )
        
        // Cache the result
        performanceCache[cacheKey] = performance
        
        // Update published quality if this becomes the active connection
        if connectionQuality != quality {
            connectionQuality = quality
            qualityChangePublisher.send(quality)
        }
        
        print("📊 Performance result for \(host):\(port) - Latency: \(latency)ms, Quality: \(quality)")
        
        return performance
    }
    
    /// Measure round-trip latency to host
    private func measureLatency(to host: String, port: Int) async -> Double {
        return await withCheckedContinuation { continuation in
            let startTime = CFAbsoluteTimeGetCurrent()
            
            // Create a simple TCP connection test
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .tcp
            )
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // Convert to ms
                    connection.cancel()
                    continuation.resume(returning: latency)
                case .failed:
                    connection.cancel()
                    continuation.resume(returning: 999.0) // High latency for failed connections
                default:
                    break
                }
            }
            
            connection.start(queue: queue)
            
            // Timeout after 10 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                connection.cancel()
                continuation.resume(returning: 999.0)
            }
        }
    }
    
    /// Estimate bandwidth (simplified test)
    private func estimateBandwidth(to host: String, port: Int) async -> Double {
        // For now, return a reasonable estimate based on connection type
        // In a full implementation, this would send test data
        
        switch connectionType {
        case .wifi:
            return isExpensive ? 5.0 : 25.0 // 5 Mbps for hotspot, 25 Mbps for WiFi
        case .cellular:
            return 2.0 // 2 Mbps for cellular
        case .wiredEthernet:
            return 100.0 // 100 Mbps for wired
        default:
            return 10.0 // 10 Mbps default
        }
    }
    
    /// Determine connection quality based on measured performance
    private func determineConnectionQuality(latency: Double, bandwidth: Double) -> ConnectionQuality {
        // High quality: Low latency + high bandwidth
        if latency < 50 && bandwidth > 20 {
            return .excellent
        }
        
        // Good quality: Moderate latency + good bandwidth
        if latency < 100 && bandwidth > 10 {
            return .good
        }
        
        // Fair quality: Higher latency or lower bandwidth
        if latency < 200 && bandwidth > 5 {
            return .fair
        }
        
        // Poor quality: High latency or very low bandwidth
        return .poor
    }
    
    /// Clear performance cache
    func clearPerformanceCache() {
        performanceCache.removeAll()
        print("📊 Performance cache cleared")
    }
    
    deinit {
        monitor.cancel()
    }
}

// MARK: - Supporting Types

struct ConnectionPerformance {
    let host: String
    let port: Int
    let latency: Double // milliseconds
    let bandwidth: Double // Mbps
    let quality: ConnectionQuality
    let timestamp: Date
}

enum ConnectionQuality: String, CaseIterable {
    case unknown = "unknown"
    case poor = "poor"
    case fair = "fair" 
    case good = "good"
    case excellent = "excellent"
    
    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }
    
    var emoji: String {
        switch self {
        case .unknown: return "❓"
        case .poor: return "🔴"
        case .fair: return "🟡"
        case .good: return "🟢"
        case .excellent: return "⚡"
        }
    }
}

enum NetworkChangeEvent {
    case connected(NWInterface.InterfaceType)
    case disconnected
    case typeChanged(from: NWInterface.InterfaceType, to: NWInterface.InterfaceType)
    case qualityChanged(ConnectionQuality)
}