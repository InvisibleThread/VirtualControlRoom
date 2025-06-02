# Virtual Control Room - Technical Implementation Guide

## SSH Library Selection

### Recommended: SwiftNIO SSH
SwiftNIO SSH is Apple's official SSH implementation built on SwiftNIO, providing excellent performance and native Swift integration.

```swift
import NIOCore
import NIOPosix
import NIOSSH

class SSHTunnelService {
    private var channel: Channel?
    private let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    
    func createTunnel(
        bastionHost: String,
        bastionPort: Int = 22,
        username: String,
        password: String,
        otp: String,
        localPort: Int,
        remoteHost: String,
        remotePort: Int
    ) async throws {
        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: PasswordAuthenticationDelegate(
                                username: username,
                                password: password + otp
                            ),
                            serverAuthDelegate: AcceptAllServerAuthenticationDelegate()
                        )),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )
                ])
            }
        
        self.channel = try await bootstrap.connect(
            host: bastionHost,
            port: bastionPort
        ).get()
        
        // Set up port forwarding
        try await setupPortForwarding(
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort
        )
    }
}
```

## VNC Client Implementation

### Option 1: LibVNCClient Wrapper
Create a Swift wrapper around the C-based LibVNCClient:

```swift
import Foundation

class VNCClient {
    private var client: OpaquePointer?
    private let frameUpdateHandler: (VNCFrameUpdate) -> Void
    
    init(frameUpdateHandler: @escaping (VNCFrameUpdate) -> Void) {
        self.frameUpdateHandler = frameUpdateHandler
    }
    
    func connect(host: String, port: Int, username: String, password: String) async throws {
        // Initialize rfbClient
        client = rfbGetClient(8, 3, 4) // 8 bits per sample, 3 samples, 4 bytes
        
        guard let client = client else {
            throw VNCError.initializationFailed
        }
        
        // Set callbacks
        client.pointee.MallocFrameBuffer = { client in
            // Allocate framebuffer
            return 1
        }
        
        client.pointee.GotFrameBufferUpdate = { client, x, y, w, h in
            // Handle frame updates
        }
        
        // Connect
        let serverString = "\(host):\(port)"
        rfbInitClient(client, nil, serverString)
    }
}
```

### Option 2: Pure Swift VNC Implementation
A lightweight VNC client implementation in pure Swift:

```swift
class SwiftVNCClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "vnc.client.queue")
    
    func connect(to endpoint: NWEndpoint, username: String, password: String) {
        connection = NWConnection(to: endpoint, using: .tcp)
        
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.performHandshake()
            case .failed(let error):
                print("Connection failed: \(error)")
            default:
                break
            }
        }
        
        connection?.start(queue: queue)
    }
    
    private func performHandshake() {
        // RFB protocol version
        send(data: "RFB 003.008\n".data(using: .utf8)!)
        
        // Continue with VNC handshake...
    }
}
```

## AR Window Rendering with RealityKit

```swift
import RealityKit
import SwiftUI

struct VNCWindowView: View {
    @StateObject private var windowModel: VNCWindowModel
    
    var body: some View {
        RealityView { content in
            // Create a plane entity for the VNC display
            let mesh = MeshResource.generatePlane(
                width: windowModel.width,
                height: windowModel.height
            )
            
            // Create material with VNC framebuffer texture
            var material = UnlitMaterial()
            if let texture = windowModel.currentFrameTexture {
                material.color = .init(texture: .init(texture))
            }
            
            let entity = ModelEntity(mesh: mesh, materials: [material])
            
            // Add interaction components
            entity.components.set(InputTargetComponent())
            entity.components.set(CollisionComponent(shapes: [.generateBox(size: [windowModel.width, windowModel.height, 0.01])]))
            
            content.add(entity)
        } update: { content in
            // Update texture when VNC frame changes
            if let entity = content.entities.first as? ModelEntity,
               let texture = windowModel.currentFrameTexture {
                var material = UnlitMaterial()
                material.color = .init(texture: .init(texture))
                entity.model?.materials = [material]
            }
        }
        .onTapGesture { location in
            windowModel.handleTap(at: location)
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    windowModel.handleDrag(value: value)
                }
        )
    }
}
```

## Port Management System

```swift
class PortManager {
    private var allocatedPorts: Set<Int> = []
    private let portRange = 10000...20000
    private let queue = DispatchQueue(label: "port.manager.queue")
    
    func allocatePort() throws -> Int {
        try queue.sync {
            guard let availablePort = findAvailablePort() else {
                throw PortError.noAvailablePorts
            }
            
            allocatedPorts.insert(availablePort)
            return availablePort
        }
    }
    
    func releasePort(_ port: Int) {
        queue.sync {
            allocatedPorts.remove(port)
        }
    }
    
    private func findAvailablePort() -> Int? {
        for port in portRange {
            if !allocatedPorts.contains(port) && isPortAvailable(port) {
                return port
            }
        }
        return nil
    }
    
    private func isPortAvailable(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(socketFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        return result == 0
    }
}
```

## Keychain Integration

```swift
import Security

class KeychainService {
    enum KeychainError: Error {
        case duplicateItem
        case itemNotFound
        case unexpectedData
        case unhandledError(status: OSStatus)
    }
    
    func saveCredentials(
        username: String,
        password: String,
        server: String,
        account: String
    ) throws {
        let passwordData = password.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrAccount as String: account,
            kSecAttrServer as String: server,
            kSecValueData as String: passwordData,
            kSecAttrProtocol as String: kSecAttrProtocolSSH,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem {
                try updateCredentials(username: username, password: password, server: server, account: account)
            } else {
                throw KeychainError.unhandledError(status: status)
            }
            return
        }
    }
    
    func retrieveCredentials(server: String, account: String) throws -> (username: String, password: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrAccount as String: account,
            kSecAttrProtocol as String: kSecAttrProtocolSSH,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            throw KeychainError.itemNotFound
        }
        
        guard let existingItem = item as? [String: Any],
              let passwordData = existingItem[kSecValueData as String] as? Data,
              let password = String(data: passwordData, encoding: .utf8),
              let account = existingItem[kSecAttrAccount as String] as? String
        else {
            throw KeychainError.unexpectedData
        }
        
        return (username: account, password: password)
    }
}
```

## Connection State Management

```swift
enum ConnectionState {
    case disconnected
    case connecting
    case authenticating
    case establishingTunnel
    case connectingVNC
    case connected
    case error(Error)
}

@MainActor
class ConnectionViewModel: ObservableObject {
    @Published var state: ConnectionState = .disconnected
    @Published var progress: Double = 0.0
    
    private let connectionManager: ConnectionManager
    private let authManager: AuthenticationManager
    
    func connect(to profile: ConnectionProfile) async {
        state = .connecting
        progress = 0.1
        
        do {
            // Get credentials
            state = .authenticating
            progress = 0.3
            
            let credentials = try await authManager.getCredentials(for: profile)
            
            // Establish SSH tunnel
            state = .establishingTunnel
            progress = 0.5
            
            let tunnel = try await connectionManager.createSSHTunnel(
                profile: profile,
                credentials: credentials
            )
            
            // Connect VNC
            state = .connectingVNC
            progress = 0.8
            
            let vncConnection = try await connectionManager.connectVNC(
                through: tunnel,
                profile: profile
            )
            
            state = .connected
            progress = 1.0
            
        } catch {
            state = .error(error)
            progress = 0.0
        }
    }
}
```

## Memory-Efficient Frame Buffer Handling

```swift
class VNCFrameBufferManager {
    private let metalDevice: MTLDevice
    private let textureCache: CVMetalTextureCache
    private var currentTexture: MTLTexture?
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.noMetalDevice
        }
        self.metalDevice = device
        
        var cache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        
        guard result == kCVReturnSuccess, let textureCache = cache else {
            throw RenderError.textureCacheCreationFailed
        }
        
        self.textureCache = textureCache
    }
    
    func updateFrameBuffer(_ pixelBuffer: CVPixelBuffer) throws -> MTLTexture {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard result == kCVReturnSuccess,
              let cvTexture = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            throw RenderError.textureCreationFailed
        }
        
        currentTexture = texture
        return texture
    }
}
```

## Performance Monitoring

```swift
class PerformanceMonitor {
    private var frameRates: [Double] = []
    private var lastFrameTime: CFTimeInterval = 0
    private let maxSamples = 60
    
    @Published var currentFPS: Double = 0
    @Published var averageFPS: Double = 0
    @Published var networkLatency: Double = 0
    
    func recordFrame() {
        let currentTime = CACurrentMediaTime()
        if lastFrameTime > 0 {
            let frameTime = currentTime - lastFrameTime
            let fps = 1.0 / frameTime
            
            frameRates.append(fps)
            if frameRates.count > maxSamples {
                frameRates.removeFirst()
            }
            
            currentFPS = fps
            averageFPS = frameRates.reduce(0, +) / Double(frameRates.count)
        }
        lastFrameTime = currentTime
    }
    
    func recordNetworkLatency(_ latency: TimeInterval) {
        networkLatency = latency * 1000 // Convert to milliseconds
    }
}
```

## Error Handling Strategy

```swift
enum VirtualControlRoomError: LocalizedError {
    case sshConnectionFailed(reason: String)
    case authenticationFailed(service: String)
    case vncConnectionFailed(reason: String)
    case portAllocationFailed
    case keychainAccessDenied
    case networkTimeout
    case invalidConfiguration(field: String)
    
    var errorDescription: String? {
        switch self {
        case .sshConnectionFailed(let reason):
            return "SSH connection failed: \(reason)"
        case .authenticationFailed(let service):
            return "Authentication failed for \(service)"
        case .vncConnectionFailed(let reason):
            return "VNC connection failed: \(reason)"
        case .portAllocationFailed:
            return "Could not allocate local port for tunnel"
        case .keychainAccessDenied:
            return "Access to stored credentials was denied"
        case .networkTimeout:
            return "Network connection timed out"
        case .invalidConfiguration(let field):
            return "Invalid configuration: \(field)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .sshConnectionFailed:
            return "Check your network connection and bastion server details"
        case .authenticationFailed:
            return "Verify your credentials and try again"
        case .vncConnectionFailed:
            return "Ensure the VNC server is running and accessible"
        case .portAllocationFailed:
            return "Close some connections and try again"
        case .keychainAccessDenied:
            return "Grant keychain access in Settings"
        case .networkTimeout:
            return "Check your internet connection"
        case .invalidConfiguration:
            return "Review and correct the connection profile settings"
        }
    }
}
``` 