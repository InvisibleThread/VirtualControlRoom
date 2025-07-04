import Foundation

/// Manages dynamic port allocation for SSH tunnels
@MainActor
class PortManager: ObservableObject {
    static let shared = PortManager()
    
    // Track allocated ports to avoid conflicts
    private var allocatedPorts: Set<Int> = []
    
    // Port range for dynamic allocation
    private let minPort = 20000
    private let maxPort = 30000
    
    private init() {
        print("🔌 PortManager initialized")
    }
    
    /// Allocate a free port for SSH tunnel
    func allocatePort() throws -> Int {
        // Try to find an available port in the range
        for _ in 0..<1000 { // Max 1000 attempts
            let port = Int.random(in: minPort...maxPort)
            
            if !allocatedPorts.contains(port) && isPortAvailable(port) {
                allocatedPorts.insert(port)
                print("🔌 Allocated port: \(port)")
                return port
            }
        }
        
        throw PortManagerError.noAvailablePorts
    }
    
    /// Release a previously allocated port
    func releasePort(_ port: Int) {
        allocatedPorts.remove(port)
        print("🔌 Released port: \(port)")
    }
    
    /// Check if a specific port is available on the system
    private func isPortAvailable(_ port: Int) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket != -1 else { return false }
        defer { Darwin.close(socket) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return result == 0
    }
    
    /// Reset all allocated ports (useful for cleanup)
    func resetAllocations() {
        allocatedPorts.removeAll()
        print("🔌 Reset all port allocations")
    }
}

enum PortManagerError: LocalizedError {
    case noAvailablePorts
    
    var errorDescription: String? {
        switch self {
        case .noAvailablePorts:
            return "No available ports found in range 20000-30000"
        }
    }
}