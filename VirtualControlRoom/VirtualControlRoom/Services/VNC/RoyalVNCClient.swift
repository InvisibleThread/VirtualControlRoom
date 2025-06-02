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
            isDebugLoggingEnabled: false,
            hostname: host,
            port: UInt16(port),
            isShared: true,
            isScalingEnabled: false,
            useDisplayLink: false,
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
        Task { @MainActor in
            switch connectionState.status {
            case .connecting:
                self.connectionState = .connecting
            case .connected:
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
        Task { @MainActor in
            self.vncFramebuffer = framebuffer
            self.screenSize = CGSize(width: CGFloat(framebuffer.size.width), height: CGFloat(framebuffer.size.height))
            updateFramebufferImage()
        }
    }
    
    func connection(_ connection: VNCConnection, didResizeFramebuffer framebuffer: VNCFramebuffer) {
        Task { @MainActor in
            self.screenSize = CGSize(width: CGFloat(framebuffer.size.width), height: CGFloat(framebuffer.size.height))
            updateFramebufferImage()
        }
    }
    
    func connection(_ connection: VNCConnection, didUpdateFramebuffer framebuffer: VNCFramebuffer, x: UInt16, y: UInt16, width: UInt16, height: UInt16) {
        Task { @MainActor in
            updateFramebufferImage()
        }
    }
    
    func connection(_ connection: VNCConnection, didUpdateCursor cursor: VNCCursor) {
        // Handle cursor updates if needed
    }
    
    private func updateFramebufferImage() {
        guard let fb = vncFramebuffer else { return }
        self.framebuffer = fb.cgImage
    }
}