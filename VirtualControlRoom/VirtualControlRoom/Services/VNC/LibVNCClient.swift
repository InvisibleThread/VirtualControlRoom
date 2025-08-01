import SwiftUI

/// LibVNCClient provides a Swift interface to the LibVNC C library for VNC connections.
/// It manages the VNC connection lifecycle, handles authentication, and provides
/// real-time framebuffer updates for display in the UI.
///
/// Key features:
/// - Wraps LibVNCWrapper (Objective-C bridge to LibVNC C library)
/// - Publishes connection state and framebuffer for SwiftUI binding
/// - Handles password authentication with retry capability
/// - Manages connection timeouts (15 seconds for initial connection)
/// - Provides thread-safe mouse and keyboard input methods
/// - Scales large framebuffers for performance (max 4K resolution)
///
/// The client coordinates with ConnectionManager for lifecycle management
/// and uses ConnectionDiagnosticsManager for structured logging.
class LibVNCClient: NSObject, ObservableObject {
    // Published properties for UI binding
    @Published var connectionState: VNCConnectionState = .disconnected
    @Published var framebuffer: CGImage?  // Current screen image from VNC server
    @Published var screenSize: CGSize = .zero  // Remote desktop dimensions
    @Published var lastError: String?  // User-friendly error message
    @Published var passwordRequired: Bool = false  // Triggers password prompt UI
    @Published var windowIsOpen: Bool = false  // Tracks if VNC window is displayed
    
    // VNC connection management
    private var vncWrapper: LibVNCWrapper?  // Objective-C wrapper for LibVNC
    private var savedPassword: String?  // Password for retry attempts
    private var pendingConnection: (host: String, port: Int, username: String?)?  // Connection details for retry
    var passwordHandler: ((String) -> Void)?  // Callback for password retry
    private var connectionTimer: Timer?  // Timeout timer for connection attempts
    private let connectionTimeout: TimeInterval = 30.0 // 30 seconds timeout
    
    // Diagnostics and logging
    private var connectionID: String?  // Unique ID for this connection session
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
    
    /// Sets up the VNC wrapper instance if it doesn't already exist.
    /// Reuses existing wrapper to avoid recreating connections unnecessarily.
    private func setupVNCWrapper() {
        // Only create wrapper if we don't have one - reuse existing for efficiency
        if vncWrapper == nil {
            vncWrapper = LibVNCWrapper()
            vncWrapper?.delegate = self
        }
    }
    
    /// Initiates a VNC connection to the specified host and port.
    /// This method handles the complete connection flow including timeout management,
    /// state transitions, and error handling.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address of the VNC server (typically localhost for SSH tunnels)
    ///   - port: The port number to connect to (local port for SSH tunnels)
    ///   - username: Optional username for VNC authentication (rarely used)
    ///   - password: Optional password for VNC authentication
    ///
    /// The connection process:
    /// 1. Ensures not already connecting
    /// 2. Disconnects any existing connection
    /// 3. Sets up the VNC wrapper
    /// 4. Saves connection details for retry
    /// 5. Initiates connection with 15-second timeout
    /// 6. Transitions through connection states
    func connect(host: String, port: Int, username: String?, password: String?) async {
        // Use existing connection ID or fallback to host:port format for diagnostics
        if connectionID == nil {
            connectionID = "\(host)_\(port)"
        }
        
        Task { @MainActor in
            diagnosticsManager.logVNCEvent("Starting VNC connection to \(host):\(port)", level: .info, connectionID: connectionID!)
        }
        // Log current state
        Task { @MainActor in
            diagnosticsManager.logVNCEvent("Current connection state: \(connectionState)", level: .debug, connectionID: connectionID!)
        }
        
        // Ensure we're not already connecting
        if connectionState == .connecting {
            Task { @MainActor in
                diagnosticsManager.logVNCEvent("Connection already in progress, ignoring new request", level: .warning, connectionID: connectionID!)
            }
            return
        }
        
        // Disconnect any existing connection first (but preserve password for retry)
        if connectionState == .connected {
            Task { @MainActor in
                diagnosticsManager.logVNCEvent("Disconnecting existing connection for new attempt", level: .info, connectionID: connectionID!)
            }
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
        
        // Connect using the wrapper
        guard let wrapper = vncWrapper else {
            Task { @MainActor in
                diagnosticsManager.logVNCEvent("VNC wrapper not initialized", level: .error, connectionID: connectionID!)
            }
            await MainActor.run {
                connectionState = .failed("VNC wrapper not initialized")
                lastError = "Internal error: VNC wrapper not initialized"
            }
            return
        }
        
        Task { @MainActor in
            diagnosticsManager.logVNCEvent("VNC wrapper ready, initiating connection", level: .info, connectionID: connectionID!)
        }
        
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
        let connected = wrapper.connect(toHost: host, port: port, username: username, password: password)
        
        if !connected {
            Task { @MainActor in
                diagnosticsManager.logVNCEvent("VNC wrapper failed to initiate connection", level: .error, connectionID: connectionID!)
            }
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
        }
    }
    
    func retryWithPassword(_ password: String) async {
        guard let pending = pendingConnection else { 
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
        vncDidDisconnect()
    }
    
    /// Sends a keyboard event to the VNC server.
    /// - Parameters:
    ///   - keysym: The X11 keysym code representing the key
    ///   - down: true for key press, false for key release
    func sendKeyEvent(keysym: UInt32, down: Bool) {
        vncWrapper?.sendKeyEvent(keysym, down: down)
    }
    
    /// Sends a mouse/pointer event to the VNC server.
    /// - Parameters:
    ///   - x: The X coordinate in VNC screen space
    ///   - y: The Y coordinate in VNC screen space
    ///   - buttonMask: Bitmask of pressed buttons (1=left, 2=middle, 4=right)
    func sendPointerEvent(x: Int, y: Int, buttonMask: Int) {
        print("📥 LibVNCClient: sendPointerEvent called with x:\(x) y:\(y) mask:\(buttonMask)")
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
        }
    }
    
    func windowDidClose() {
        Task { @MainActor in
            windowIsOpen = false
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

