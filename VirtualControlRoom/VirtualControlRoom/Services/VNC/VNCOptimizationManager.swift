import Foundation
import Combine
import CoreData

/// Manages VNC connection optimization including encoding preferences and performance tuning
@MainActor
class VNCOptimizationManager: ObservableObject {
    static let shared = VNCOptimizationManager()
    
    @Published var optimizationSettings: [String: VNCOptimizationSettings] = [:]
    
    private init() {
        print("⚡ VNCOptimizationManager initialized with performance-based optimization")
        setupNetworkQualityMonitoring()
    }
    
    private func setupNetworkQualityMonitoring() {
        // Subscribe to connection quality changes
        NetworkMonitor.shared.qualityChangePublisher
            .sink { [weak self] quality in
                self?.handleQualityChange(quality)
            }
            .store(in: &cancellables)
    }
    
    private func handleQualityChange(_ quality: ConnectionQuality) {
        print("⚡ Network quality changed to: \(quality.description) (\(quality.emoji))")
        adjustSettingsForNetworkChange()
    }
    
    // Store cancellables for Combine subscriptions
    private var cancellables = Set<AnyCancellable>()
    
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
    
    /// Load optimization settings from ConnectionProfile (manual settings take precedence)
    func getOptimizationSettings(for connectionProfile: ConnectionProfile) -> VNCOptimizationSettings {
        let connectionID = connectionProfile.id?.uuidString ?? UUID().uuidString
        
        // Check if manual optimization is enabled
        if connectionProfile.useCustomOptimization {
            print("⚡ Using manual optimization settings for \(connectionProfile.name ?? "Unnamed")")
            
            // Parse preferred encodings from stored string
            let encodingsString = connectionProfile.preferredEncodings ?? "tight,zrle,zlib,raw"
            let encodingNames = encodingsString.components(separatedBy: ",")
            let encodings = encodingNames.compactMap { VNCEncoding(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            
            // Convert pixel format string to enum
            let pixelFormat: VNCPixelFormat
            switch connectionProfile.pixelFormat {
            case "rgb565":
                pixelFormat = .rgb565
            case "rgb555":
                pixelFormat = .rgb555
            default:
                pixelFormat = .rgb888
            }
            
            let manualSettings = VNCOptimizationSettings(
                preferredEncodings: encodings.isEmpty ? [.tight, .zrle, .zlib, .raw] : encodings,
                compressionLevel: Int(connectionProfile.compressionLevel),
                jpegQuality: Int(connectionProfile.jpegQuality),
                framebufferUpdateRequestIncremental: true,
                pixelFormat: pixelFormat,
                maxFrameRate: Int(connectionProfile.maxFrameRate)
            )
            
            // Cache the settings
            optimizationSettings[connectionID] = manualSettings
            
            print("   Manual Settings:")
            print("   - Encodings: \(manualSettings.preferredEncodings.map { $0.rawValue })")
            print("   - Compression: \(manualSettings.compressionLevel)")
            print("   - JPEG Quality: \(manualSettings.jpegQuality)")
            print("   - Pixel Format: \(manualSettings.pixelFormat)")
            print("   - Max Frame Rate: \(manualSettings.maxFrameRate) FPS")
            
            return manualSettings
        } else {
            print("⚡ Using automatic optimization settings for \(connectionProfile.name ?? "Unnamed")")
            // Fall back to automatic optimization based on network conditions
            return getOptimizationSettings(for: connectionID)
        }
    }
    
    func updateOptimizationSettings(for connectionID: String, settings: VNCOptimizationSettings) {
        optimizationSettings[connectionID] = settings
        print("⚡ VNC optimization settings updated for \(connectionID)")
    }
    
    private func createDefaultSettings() -> VNCOptimizationSettings {
        let networkMonitor = NetworkMonitor.shared
        
        // Use measured connection quality instead of interface type
        return createSettingsForQuality(networkMonitor.connectionQuality)
    }
    
    /// Create VNC settings based on measured connection quality
    func createSettingsForQuality(_ quality: ConnectionQuality) -> VNCOptimizationSettings {
        switch quality {
        case .excellent:
            // High performance settings for excellent connections
            return VNCOptimizationSettings(
                preferredEncodings: [.zrle, .tight, .raw],
                compressionLevel: 2,
                jpegQuality: 9,
                framebufferUpdateRequestIncremental: true,
                pixelFormat: .rgb888,
                maxFrameRate: 60
            )
            
        case .good:
            // Balanced settings for good connections
            return VNCOptimizationSettings(
                preferredEncodings: [.tight, .zrle, .zlib, .raw],
                compressionLevel: 4,
                jpegQuality: 8,
                framebufferUpdateRequestIncremental: true,
                pixelFormat: .rgb888,
                maxFrameRate: 30
            )
            
        case .fair:
            // Conservative settings for fair connections
            return VNCOptimizationSettings(
                preferredEncodings: [.tight, .zlib, .raw],
                compressionLevel: 7,
                jpegQuality: 6,
                framebufferUpdateRequestIncremental: true,
                pixelFormat: .rgb888,
                maxFrameRate: 20
            )
            
        case .poor:
            // Maximum compression settings for poor connections
            return VNCOptimizationSettings(
                preferredEncodings: [.tight, .zlib, .raw],
                compressionLevel: 9,
                jpegQuality: 4,
                framebufferUpdateRequestIncremental: true,
                pixelFormat: .rgb565, // Lower color depth for bandwidth savings
                maxFrameRate: 10
            )
            
        case .unknown:
            // Safe default settings for unknown quality
            return VNCOptimizationSettings(
                preferredEncodings: [.tight, .zrle, .zlib, .raw],
                compressionLevel: 6,
                jpegQuality: 7,
                framebufferUpdateRequestIncremental: true,
                pixelFormat: .rgb888,
                maxFrameRate: 25
            )
        }
    }
    
    // MARK: - Performance-Based Configuration
    
    /// Configure VNC client using ConnectionProfile settings (manual or automatic)
    func configureVNCClient(_ client: LibVNCClient, for connectionProfile: ConnectionProfile) async {
        let settings = getOptimizationSettings(for: connectionProfile)
        let connectionName = connectionProfile.name ?? "Unnamed"
        
        print("⚡ Configuring VNC client for \(connectionName)")
        print("   Settings Type: \(connectionProfile.useCustomOptimization ? "Manual" : "Automatic")")
        print("   Encodings: \(settings.preferredEncodings.map { $0.rawValue })")
        print("   Compression: \(settings.compressionLevel)")
        print("   JPEG Quality: \(settings.jpegQuality)")
        print("   Pixel Format: \(settings.pixelFormat)")
        print("   Frame Rate: \(settings.maxFrameRate) FPS")
        
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
    
    /// Configure VNC client with performance measurement (for automatic optimization)
    func configureVNCClientWithPerformance(_ client: LibVNCClient, for connectionID: String, host: String, port: Int) async {
        print("⚡ Measuring performance for VNC optimization...")
        
        // Measure actual connection performance
        let performance = await NetworkMonitor.shared.measurePerformance(to: host, port: port)
        
        // Create optimized settings based on measured performance
        let settings = createSettingsForQuality(performance.quality)
        
        // Store settings for this connection
        optimizationSettings[connectionID] = settings
        
        print("⚡ Configuring VNC client with performance-based optimizations for \(connectionID)")
        print("   Performance: \(performance.quality.description) (\(performance.quality.emoji))")
        print("   Latency: \(Int(performance.latency))ms")
        print("   Bandwidth: \(performance.bandwidth) Mbps")
        print("   Encodings: \(settings.preferredEncodings.map { $0.rawValue })")
        print("   Compression: \(settings.compressionLevel)")
        print("   JPEG Quality: \(settings.jpegQuality)")
        print("   Frame Rate: \(settings.maxFrameRate) FPS")
        
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
    
    /// Legacy method for backward compatibility
    func configureVNCClient(_ client: LibVNCClient, for connectionID: String) {
        let settings = getOptimizationSettings(for: connectionID)
        
        print("⚡ Configuring VNC client with cached optimizations for \(connectionID)")
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
        print("⚡ Adjusting VNC settings for network performance change")
        
        // Update all connections with new performance-based settings
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
    
    /// Adjust settings for a specific connection based on measured performance
    func adjustSettingsForPerformance(_ performance: ConnectionPerformance, connectionID: String) {
        print("⚡ Adjusting VNC settings for \(connectionID) based on performance: \(performance.quality.description)")
        
        let newSettings = createSettingsForQuality(performance.quality)
        optimizationSettings[connectionID] = newSettings
        
        // Notify clients to reconfigure
        NotificationCenter.default.post(
            name: .vncOptimizationChanged,
            object: connectionID,
            userInfo: ["settings": newSettings, "performance": performance]
        )
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