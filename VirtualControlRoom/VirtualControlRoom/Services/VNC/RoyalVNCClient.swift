import Foundation
import SwiftUI
import RoyalVNCKit

/// Real VNC client implementation using RoyalVNCKit
class RoyalVNCClient: NSObject, ObservableObject {
    @Published var connectionState: VNCConnectionState = .disconnected
    @Published var framebuffer: CGImage? {
        didSet {
            print("DEBUG: @Published framebuffer didSet - new value: \(framebuffer != nil ? "\(framebuffer!.width)x\(framebuffer!.height)" : "NIL")")
        }
    }
    @Published var screenSize: CGSize = .zero
    @Published var lastError: String?
    
    private var connection: VNCConnection?
    private var vncFramebuffer: VNCFramebuffer?
    private var savedUsername: String?
    private var savedPassword: String?
    
    func connect(host: String, port: Int, username: String?, password: String?) async {
        await MainActor.run {
            connectionState = .connecting
            lastError = nil
        }
        
        // Save credentials for authentication callback
        savedUsername = username
        savedPassword = password
        
        // Configure VNC connection settings - use convenience initializer with Int64 array
        let settings = VNCConnection.Settings(
            isDebugLoggingEnabled: true, // Enable debug logging to see what's happening
            hostname: host,
            port: UInt16(port),
            isShared: true,
            isScalingEnabled: false,
            useDisplayLink: true, // Try enabling display link for better updates
            inputMode: .forwardKeyboardShortcutsIfNotInUseLocally,
            isClipboardRedirectionEnabled: true,
            colorDepth: .depth24Bit,
            frameEncodings: [0, 1, 5] // Raw, CopyRect, Hextile encodings
        )
        
        // Create connection
        let vncConnection = VNCConnection(settings: settings)
        vncConnection.delegate = self
        
        // Store connection reference
        await MainActor.run {
            self.connection = vncConnection
        }
        
        // Connect
        vncConnection.connect()
    }
    
    func disconnect() {
        connection?.disconnect()
        connection = nil
        vncFramebuffer = nil
        savedUsername = nil
        savedPassword = nil
        
        Task { @MainActor in
            connectionState = .disconnected
            framebuffer = nil
            screenSize = .zero
            lastError = nil
        }
    }
    
    func sendKeyEvent(key: String, down: Bool) {
        // TODO: Implement keyboard input
        // connection?.sendKeyEvent(key: key, down: down)
    }
    
    func sendPointerEvent(x: Int, y: Int, buttonMask: Int) {
        // TODO: Implement mouse input
        // connection?.sendPointerEvent(x: x, y: y, buttonMask: buttonMask)
    }
}

// MARK: - VNCConnectionDelegate
extension RoyalVNCClient: VNCConnectionDelegate {
    func connection(_ connection: VNCConnection, stateDidChange connectionState: VNCConnection.ConnectionState) {
        print("DEBUG: Connection state changed to: \(connectionState.status)")
        Task { @MainActor in
            switch connectionState.status {
            case .connecting:
                self.connectionState = .connecting
            case .connected:
                self.connectionState = .connected
                print("DEBUG: VNC connection established successfully")
            case .disconnecting:
                self.connectionState = .disconnected
            case .disconnected:
                self.connectionState = .disconnected
                self.connection = nil
                self.vncFramebuffer = nil
                if let error = connectionState.error {
                    self.lastError = error.localizedDescription
                    print("DEBUG: Connection error: \(error.localizedDescription)")
                }
            @unknown default:
                break
            }
        }
    }
    
    func connection(_ connection: VNCConnection, didFailWithError error: Error) {
        Task { @MainActor in
            self.connectionState = .failed(error.localizedDescription)
            self.lastError = error.localizedDescription
            self.connection = nil
        }
    }
    
    func connection(_ connection: VNCConnection, credentialFor authenticationType: VNCAuthenticationType, completion: @escaping (VNCCredential?) -> Void) {
        // Handle authentication based on type
        switch authenticationType {
        case .vnc:
            // Standard VNC authentication (password only)
            if let password = savedPassword {
                completion(VNCPasswordCredential(password: password))
            } else {
                completion(nil)
            }
        case .appleRemoteDesktop:
            // Apple Remote Desktop authentication (username and password)
            if let username = savedUsername, let password = savedPassword {
                completion(VNCUsernamePasswordCredential(username: username, password: password))
            } else {
                completion(nil)
            }
        case .ultraVNCMSLogonII:
            // UltraVNC MS Logon II (username and password)
            if let username = savedUsername, let password = savedPassword {
                completion(VNCUsernamePasswordCredential(username: username, password: password))
            } else {
                completion(nil)
            }
        default:
            // Unknown authentication type
            completion(nil)
        }
    }
    
    func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {
        print("DEBUG: didCreateFramebuffer called - size: \(framebuffer.size)")
        Task { @MainActor in
            self.vncFramebuffer = framebuffer
            self.screenSize = CGSize(width: CGFloat(framebuffer.size.width), height: CGFloat(framebuffer.size.height))
            
            print("DEBUG: Framebuffer created, waiting for automatic update from server")
            
            // Also create a test pattern to verify UI pipeline works
            createTestPattern()
            
            updateFramebufferImage()
        }
    }
    
    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {
        print("DEBUG: didResizeFramebuffer called - size: \(framebuffer.size)")
        Task { @MainActor in
            self.screenSize = CGSize(width: CGFloat(framebuffer.size.width), height: CGFloat(framebuffer.size.height))
            updateFramebufferImage()
        }
    }
    
    func connection(_ connection: VNCConnection, didUpdateFramebuffer framebuffer: VNCFramebuffer, x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
        print("DEBUG: didUpdateFramebuffer called - region: \(x),\(y) \(width)x\(height)")
        Task { @MainActor in
            updateFramebufferImage()
        }
    }
    
    func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {
        // Handle cursor updates if needed
    }
    
    private func updateFramebufferImage() {
        guard let fb = vncFramebuffer else { 
            print("DEBUG: No VNC framebuffer available")
            return 
        }
        
        print("DEBUG: Framebuffer size: \(fb.size)")
        print("DEBUG: Attempting to get CGImage...")
        
        let image = fb.cgImage
        print("DEBUG: CGImage result: \(image != nil ? "SUCCESS" : "NIL")")
        
        if let image = image {
            print("DEBUG: CGImage dimensions: \(image.width)x\(image.height)")
            
            // Scale down extremely large images for better UI performance
            let maxDisplaySize: CGFloat = 2048
            let scaledImage: CGImage
            
            if image.width > Int(maxDisplaySize) || image.height > Int(maxDisplaySize) {
                print("DEBUG: Image is very large (\(image.width)x\(image.height)), scaling down for UI")
                scaledImage = scaleImage(image, maxSize: maxDisplaySize) ?? image
                print("DEBUG: Scaled image to: \(scaledImage.width)x\(scaledImage.height)")
            } else {
                scaledImage = image
            }
            
            print("DEBUG: About to update @Published framebuffer property")
            self.framebuffer = scaledImage
            print("DEBUG: @Published framebuffer property updated")
        } else {
            print("DEBUG: CGImage is nil - this usually means no pixel data has been received yet")
            print("DEBUG: RoyalVNCKit will automatically request framebuffer updates")
        }
    }
    
    private func createTestPattern() {
        // Create a simple test pattern to verify UI pipeline works
        let size = CGSize(width: 800, height: 600)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil,
                                    width: Int(size.width),
                                    height: Int(size.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: Int(size.width) * 4,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("DEBUG: Failed to create test pattern context")
            return
        }
        
        // Fill with a red background
        context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Add some text
        context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        let text = "VNC Test Pattern"
        let textRect = CGRect(x: 200, y: 280, width: 400, height: 40)
        context.fill(textRect)
        
        guard let testImage = context.makeImage() else {
            print("DEBUG: Failed to create test image")
            return
        }
        
        print("DEBUG: Created test pattern image \(testImage.width)x\(testImage.height)")
        
        // Set the test image immediately to test UI pipeline
        print("DEBUG: Setting test pattern as framebuffer immediately")
        self.framebuffer = testImage
        
        // Also set it again after a delay in case VNC updates overwrite it
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            print("DEBUG: Setting test pattern as framebuffer again after 3 seconds")
            self.framebuffer = testImage
        }
    }
    
    private func scaleImage(_ image: CGImage, maxSize: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        
        // Calculate scale factor to fit within maxSize while maintaining aspect ratio
        let scale = min(maxSize / width, maxSize / height)
        
        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)
        
        print("DEBUG: Scaling image from \(image.width)x\(image.height) to \(newWidth)x\(newHeight) (scale: \(scale))")
        
        guard let colorSpace = image.colorSpace,
              let context = CGContext(data: nil,
                                    width: newWidth,
                                    height: newHeight,
                                    bitsPerComponent: image.bitsPerComponent,
                                    bytesPerRow: 0,
                                    space: colorSpace,
                                    bitmapInfo: image.bitmapInfo.rawValue) else {
            print("DEBUG: Failed to create scaling context")
            return nil
        }
        
        // Draw the image scaled
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        
        return context.makeImage()
    }
    
    // MARK: - Debug Methods
    func setTestFramebuffer(_ image: CGImage) {
        print("DEBUG: setTestFramebuffer called with image \(image.width)x\(image.height)")
        Task { @MainActor in
            print("DEBUG: Setting test framebuffer on main actor")
            self.framebuffer = image
            print("DEBUG: Test framebuffer set, should trigger UI update")
        }
    }
    
    func clearFramebuffer() {
        print("DEBUG: clearFramebuffer called")
        Task { @MainActor in
            print("DEBUG: Clearing framebuffer on main actor")
            self.framebuffer = nil
            print("DEBUG: Framebuffer cleared")
        }
    }
}