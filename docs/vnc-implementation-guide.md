# VNC Implementation Guide - LibVNCClient Wrapper

## 1. Project Setup

### Adding LibVNCClient to Your Project

#### Option A: Swift Package Manager (Recommended)
Create a Package.swift wrapper for LibVNCClient:

```swift
// Package.swift
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "LibVNCClient-Swift",
    platforms: [
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "LibVNCClient-Swift",
            targets: ["LibVNCClient-Swift"])
    ],
    targets: [
        .target(
            name: "LibVNCClient-Swift",
            dependencies: ["LibVNCClient"]),
        .systemLibrary(
            name: "LibVNCClient",
            pkgConfig: "libvncclient",
            providers: [
                .brew(["libvncserver"])
            ])
    ]
)
```

#### Option B: Manual Integration
1. Download LibVNCClient source
2. Add to project as a framework target
3. Configure build settings for visionOS

### Bridging Header Setup

Create `VirtualControlRoom-Bridging-Header.h`:

```c
#ifndef VirtualControlRoom_Bridging_Header_h
#define VirtualControlRoom_Bridging_Header_h

#import <rfb/rfbclient.h>

// Helper functions for Swift interop
typedef void (*FrameBufferUpdateCallback)(void *context, int x, int y, int w, int h);
typedef void (*ConnectionStatusCallback)(void *context, int status);

// Structure to hold Swift callbacks
typedef struct {
    void *swiftContext;
    FrameBufferUpdateCallback frameBufferUpdate;
    ConnectionStatusCallback connectionStatus;
} SwiftCallbacks;

#endif
```

## 2. Core VNC Wrapper Implementation

### VNCClient.swift - Main Wrapper Class

```swift
import Foundation
import Combine
import CoreGraphics

/// Thread-safe VNC client wrapper around LibVNCClient
public class VNCClient {
    // MARK: - Types
    
    public enum ConnectionState {
        case disconnected
        case connecting
        case authenticating
        case connected
        case failed(Error)
    }
    
    public struct FrameUpdate {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let frameBuffer: UnsafePointer<UInt8>
        let bytesPerPixel: Int
        let rowStride: Int
    }
    
    public enum VNCError: LocalizedError {
        case initializationFailed
        case connectionFailed(String)
        case authenticationFailed
        case invalidFrameBuffer
        case alreadyConnected
        
        public var errorDescription: String? {
            switch self {
            case .initializationFailed:
                return "Failed to initialize VNC client"
            case .connectionFailed(let reason):
                return "Connection failed: \(reason)"
            case .authenticationFailed:
                return "Authentication failed"
            case .invalidFrameBuffer:
                return "Invalid frame buffer"
            case .alreadyConnected:
                return "Client is already connected"
            }
        }
    }
    
    // MARK: - Properties
    
    private var client: OpaquePointer?
    private let queue = DispatchQueue(label: "com.virtualcontrolroom.vnc", qos: .userInteractive)
    private var callbacks: SwiftCallbacks?
    
    @Published public private(set) var connectionState: ConnectionState = .disconnected
    public let frameUpdateSubject = PassthroughSubject<FrameUpdate, Never>()
    
    private var isRunning = false
    private var messageLoopTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init() {
        setupCallbacks()
    }
    
    deinit {
        disconnect()
    }
    
    // MARK: - Connection Management
    
    public func connect(
        host: String,
        port: Int,
        username: String? = nil,
        password: String? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                self?.performConnect(
                    host: host,
                    port: port,
                    username: username,
                    password: password,
                    continuation: continuation
                )
            }
        }
    }
    
    private func performConnect(
        host: String,
        port: Int,
        username: String?,
        password: String?,
        continuation: CheckedContinuation<Void, Error>
    ) {
        guard client == nil else {
            continuation.resume(throwing: VNCError.alreadyConnected)
            return
        }
        
        connectionState = .connecting
        
        // Initialize VNC client with 32-bit color
        guard let newClient = rfbGetClient(8, 3, 4) else {
            connectionState = .failed(VNCError.initializationFailed)
            continuation.resume(throwing: VNCError.initializationFailed)
            return
        }
        
        client = newClient
        
        // Configure client
        configureClient(newClient, username: username, password: password)
        
        // Set server address
        let serverString = "\(host):\(port)"
        newClient.pointee.serverHost = strdup(serverString)
        
        // Initialize connection
        if rfbInitClient(newClient, nil, nil) == 0 {
            let error = VNCError.connectionFailed("Failed to initialize connection")
            connectionState = .failed(error)
            client = nil
            continuation.resume(throwing: error)
            return
        }
        
        connectionState = .connected
        isRunning = true
        startMessageLoop()
        continuation.resume()
    }
    
    public func disconnect() {
        queue.async { [weak self] in
            self?.performDisconnect()
        }
    }
    
    private func performDisconnect() {
        isRunning = false
        messageLoopTask?.cancel()
        
        if let client = client {
            rfbClientCleanup(client)
            self.client = nil
        }
        
        connectionState = .disconnected
    }
    
    // MARK: - Client Configuration
    
    private func configureClient(_ client: OpaquePointer, username: String?, password: String?) {
        let clientPtr = client.assumingMemoryBound(to: rfbClient.self)
        
        // Set callbacks
        clientPtr.pointee.MallocFrameBuffer = mallocFrameBufferCallback
        clientPtr.pointee.GotFrameBufferUpdate = gotFrameBufferUpdateCallback
        clientPtr.pointee.GetPassword = getPasswordCallback
        clientPtr.pointee.GetCredential = getCredentialCallback
        
        // Store Swift context
        callbacks?.swiftContext = Unmanaged.passUnretained(self).toOpaque()
        clientPtr.pointee.clientData = &callbacks
        
        // Set authentication data if provided
        if let username = username {
            clientPtr.pointee.userName = strdup(username)
        }
        if let password = password {
            clientPtr.pointee.password = strdup(password)
        }
        
        // Configure other options
        clientPtr.pointee.canHandleNewFBSize = 1
        clientPtr.pointee.appData.encodingsString = "tight ultra copyrect hextile zlib corre rre raw"
    }
    
    // MARK: - Message Loop
    
    private func startMessageLoop() {
        messageLoopTask = Task { [weak self] in
            await self?.runMessageLoop()
        }
    }
    
    private func runMessageLoop() async {
        while isRunning, let client = client {
            queue.async { [weak self] in
                guard self?.isRunning == true else { return }
                
                let timeout = 50000 // 50ms in microseconds
                if WaitForMessage(client, timeout) > 0 {
                    if !HandleRFBServerMessage(client) {
                        self?.handleConnectionError()
                    }
                }
            }
            
            // Small delay to prevent busy waiting
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
    }
    
    private func handleConnectionError() {
        let error = VNCError.connectionFailed("Lost connection to server")
        connectionState = .failed(error)
        performDisconnect()
    }
    
    // MARK: - Input Handling
    
    public func sendKeyEvent(keysym: UInt32, down: Bool) {
        queue.async { [weak self] in
            guard let client = self?.client else { return }
            SendKeyEvent(client, keysym, down ? 1 : 0)
        }
    }
    
    public func sendPointerEvent(x: Int, y: Int, buttonMask: Int) {
        queue.async { [weak self] in
            guard let client = self?.client else { return }
            SendPointerEvent(client, Int32(x), Int32(y), Int32(buttonMask))
        }
    }
    
    // MARK: - Frame Buffer Access
    
    public func getCurrentFrameBuffer() -> CGImage? {
        queue.sync { [weak self] in
            self?.createCGImage()
        }
    }
    
    private func createCGImage() -> CGImage? {
        guard let client = client else { return nil }
        let clientPtr = client.assumingMemoryBound(to: rfbClient.self)
        
        let width = Int(clientPtr.pointee.width)
        let height = Int(clientPtr.pointee.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        guard let frameBuffer = clientPtr.pointee.frameBuffer else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        guard let context = CGContext(
            data: frameBuffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        return context.makeImage()
    }
}

// MARK: - C Callbacks

private func mallocFrameBufferCallback(client: OpaquePointer?) -> UInt8 {
    guard let client = client else { return 0 }
    let clientPtr = client.assumingMemoryBound(to: rfbClient.self)
    
    let width = Int(clientPtr.pointee.width)
    let height = Int(clientPtr.pointee.height)
    let bytesPerPixel = 4
    let size = width * height * bytesPerPixel
    
    // Free existing buffer if any
    if let existingBuffer = clientPtr.pointee.frameBuffer {
        free(existingBuffer)
    }
    
    // Allocate new buffer
    clientPtr.pointee.frameBuffer = malloc(size)?.assumingMemoryBound(to: UInt8.self)
    
    return clientPtr.pointee.frameBuffer != nil ? 1 : 0
}

private func gotFrameBufferUpdateCallback(
    client: OpaquePointer?,
    x: Int32,
    y: Int32,
    w: Int32,
    h: Int32
) {
    guard let client = client else { return }
    let clientPtr = client.assumingMemoryBound(to: rfbClient.self)
    
    guard let callbacksPtr = clientPtr.pointee.clientData?.assumingMemoryBound(to: SwiftCallbacks.self),
          let swiftContext = callbacksPtr.pointee.swiftContext else { return }
    
    let vncClient = Unmanaged<VNCClient>.fromOpaque(swiftContext).takeUnretainedValue()
    
    guard let frameBuffer = clientPtr.pointee.frameBuffer else { return }
    
    let update = VNCClient.FrameUpdate(
        x: Int(x),
        y: Int(y),
        width: Int(w),
        height: Int(h),
        frameBuffer: frameBuffer,
        bytesPerPixel: 4,
        rowStride: Int(clientPtr.pointee.width) * 4
    )
    
    DispatchQueue.main.async {
        vncClient.frameUpdateSubject.send(update)
    }
}

private func getPasswordCallback(client: OpaquePointer?) -> UnsafeMutablePointer<CChar>? {
    guard let client = client else { return nil }
    let clientPtr = client.assumingMemoryBound(to: rfbClient.self)
    
    // Return the stored password if available
    return clientPtr.pointee.password
}

private func getCredentialCallback(
    client: OpaquePointer?,
    credentialType: Int32
) -> UInt8 {
    // Handle credential requests
    // For MVP, we'll use the stored username/password
    return 1
}

// MARK: - Callback Setup

extension VNCClient {
    private func setupCallbacks() {
        callbacks = SwiftCallbacks(
            swiftContext: nil,
            frameBufferUpdate: nil,
            connectionStatus: nil
        )
    }
}
```

## 3. Integration with Connection Manager

### VNCConnectionAdapter.swift

```swift
import Foundation
import Combine

/// Adapts the VNCClient to work with the ConnectionManager architecture
class VNCConnectionAdapter: NSObject {
    private let vncClient: VNCClient
    private let connectionId: UUID
    private var cancellables = Set<AnyCancellable>()
    
    init(connectionId: UUID) {
        self.connectionId = connectionId
        self.vncClient = VNCClient()
        super.init()
        setupBindings()
    }
    
    private func setupBindings() {
        // Monitor connection state
        vncClient.$connectionState
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)
        
        // Handle frame updates
        vncClient.frameUpdateSubject
            .sink { [weak self] update in
                self?.handleFrameUpdate(update)
            }
            .store(in: &cancellables)
    }
    
    func connect(
        to localPort: Int,
        username: String,
        password: String
    ) async throws {
        try await vncClient.connect(
            host: "localhost",
            port: localPort,
            username: username,
            password: password
        )
    }
    
    func disconnect() {
        vncClient.disconnect()
    }
    
    private func handleStateChange(_ state: VNCClient.ConnectionState) {
        // Notify connection manager of state changes
        NotificationCenter.default.post(
            name: .vncConnectionStateChanged,
            object: nil,
            userInfo: [
                "connectionId": connectionId,
                "state": state
            ]
        )
    }
    
    private func handleFrameUpdate(_ update: VNCClient.FrameUpdate) {
        // Convert to texture and notify rendering engine
        if let texture = convertToMetalTexture(update) {
            NotificationCenter.default.post(
                name: .vncFrameUpdated,
                object: nil,
                userInfo: [
                    "connectionId": connectionId,
                    "texture": texture,
                    "region": CGRect(
                        x: update.x,
                        y: update.y,
                        width: update.width,
                        height: update.height
                    )
                ]
            )
        }
    }
    
    private func convertToMetalTexture(_ update: VNCClient.FrameUpdate) -> MTLTexture? {
        // Implementation depends on your Metal setup
        // This is a placeholder
        return nil
    }
}

extension Notification.Name {
    static let vncConnectionStateChanged = Notification.Name("vncConnectionStateChanged")
    static let vncFrameUpdated = Notification.Name("vncFrameUpdated")
}
```

## 4. Frame Buffer to RealityKit Integration

### VNCTextureProvider.swift

```swift
import Metal
import MetalKit
import RealityKit
import CoreGraphics

class VNCTextureProvider: ObservableObject {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureLoader: MTKTextureLoader
    
    @Published var currentTexture: MTLTexture?
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw RenderError.noMetalDevice
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.textureLoader = MTKTextureLoader(device: device)
    }
    
    func updateFromVNCClient(_ client: VNCClient) {
        guard let cgImage = client.getCurrentFrameBuffer() else { return }
        
        do {
            currentTexture = try textureLoader.newTexture(
                cgImage: cgImage,
                options: [
                    .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                    .textureStorageMode: MTLStorageMode.private.rawValue
                ]
            )
        } catch {
            print("Failed to create texture: \(error)")
        }
    }
    
    func updateFromFrameUpdate(_ update: VNCClient.FrameUpdate) {
        // Create texture descriptor
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: update.width,
            height: update.height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead]
        
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return }
        
        // Copy frame buffer data to texture
        let bytesPerRow = update.rowStride
        texture.replace(
            region: MTLRegionMake2D(0, 0, update.width, update.height),
            mipmapLevel: 0,
            withBytes: update.frameBuffer,
            bytesPerRow: bytesPerRow
        )
        
        DispatchQueue.main.async {
            self.currentTexture = texture
        }
    }
}
```

## 5. Testing the Implementation

### VNCClientTests.swift

```swift
import XCTest
@testable import VirtualControlRoom

class VNCClientTests: XCTestCase {
    var client: VNCClient!
    
    override func setUp() {
        super.setUp()
        client = VNCClient()
    }
    
    override func tearDown() {
        client.disconnect()
        client = nil
        super.tearDown()
    }
    
    func testConnectionLifecycle() async throws {
        // Test connection
        let expectation = expectation(description: "Connection established")
        
        var states: [VNCClient.ConnectionState] = []
        let cancellable = client.$connectionState.sink { state in
            states.append(state)
            if case .connected = state {
                expectation.fulfill()
            }
        }
        
        // Connect to test server
        try await client.connect(
            host: "localhost",
            port: 5900,
            username: "test",
            password: "test"
        )
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify state transitions
        XCTAssertEqual(states.count, 3) // disconnected -> connecting -> connected
        
        cancellable.cancel()
    }
    
    func testFrameBufferUpdates() async throws {
        let updateExpectation = expectation(description: "Frame buffer updated")
        
        let cancellable = client.frameUpdateSubject.sink { update in
            XCTAssertGreaterThan(update.width, 0)
            XCTAssertGreaterThan(update.height, 0)
            updateExpectation.fulfill()
        }
        
        try await client.connect(host: "localhost", port: 5900)
        
        await fulfillment(of: [updateExpectation], timeout: 10.0)
        
        cancellable.cancel()
    }
}
```

## 6. Build Configuration

### Package Dependencies

Add to your `Package.swift` or Xcode project:

```swift
dependencies: [
    .package(url: "https://github.com/LibVNC/libvncserver.git", from: "0.9.14"),
    // Or use a system library
]
```

### Build Settings

In your Xcode project:
1. Add `VirtualControlRoom-Bridging-Header.h` to "Objective-C Bridging Header"
2. Add LibVNCClient library to "Link Binary with Libraries"
3. Set "Enable Modules" to YES
4. Add any required library search paths

## 7. Performance Optimizations

### Async Frame Processing

```swift
actor FrameProcessor {
    private var processingQueue = [VNCClient.FrameUpdate]()
    private let maxQueueSize = 3
    
    func enqueue(_ update: VNCClient.FrameUpdate) {
        if processingQueue.count >= maxQueueSize {
            processingQueue.removeFirst()
        }
        processingQueue.append(update)
    }
    
    func processNext() async -> VNCClient.FrameUpdate? {
        guard !processingQueue.isEmpty else { return nil }
        return processingQueue.removeFirst()
    }
}
```

## 8. Error Handling and Recovery

### Connection Recovery

```swift
extension VNCConnectionAdapter {
    func setupAutoReconnect() {
        vncClient.$connectionState
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] state in
                if case .failed = state {
                    self?.attemptReconnect()
                }
            }
            .store(in: &cancellables)
    }
    
    private func attemptReconnect() {
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            // Attempt reconnection logic here
        }
    }
}
```

This implementation provides a solid foundation for the VNC functionality in your MVP. The wrapper handles the complex C interop while providing a clean Swift interface that integrates well with your visionOS architecture. 