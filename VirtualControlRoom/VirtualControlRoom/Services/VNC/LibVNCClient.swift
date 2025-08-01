import Foundation
import SwiftUI

/// VNC client implementation using LibVNCClient C library
class LibVNCClient: NSObject, ObservableObject {
    @Published var connectionState: VNCConnectionState = .disconnected
    @Published var framebuffer: CGImage?
    @Published var screenSize: CGSize = .zero
    @Published var lastError: String?
    @Published var passwordRequired: Bool = false
    @Published var windowIsOpen: Bool = false
    
    private var vncWrapper: LibVNCWrapper?
    private var savedPassword: String?
    private var pendingConnection: (host: String, port: Int, username: String?)?
    var passwordHandler: ((String) -> Void)?
    private var connectionTimer: Timer?
    private let connectionTimeout: TimeInterval = 30.0 // 30 seconds timeout
    
    // Connection ID for diagnostics
    private var connectionID: String?
    private let diagnosticsManager = ConnectionDiagnosticsManager.shared
    
    override init() {
        super.init()
        setupVNCWrapper()
    }
    
    /// Set the connection ID for diagnostics logging
    func setConnectionID(_ id: String) {
        connectionID = id
        Task { @MainActor in
            diagnosticsManager.logVNCEvent("VNC client initialized", level: .debug, connectionID: id)
        }
    }
    
    private func setupVNCWrapper() {
        // Only create wrapper if we don't have one - Sprint 0.5 approach
        if vncWrapper == nil {
            vncWrapper = LibVNCWrapper()
            vncWrapper?.delegate = self
        }
    }
    
    func connect(host: String, port: Int, username: String?, password: String?) async {
        // Use existing connection ID or fallback to host:port format for diagnostics
        if connectionID == nil {
            connectionID = "\(host)_\(port)"
        }
        
        Task { @MainActor in
            diagnosticsManager.logVNCEvent("Starting VNC connection to \(host):\(port)", level: .info, connectionID: connectionID!)
        }
        print("🔌 VNC: connect() called with host: \(host), port: \(port)")
        
        // Log current state
        Task { @MainActor in
            diagnosticsManager.logVNCEvent("Current connection state: \(connectionState)", level: .debug, connectionID: connectionID!)
        }
        print("🔌 VNC: Current connectionState: \(connectionState)")
        
        // Ensure we're not already connecting
        if connectionState == .connecting {
            Task { @MainActor in
                diagnosticsManager.logVNCEvent("Connection already in progress, ignoring new request", level: .warning, connectionID: connectionID!)
            }
            print("⚠️ VNC: Already connecting, ignoring new connection request")
            return
        }
        
        // Disconnect any existing connection first (but preserve password for retry)
        if connectionState == .connected {
            Task { @MainActor in
                diagnosticsManager.logVNCEvent("Disconnecting existing connection for new attempt", level: .info, connectionID: connectionID!)
            }
            print("🔄 VNC: Disconnecting existing connection for new attempt")
            let tempPassword = savedPassword  // Preserve password
            vncWrapper?.disconnect()
            savedPassword = tempPassword  // Restore password
            
            await MainActor.run {
                connectionState = .disconnected
                framebuffer = nil
                screenSize = .zero
                // Don't clear lastError - let new connection set it
                passwordRequired = false
            }
        }
        
        // Ensure we have a wrapper (Sprint 0.5 approach - reuse existing)
        setupVNCWrapper()
        
        await MainActor.run {
            connectionState = .connecting
            lastError = nil
            passwordRequired = false
        }
        
        // Save connection details for retry
        pendingConnection = (host, port, username)
        
        // Save password for callback
        savedPassword = password
        print("🔐 VNC: LibVNCClient savedPassword set to: \(password != nil ? "[PASSWORD_SET]" : "[NIL]")")
        
        // Connect using the wrapper
        guard let wrapper = vncWrapper else {
            Task { @MainActor in
                diagnosticsManager.logVNCEvent("VNC wrapper not initialized", level: .error, connectionID: connectionID!)
            }
            print("❌ VNC: wrapper is nil!")
            await MainActor.run {
                connectionState = .failed("VNC wrapper not initialized")
                lastError = "Internal error: VNC wrapper not initialized"
            }
            return
        }
        
        Task { @MainActor in
            diagnosticsManager.logVNCEvent("VNC wrapper ready, initiating connection", level: .info, connectionID: connectionID!)
        }
        print("✅ VNC: wrapper exists, proceeding with connection")
        
        // Start timeout timer after we initiate the connection
        await MainActor.run {
            connectionTimer?.invalidate()
            connectionTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.connectionState == .connecting {
                        if let connectionID = self.connectionID {
                            self.diagnosticsManager.logVNCEvent("VNC connection timeout after 15 seconds - server not responding", level: .error, connectionID: connectionID)
                        }
                        self.connectionState = .failed("Connection timeout: Server not responding")
                        self.lastError = "Connection timed out after 15 seconds. The server may be unreachable or not responding."
                        self.vncWrapper?.disconnect()
                    }
                }
            }
        }
        
        // Note: LibVNCWrapper handles connection on background queue
        Task { @MainActor in
            diagnosticsManager.logVNCEvent("Initiating VNC connection with wrapper", level: .info, connectionID: connectionID!)
        }
        print("🔐 VNC: Calling wrapper.connect with password: \(password != nil ? "[PASSWORD_SET]" : "[NIL]")")
        let connected = wrapper.connect(toHost: host, port: port, username: username, password: password)
        print("🔐 VNC: wrapper.connect returned: \(connected)")
        
        if !connected {
            Task { @MainActor in
                diagnosticsManager.logVNCEvent("VNC wrapper failed to initiate connection", level: .error, connectionID: connectionID!)
            }
            print("❌ VNC: wrapper.connect returned false")
            await MainActor.run {
                connectionTimer?.invalidate()
                connectionTimer = nil
                connectionState = .failed("Failed to initiate connection")
                lastError = "Failed to start VNC connection. Please check the server address and port."
            }
        } else {
            Task { @MainActor in
                diagnosticsManager.logVNCEvent("VNC connection initiated successfully, waiting for response", level: .success, connectionID: connectionID!)
            }
            print("✅ VNC: wrapper.connect returned true, connection initiated")
        }
    }
    
    func retryWithPassword(_ password: String) async {
        print("🔄 VNC: Retrying with password...")
        guard let pending = pendingConnection else { 
            print("❌ VNC: No pending connection to retry")
            return 
        }
        
        // Reset state first
        await MainActor.run {
            passwordRequired = false
            connectionState = .disconnected  // Reset to disconnected to allow new connection
        }
        
        // Save the password 
        savedPassword = password
        
        // Start a fresh connection attempt with the password
        await connect(host: pending.host, port: pending.port, username: pending.username, password: password)
    }
    
    func disconnect() {
        print("🔌 VNC: Manual disconnect requested")
        
        // Cancel any pending timers first
        Task { @MainActor in
            connectionTimer?.invalidate()
            connectionTimer = nil
        }
        
        vncWrapper?.disconnect()
        savedPassword = nil
        pendingConnection = nil
        
        // Instead of setting state directly, trigger the delegate method
        // This ensures proper state transitions in ConnectionManager
        print("🧹 VNC: Performing connection cleanup")
        vncDidDisconnect()
        
        print("🔔 VNC: Notifying delegate about disconnection")
        // Additional cleanup logging for debugging
        print("🧹 VNC: Performing connection cleanup")
    }
    
    func sendKeyEvent(keysym: UInt32, down: Bool) {
        print("🔵 LibVNCClient: sendKeyEvent(keysym:0x\(String(keysym, radix: 16).uppercased()), down:\(down))")
        vncWrapper?.sendKeyEvent(keysym, down: down)
    }
    
    func sendPointerEvent(x: Int, y: Int, buttonMask: Int) {
        print("🔵 LibVNCClient: sendPointerEvent(x:\(x), y:\(y), buttonMask:\(buttonMask))")
        vncWrapper?.sendPointerEvent(x, y: y, buttonMask: buttonMask)
    }
}

// MARK: - LibVNCWrapperDelegate
extension LibVNCClient: LibVNCWrapperDelegate {
    func vncDidConnect() {
        Task { @MainActor in
            connectionTimer?.invalidate()
            connectionTimer = nil
            connectionState = .connected
            lastError = nil
            
            if let connectionID = connectionID {
                diagnosticsManager.logVNCEvent("VNC connection established successfully", level: .success, connectionID: connectionID)
            }
            print("✅ VNC: Connected successfully via LibVNCClient")
        }
    }
    
    func vncDidDisconnect() {
        Task { @MainActor in
            connectionState = .disconnected
            framebuffer = nil
            screenSize = .zero
            
            if let connectionID = connectionID {
                diagnosticsManager.logVNCEvent("VNC connection disconnected", level: .info, connectionID: connectionID)
            }
            print("🔌 VNC: Disconnected")
        }
    }
    
    func vncDidFailWithError(_ error: String) {
        print("🔴 LibVNCClient: vncDidFailWithError called with: \(error)")
        Task { @MainActor in
            if let connectionID = connectionID {
                diagnosticsManager.logVNCEvent("VNC connection failed: \(error)", level: .error, connectionID: connectionID)
            }
            print("🔴 LibVNCClient: On main actor, updating connection state")
            connectionTimer?.invalidate()
            connectionTimer = nil
            
            // Provide more user-friendly error messages
            let userFriendlyError: String
            if error.contains("Connection refused") {
                userFriendlyError = "Connection refused. Please verify the VNC server is running and accessible on port \(pendingConnection?.port ?? 5900)."
            } else if error.contains("No route to host") || error.contains("Host is down") {
                userFriendlyError = "Cannot reach the server. Please check the server address and network connection."
            } else if error.contains("timed out") {
                userFriendlyError = "Connection timed out. The server may be slow or unreachable."
            } else {
                userFriendlyError = error
            }
            
            print("🔴 LibVNCClient: Setting connectionState to failed with message: \(userFriendlyError)")
            connectionState = .failed(userFriendlyError)
            lastError = userFriendlyError
            print("❌ VNC: Connection failed - \(error)")
        }
    }
    
    func vncDidUpdateFramebuffer(_ image: CGImage) {
        Task { @MainActor in
            // Check if we need to scale the image for performance
            let maxDisplayWidth: CGFloat = 3840  // 4K width max
            let maxDisplayHeight: CGFloat = 2160 // 4K height max
            
            let imageWidth = CGFloat(image.width)
            let imageHeight = CGFloat(image.height)
            
            if imageWidth > maxDisplayWidth || imageHeight > maxDisplayHeight {
                // Scale down for performance
                let scaleX = maxDisplayWidth / imageWidth
                let scaleY = maxDisplayHeight / imageHeight
                let scale = min(scaleX, scaleY)
                
                let newWidth = Int(imageWidth * scale)
                let newHeight = Int(imageHeight * scale)
                
                if let scaledImage = scaleImage(image, to: CGSize(width: newWidth, height: newHeight)) {
                    self.framebuffer = scaledImage
                } else {
                    self.framebuffer = image
                }
            } else {
                self.framebuffer = image
            }
        }
    }
    
    func vncDidResize(_ newSize: CGSize) {
        Task { @MainActor in
            screenSize = newSize
            print("📐 VNC: Screen resized to \(newSize.width)x\(newSize.height)")
        }
    }
    
    func vncPasswordForAuthentication() -> String? {
        // Return whatever password we have (might be empty)
        return savedPassword
    }
    
    func vncRequiresPassword() {
        Task { @MainActor in
            if let connectionID = connectionID {
                diagnosticsManager.logVNCEvent("VNC server requires password authentication", level: .info, connectionID: connectionID)
            }
            passwordRequired = true
            connectionState = .failed("Password required")
            lastError = "VNC server requires a password"
        }
    }
    
    // Helper function to scale images
    private func scaleImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
    
    // MARK: - Window Management
    
    func windowDidOpen() {
        Task { @MainActor in
            windowIsOpen = true
            print("🪟 VNC: Window opened")
        }
    }
    
    func windowDidClose() {
        Task { @MainActor in
            windowIsOpen = false
            print("🪟 VNC: Window closed")
            // Don't auto-disconnect here - let the window view handle it
        }
    }
    
    func canOpenWindow() -> Bool {
        if case .connected = connectionState {
            return !windowIsOpen
        }
        return false
    }
}

