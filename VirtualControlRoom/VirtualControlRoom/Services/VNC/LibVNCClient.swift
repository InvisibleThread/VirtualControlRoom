import Foundation
import SwiftUI

/// VNC client implementation using LibVNCClient C library
/// This replaces RoyalVNCClient which had issues with cgImage property
class LibVNCClient: NSObject, ObservableObject {
    @Published var connectionState: VNCConnectionState = .disconnected
    @Published var framebuffer: CGImage?
    @Published var screenSize: CGSize = .zero
    @Published var lastError: String?
    
    private var vncWrapper: LibVNCWrapper?
    private var savedPassword: String?
    
    override init() {
        super.init()
        setupVNCWrapper()
    }
    
    private func setupVNCWrapper() {
        vncWrapper = LibVNCWrapper()
        vncWrapper?.delegate = self
    }
    
    func connect(host: String, port: Int, username: String?, password: String?) async {
        await MainActor.run {
            connectionState = .connecting
            lastError = nil
        }
        
        // Save password for callback
        savedPassword = password
        
        // Connect using the wrapper
        guard let wrapper = vncWrapper else {
            await MainActor.run {
                connectionState = .failed("VNC wrapper not initialized")
                lastError = "Internal error: VNC wrapper not initialized"
            }
            return
        }
        
        // Note: LibVNCWrapper handles connection on background queue
        let connected = wrapper.connect(toHost: host, port: port, username: username, password: password)
        
        if !connected {
            await MainActor.run {
                connectionState = .failed("Failed to initiate connection")
                lastError = "Failed to start VNC connection"
            }
        }
    }
    
    func disconnect() {
        vncWrapper?.disconnect()
        savedPassword = nil
        
        Task { @MainActor in
            connectionState = .disconnected
            framebuffer = nil
            screenSize = .zero
            lastError = nil
        }
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
            connectionState = .connected
            lastError = nil
            print("✅ VNC: Connected successfully via LibVNCClient")
        }
    }
    
    func vncDidDisconnect() {
        Task { @MainActor in
            connectionState = .disconnected
            framebuffer = nil
            screenSize = .zero
            print("🔌 VNC: Disconnected")
        }
    }
    
    func vncDidFailWithError(_ error: String) {
        Task { @MainActor in
            connectionState = .failed(error)
            lastError = error
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
        return savedPassword
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
}

