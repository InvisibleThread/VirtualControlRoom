import Foundation

/// Manages VNC connection optimization including encoding preferences and performance tuning
@MainActor
class VNCOptimizationManager: ObservableObject {
    static let shared = VNCOptimizationManager()
    
    @Published var optimizationSettings: [String: VNCOptimizationSettings] = [:]
    
    private init() {
        print("⚡ VNCOptimizationManager initialized")
    }
    
    // MARK: - Optimization Settings
    
    func getOptimizationSettings(for connectionID: String) -> VNCOptimizationSettings {
        if let existing = optimizationSettings[connectionID] {
            return existing
        }
        
        // Create default settings based on network conditions
        let defaultSettings = createDefaultSettings()
        optimizationSettings[connectionID] = defaultSettings
        return defaultSettings
    }
    
    func updateOptimizationSettings(for connectionID: String, settings: VNCOptimizationSettings) {
        optimizationSettings[connectionID] = settings
        print("⚡ VNC optimization settings updated for \(connectionID)")
    }
    
    private func createDefaultSettings() -> VNCOptimizationSettings {
        let networkMonitor = NetworkMonitor.shared
        
        if networkMonitor.isExpensive || networkMonitor.connectionType == .cellular {
            // Conservative settings for cellular/expensive connections
            return VNCOptimizationSettings(
                preferredEncodings: [.tight, .zlib, .raw],
                compressionLevel: 9,
                jpegQuality: 5,
                framebufferUpdateRequestIncremental: true,
                pixelFormat: .rgb565, // Lower color depth for bandwidth savings
                maxFrameRate: 15
            )
        } else if networkMonitor.connectionType == .wifi {
            // Balanced settings for WiFi
            return VNCOptimizationSettings(
                preferredEncodings: [.tight, .zrle, .zlib, .raw],
                compressionLevel: 6,
                jpegQuality: 8,
                framebufferUpdateRequestIncremental: true,
                pixelFormat: .rgb888,
                maxFrameRate: 30
            )
        } else {
            // High performance settings for wired connections
            return VNCOptimizationSettings(
                preferredEncodings: [.zrle, .tight, .raw],
                compressionLevel: 3,
                jpegQuality: 9,
                framebufferUpdateRequestIncremental: true,
                pixelFormat: .rgb888,
                maxFrameRate: 60
            )
        }
    }
    
    // MARK: - VNC Client Configuration
    
    func configureVNCClient(_ client: LibVNCClient, for connectionID: String) {
        let settings = getOptimizationSettings(for: connectionID)
        
        print("⚡ Configuring VNC client with optimizations for \(connectionID)")
        print("   Encodings: \(settings.preferredEncodings.map { $0.rawValue })")
        print("   Compression: \(settings.compressionLevel)")
        print("   JPEG Quality: \(settings.jpegQuality)")
        
        // Apply encoding preferences
        client.setPreferredEncodings(settings.preferredEncodings)
        
        // Apply compression settings
        client.setCompressionLevel(settings.compressionLevel)
        client.setJPEGQuality(settings.jpegQuality)
        
        // Apply pixel format
        client.setPixelFormat(settings.pixelFormat)
        
        // Configure framebuffer update behavior
        client.setIncrementalUpdates(settings.framebufferUpdateRequestIncremental)
        
        // Apply frame rate limiting
        client.setMaxFrameRate(settings.maxFrameRate)
    }
    
    // MARK: - Performance Monitoring
    
    func startPerformanceMonitoring(for connectionID: String) {
        // Monitor bandwidth usage, frame rate, latency, etc.
        print("📊 Starting performance monitoring for \(connectionID)")
        
        // This could be expanded to track metrics and adjust settings dynamically
    }
    
    func stopPerformanceMonitoring(for connectionID: String) {
        print("📊 Stopping performance monitoring for \(connectionID)")
        optimizationSettings.removeValue(forKey: connectionID)
    }
    
    // MARK: - Dynamic Optimization
    
    func adjustSettingsForNetworkChange() {
        print("⚡ Adjusting VNC settings for network change")
        
        // Update all connections with new default settings
        for connectionID in optimizationSettings.keys {
            let newSettings = createDefaultSettings()
            optimizationSettings[connectionID] = newSettings
            
            // Notify clients to reconfigure
            NotificationCenter.default.post(
                name: .vncOptimizationChanged,
                object: connectionID,
                userInfo: ["settings": newSettings]
            )
        }
    }
}

// MARK: - Supporting Types

struct VNCOptimizationSettings {
    let preferredEncodings: [VNCEncoding]
    let compressionLevel: Int // 0-9, higher = more compression
    let jpegQuality: Int // 0-9, higher = better quality
    let framebufferUpdateRequestIncremental: Bool
    let pixelFormat: VNCPixelFormat
    let maxFrameRate: Int
}

enum VNCEncoding: String, CaseIterable {
    case raw = "raw"
    case copyRect = "copyrect" 
    case rre = "rre"
    case corre = "corre"
    case hextile = "hextile"
    case zlib = "zlib"
    case tight = "tight"
    case zlibhex = "zlibhex"
    case zrle = "zrle"
    case cursor = "cursor"
    case desktopSize = "desktop-size"
    
    var vncEncodingValue: Int32 {
        switch self {
        case .raw: return 0
        case .copyRect: return 1
        case .rre: return 2
        case .corre: return 4
        case .hextile: return 5
        case .zlib: return 6
        case .tight: return 7
        case .zlibhex: return 8
        case .zrle: return 16
        case .cursor: return -239
        case .desktopSize: return -223
        }
    }
}

enum VNCPixelFormat {
    case rgb888  // 24-bit RGB
    case rgb565  // 16-bit RGB (bandwidth optimized)
    case rgb555  // 15-bit RGB
    
    var bitsPerPixel: Int {
        switch self {
        case .rgb888: return 24
        case .rgb565: return 16
        case .rgb555: return 15
        }
    }
}

// MARK: - LibVNCClient Extensions

extension LibVNCClient {
    func setPreferredEncodings(_ encodings: [VNCEncoding]) {
        // Convert to VNC encoding values
        let encodingValues = encodings.map { $0.vncEncodingValue }
        
        // This would need to be implemented in the LibVNC wrapper
        // For now, we'll just log the intention
        print("🔧 VNC: Setting preferred encodings: \(encodings.map { $0.rawValue })")
    }
    
    func setCompressionLevel(_ level: Int) {
        print("🔧 VNC: Setting compression level: \(level)")
        // Implementation would go in LibVNC wrapper
    }
    
    func setJPEGQuality(_ quality: Int) {
        print("🔧 VNC: Setting JPEG quality: \(quality)")
        // Implementation would go in LibVNC wrapper
    }
    
    func setPixelFormat(_ format: VNCPixelFormat) {
        print("🔧 VNC: Setting pixel format: \(format.bitsPerPixel)-bit")
        // Implementation would go in LibVNC wrapper
    }
    
    func setIncrementalUpdates(_ enabled: Bool) {
        print("🔧 VNC: Setting incremental updates: \(enabled)")
        // Implementation would go in LibVNC wrapper
    }
    
    func setMaxFrameRate(_ frameRate: Int) {
        print("🔧 VNC: Setting max frame rate: \(frameRate) FPS")
        // Implementation would go in LibVNC wrapper
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let vncOptimizationChanged = Notification.Name("VNCOptimizationChanged")
}