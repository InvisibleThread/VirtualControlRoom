import Foundation
import Combine
import SwiftUI

/// Manages connection diagnostics and logs for user feedback
@MainActor
class ConnectionDiagnosticsManager: ObservableObject {
    static let shared = ConnectionDiagnosticsManager()
    
    // Published logs per connection
    @Published var connectionLogs: [String: [DiagnosticEntry]] = [:]
    
    private init() {}
    
    // MARK: - Trace ID Management
    
    private var traceMap: [String: String] = [:] // connectionID -> traceID
    
    /// Generate a unique trace ID for a connection attempt
    func generateTraceID(for connectionID: String) -> String {
        let traceID = String(format: "%02X%02X", Int.random(in: 0...255), Int.random(in: 0...255))
        traceMap[connectionID] = traceID
        return traceID
    }
    
    /// Get the current trace ID for a connection
    func getTraceID(for connectionID: String) -> String {
        return traceMap[connectionID] ?? "----"
    }
    
    // MARK: - Public Methods
    
    /// Add a log entry for a specific connection with efficient formatting
    func addLog(_ message: String, level: LogLevel, connectionID: String, category: DiagnosticCategory = .general) {
        let entry = DiagnosticEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
        
        if connectionLogs[connectionID] == nil {
            connectionLogs[connectionID] = []
        }
        
        // Add the new entry
        connectionLogs[connectionID]?.append(entry)
        
        // Keep only the last 100 entries per connection
        if let logs = connectionLogs[connectionID], logs.count > 100 {
            connectionLogs[connectionID] = Array(logs.suffix(100))
        }
        
        print("🔍 Diagnostics [\(connectionID)]: [\(level.emoji)] \(message)")
    }
    
    /// Add a trace log with stable diagnostic identifier and minimal context
    func addTraceLog(_ phase: String, method: String, id: String, context: [String: Any] = [:], result: String = "", connectionID: String, level: LogLevel = .debug) {
        let traceID = getTraceID(for: connectionID)
        
        // Smart filtering: Only log errors, warnings, state changes, and decision points
        let shouldLog = level == .error || 
                       level == .warning ||
                       level == .success || 
                       result.contains("FAIL") || 
                       result.contains("SUCCESS") ||
                       phase.contains("_TUNNEL") ||
                       phase.contains("_CHANNEL") ||
                       phase.contains("VNC") ||
                       phase.contains("CONNECTION") ||
                       method.contains("connect") ||
                       method.contains("disconnect") ||
                       id.contains("FAILED") ||
                       id.contains("ERROR")
        
        guard shouldLog else { return }
        
        // Build compact context string
        var contextStr = ""
        if !context.isEmpty {
            let contextPairs = context.map { "\($0.key)=\($0.value)" }
            contextStr = " | " + contextPairs.joined(separator: " ")
        }
        
        let resultStr = result.isEmpty ? "" : " | \(result)"
        let message = "[\(traceID)] \(phase):\(method):\(id)\(contextStr)\(resultStr)"
        
        addLog(message, level: level, connectionID: connectionID, category: .general)
    }
    
    /// Get logs for a specific connection
    func getLogs(for connectionID: String) -> [DiagnosticEntry] {
        return connectionLogs[connectionID] ?? []
    }
    
    /// Clear logs for a specific connection
    func clearLogs(for connectionID: String) {
        connectionLogs[connectionID] = []
    }
    
    /// Get the latest error for a connection (if any)
    func getLatestError(for connectionID: String) -> DiagnosticEntry? {
        return connectionLogs[connectionID]?.reversed().first { $0.level == .error }
    }
    
    /// Get connection status summary
    func getStatusSummary(for connectionID: String) -> ConnectionStatusSummary {
        let logs = getLogs(for: connectionID)
        let now = Date()
        let recentTimeThreshold = now.addingTimeInterval(-300) // 5 minutes ago
        
        // Only count recent errors/warnings for status indicators
        let recentErrors = logs.filter { $0.level == .error && $0.timestamp > recentTimeThreshold }
        let recentWarnings = logs.filter { $0.level == .warning && $0.timestamp > recentTimeThreshold }
        
        // But keep total counts for history
        let allErrors = logs.filter { $0.level == .error }
        let allWarnings = logs.filter { $0.level == .warning }
        
        let lastActivity = logs.last?.timestamp
        let lastError = allErrors.last
        
        let status: ConnectionStatus
        if let latestLog = logs.last {
            switch latestLog.level {
            case .error:
                // Only show as failed if error is recent
                if latestLog.timestamp > recentTimeThreshold {
                    status = .failed
                } else {
                    status = .unknown
                }
            case .warning:
                // Only show as unstable if warning is recent
                if latestLog.timestamp > recentTimeThreshold {
                    status = .unstable
                } else {
                    status = .unknown
                }
            case .info:
                if latestLog.message.lowercased().contains("connect") {
                    status = .connected
                } else {
                    status = .unknown
                }
            case .success:
                status = .connected
            default:
                status = .unknown
            }
        } else {
            status = .unknown
        }
        
        return ConnectionStatusSummary(
            status: status,
            lastActivity: lastActivity,
            lastError: lastError,
            errorCount: allErrors.count,
            warningCount: allWarnings.count,
            totalLogs: logs.count,
            recentErrorCount: recentErrors.count,
            recentWarningCount: recentWarnings.count
        )
    }
    
    // MARK: - Convenience Methods for Different Connection Types
    
    func logVNCEvent(_ message: String, level: LogLevel, connectionID: String) {
        addLog(message, level: level, connectionID: connectionID, category: .vnc)
    }
    
    func logSSHEvent(_ message: String, level: LogLevel, connectionID: String) {
        addLog(message, level: level, connectionID: connectionID, category: .ssh)
    }
    
    func logNetworkEvent(_ message: String, level: LogLevel, connectionID: String) {
        addLog(message, level: level, connectionID: connectionID, category: .network)
    }
    
    func logAuthEvent(_ message: String, level: LogLevel, connectionID: String) {
        addLog(message, level: level, connectionID: connectionID, category: .authentication)
    }
}

// MARK: - Supporting Types

struct DiagnosticEntry: Identifiable, Codable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: DiagnosticCategory
    let message: String
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

enum LogLevel: String, Codable, CaseIterable {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    case success = "success"
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .success: return "✅"
        }
    }
    
    var color: Color {
        switch self {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

enum DiagnosticCategory: String, Codable, CaseIterable {
    case general = "general"
    case vnc = "vnc"
    case ssh = "ssh"
    case network = "network"
    case authentication = "auth"
    case optimization = "optimization"
    
    var displayName: String {
        switch self {
        case .general: return "General"
        case .vnc: return "VNC"
        case .ssh: return "SSH"
        case .network: return "Network"
        case .authentication: return "Authentication"
        case .optimization: return "Optimization"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "info.circle"
        case .vnc: return "display"
        case .ssh: return "lock.shield"
        case .network: return "network"
        case .authentication: return "key"
        case .optimization: return "speedometer"
        }
    }
}

enum ConnectionStatus: String, Codable {
    case unknown = "unknown"
    case connecting = "connecting"
    case connected = "connected"
    case unstable = "unstable"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .unstable: return "Unstable"
        case .failed: return "Failed"
        }
    }
    
    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .connecting: return .blue
        case .connected: return .green
        case .unstable: return .orange
        case .failed: return .red
        }
    }
    
    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .connecting: return "arrow.clockwise.circle"
        case .connected: return "checkmark.circle.fill"
        case .unstable: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}

struct ConnectionStatusSummary {
    let status: ConnectionStatus
    let lastActivity: Date?
    let lastError: DiagnosticEntry?
    let errorCount: Int
    let warningCount: Int
    let totalLogs: Int
    let recentErrorCount: Int
    let recentWarningCount: Int
    
    var hasIssues: Bool {
        return errorCount > 0 || warningCount > 0
    }
    
    var hasRecentIssues: Bool {
        return recentErrorCount > 0 || recentWarningCount > 0
    }
    
    var statusDescription: String {
        if recentErrorCount > 0 {
            return "\(recentErrorCount) recent error\(recentErrorCount > 1 ? "s" : "")"
        } else if recentWarningCount > 0 {
            return "\(recentWarningCount) recent warning\(recentWarningCount > 1 ? "s" : "")"
        } else if errorCount > 0 || warningCount > 0 {
            return "Previous issues cleared"
        } else if totalLogs > 0 {
            return "All systems normal"
        } else {
            return "No activity"
        }
    }
}