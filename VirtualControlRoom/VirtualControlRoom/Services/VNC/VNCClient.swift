import Foundation
import SwiftUI
import Combine

enum VNCConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String) // Changed from Error to String for Equatable conformance
    
    static func == (lhs: VNCConnectionState, rhs: VNCConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

enum VNCError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case unsupportedProtocol
    case frameBufferUpdateFailed
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .authenticationFailed:
            return "Authentication failed"
        case .unsupportedProtocol:
            return "Unsupported VNC protocol"
        case .frameBufferUpdateFailed:
            return "Failed to update frame buffer"
        }
    }
}

class VNCClient: ObservableObject {
    @Published var connectionState: VNCConnectionState = .disconnected
    @Published var framebuffer: CGImage?
    @Published var screenSize: CGSize = .zero
    
    private var updateTimer: Timer?
    private let mockImage = createMockDesktopImage()
    
    func connect(host: String, port: Int, password: String?) async {
        await MainActor.run {
            connectionState = .connecting
        }
        
        // Simulate connection delay
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // For PoC, simulate successful connection
        await MainActor.run {
            connectionState = .connected
            screenSize = CGSize(width: 1920, height: 1080)
            framebuffer = mockImage
            startFrameUpdates()
        }
    }
    
    func disconnect() {
        updateTimer?.invalidate()
        updateTimer = nil
        connectionState = .disconnected
        framebuffer = nil
        screenSize = .zero
    }
    
    private func startFrameUpdates() {
        // Simulate frame updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            // In real implementation, this would update with actual VNC frames
            // For PoC, we'll just use the same mock image
            self.framebuffer = self.mockImage
        }
    }
}

// Helper function to create a mock desktop image
private func createMockDesktopImage() -> CGImage? {
    let size = CGSize(width: 1920, height: 1080)
    let renderer = UIGraphicsImageRenderer(size: size)
    
    let image = renderer.image { context in
        // Background
        UIColor.systemGray6.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        
        // Simulated desktop elements
        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: 30))
        
        // Window
        UIColor.white.setFill()
        context.fill(CGRect(x: 100, y: 100, width: 800, height: 600))
        
        // Text
        let text = "VNC Test Desktop - \(Date())"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24),
            .foregroundColor: UIColor.black
        ]
        text.draw(at: CGPoint(x: 120, y: 120), withAttributes: attributes)
    }
    
    return image.cgImage
}