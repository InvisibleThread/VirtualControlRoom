import Foundation
import Network
import Combine

/// Monitors network connectivity and notifies about changes
@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected = false
    @Published var connectionType: NWInterface.InterfaceType = .other
    @Published var isExpensive = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    // Network change notifications
    let networkChangePublisher = PassthroughSubject<NetworkChangeEvent, Never>()
    
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
    
    deinit {
        monitor.cancel()
    }
}

enum NetworkChangeEvent {
    case connected(NWInterface.InterfaceType)
    case disconnected
    case typeChanged(from: NWInterface.InterfaceType, to: NWInterface.InterfaceType)
}