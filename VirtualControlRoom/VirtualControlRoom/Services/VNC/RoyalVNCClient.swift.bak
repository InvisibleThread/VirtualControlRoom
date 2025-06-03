import Foundation
import SwiftUI
import RoyalVNCKit

/// Real VNC client implementation using RoyalVNCKit
class RoyalVNCClient: NSObject, ObservableObject {
    @Published var connectionState: VNCConnectionState = .disconnected
    @Published var framebuffer: CGImage?
    @Published var screenSize: CGSize = .zero
    @Published var lastError: String?
    
    private var connection: VNCConnection?
    private var vncFramebuffer: VNCFramebuffer?
    private var savedUsername: String?
    private var savedPassword: String?
    private var hasLoggedImageFailure = false
    
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
            isDebugLoggingEnabled: false, // Disable verbose debug logging for performance
            hostname: host,
            port: UInt16(port),
            isShared: true,
            isScalingEnabled: false,
            useDisplayLink: true, // Try enabling display link for better updates
            inputMode: .forwardKeyboardShortcutsIfNotInUseLocally,
            isClipboardRedirectionEnabled: true,
            colorDepth: .depth24Bit,
            frameEncodings: [16, 5, 2, 1, 0] // ZRLE, Hextile, RRE, CopyRect, Raw - TightVNC prefers ZRLE/Hextile
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
        hasLoggedImageFailure = false // Reset for next connection
        
        Task { @MainActor in
            connectionState = .disconnected
            framebuffer = nil
            screenSize = .zero
            lastError = nil
        }
    }
    
    func sendKeyEvent(keysym: UInt32, down: Bool) {
        guard let connection = connection else { return }
        
        let keyCode = VNCKeyCode(keysym)
        
        if down {
            connection.keyDown(keyCode)
        } else {
            connection.keyUp(keyCode)
        }
    }
    
    func sendPointerEvent(x: Int, y: Int, buttonMask: Int) {
        guard let connection = connection else { return }
        
        let vncX = UInt16(max(0, min(x, Int(UInt16.max))))
        let vncY = UInt16(max(0, min(y, Int(UInt16.max))))
        
        // Move mouse to position
        connection.mouseMove(x: vncX, y: vncY)
        
        // Handle button states (VNC button mask: 1=left, 2=middle, 4=right)
        if buttonMask & 1 != 0 {
            connection.mouseButtonDown(.left, x: vncX, y: vncY)
        } else {
            connection.mouseButtonUp(.left, x: vncX, y: vncY)
        }
        
        if buttonMask & 2 != 0 {
            connection.mouseButtonDown(.middle, x: vncX, y: vncY)
        } else {
            connection.mouseButtonUp(.middle, x: vncX, y: vncY)
        }
        
        if buttonMask & 4 != 0 {
            connection.mouseButtonDown(.right, x: vncX, y: vncY)
        } else {
            connection.mouseButtonUp(.right, x: vncX, y: vncY)
        }
    }
}

// MARK: - VNCConnectionDelegate
extension RoyalVNCClient: VNCConnectionDelegate {
    func connection(_ connection: VNCConnection, stateDidChange connectionState: VNCConnection.ConnectionState) {
        Task { @MainActor in
            switch connectionState.status {
            case .connecting:
                self.connectionState = .connecting
            case .connected:
                print("🟢 VNC: Connected successfully!")
                self.connectionState = .connected
            case .disconnecting:
                self.connectionState = .disconnected
            case .disconnected:
                self.connectionState = .disconnected
                self.connection = nil
                self.vncFramebuffer = nil
                if let error = connectionState.error {
                    self.lastError = error.localizedDescription
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
            // Standard VNC authentication (password only) - used by TightVNC
            if let password = savedPassword {
                completion(VNCPasswordCredential(password: password))
            } else {
                // TightVNC might accept empty password
                completion(VNCPasswordCredential(password: ""))
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
            // Unknown authentication type - log it for debugging
            print("⚠️ VNC: Unsupported authentication type requested: \(authenticationType)")
            completion(nil)
        }
    }
    
    func connection(_ connection: VNCConnection, didCreateFramebuffer framebuffer: VNCFramebuffer) {
        print("📺 VNC: Created framebuffer \(framebuffer.size.width)x\(framebuffer.size.height)")
        Task { @MainActor in
            self.vncFramebuffer = framebuffer
            self.screenSize = CGSize(width: CGFloat(framebuffer.size.width), height: CGFloat(framebuffer.size.height))
            
            // Don't try to update image immediately - wait for first framebuffer update
            print("📺 VNC: Framebuffer created, waiting for first update...")
        }
    }
    
    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor in
            self.screenSize = CGSize(width: CGFloat(framebuffer.size.width), height: CGFloat(framebuffer.size.height))
            updateFramebufferImage()
        }
    }
    
    func connection(_ connection: VNCConnection, didUpdateFramebuffer framebuffer: VNCFramebuffer, x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
        // Removed verbose logging for performance - framebuffer updates happen frequently
        Task { @MainActor in
            updateFramebufferImage()
        }
    }
    
    func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {
        // Handle cursor updates if needed - removed logging for performance
    }
    
    func connection(_ connection: VNCConnection, didReceiveServerCutText text: String) {
        print("📋 VNC: Server cut text: \(text)")
    }
    
    private func updateFramebufferImage() {
        guard let fb = vncFramebuffer else { 
            return 
        }
        
        // Try multiple ways to get image data from framebuffer
        if let image = fb.cgImage {
            // For very wide displays (like 8000x2000), scale down for UI performance
            // but maintain aspect ratio
            let maxDisplayWidth: CGFloat = 3840  // 4K width max
            let maxDisplayHeight: CGFloat = 2160 // 4K height max
            let scaledImage: CGImage
            
            let imageWidth = CGFloat(image.width)
            let imageHeight = CGFloat(image.height)
            
            if imageWidth > maxDisplayWidth || imageHeight > maxDisplayHeight {
                // Calculate scale to fit within max bounds while maintaining aspect ratio
                let scaleX = maxDisplayWidth / imageWidth
                let scaleY = maxDisplayHeight / imageHeight
                let scale = min(scaleX, scaleY)
                
                let newWidth = Int(imageWidth * scale)
                let newHeight = Int(imageHeight * scale)
                
                scaledImage = scaleImageToSize(image, width: newWidth, height: newHeight) ?? image
            } else {
                scaledImage = image
            }
            
            self.framebuffer = scaledImage
        } else {
            // Log only on first failure, not every frame
            if !hasLoggedImageFailure {
                print("❌ VNC: Failed to get CGImage from framebuffer (size: \(fb.size.width)x\(fb.size.height))")
                print("⚠️ VNC: The VNC connection is active but image conversion is failing")
                print("📊 VNC: This may be due to pixel format incompatibility with the VNC server")
                hasLoggedImageFailure = true
            }
            
            // Don't set a placeholder - leave framebuffer as nil so UI shows blank
            // This makes it clear the issue is with image conversion, not connection
        }
    }
    
    private func scaleImageToSize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        // Use RGB color space and ensure compatible bitmap info
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        
        // Calculate bytes per row manually to avoid alignment issues
        let bytesPerRow = width * 4 // 4 bytes per pixel for RGBA
        
        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: colorSpace,
                                    bitmapInfo: bitmapInfo) else {
            print("Failed to create bitmap context for scaling")
            return nil
        }
        
        // Draw the image scaled
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return context.makeImage()
    }
    
    private func createCGImageFromPixelData(_ pixelData: Data, width: Int, height: Int) -> CGImage? {
        // Based on server pixel format from console:
        // bitsPerPixel: 32, depth: 24, redShift: 16, greenShift: 8, blueShift: 0
        // This means BGRX format (blue in low byte, red in high byte, X = unused)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Try different bitmap configurations to match the VNC server format
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let bytesPerRow = width * 4
        
        return pixelData.withUnsafeBytes { bytes in
            guard let dataProvider = CGDataProvider(data: NSData(bytes: bytes.baseAddress, length: pixelData.count)) else {
                print("❌ VNC: Failed to create data provider")
                return nil
            }
            
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: dataProvider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
            
            if image == nil {
                print("❌ VNC: CGImage creation failed with current bitmap info")
            }
            
            return image
        }
    }
}