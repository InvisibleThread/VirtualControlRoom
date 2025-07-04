import Foundation

/// Configuration for SSH tunnel behavior
struct SSHTunnelConfiguration {
    /// Maximum number of retry attempts for transient failures
    let maxRetries: Int
    
    /// Delay between retry attempts
    let retryDelay: TimeInterval
    
    /// Timeout for establishing connections
    let connectionTimeout: TimeInterval
    
    /// Whether to validate target reachability before creating tunnel
    let validateBeforeConnect: Bool
    
    /// Whether to try IP address if hostname fails
    let fallbackToIPAddress: Bool
    
    /// Whether to keep tunnel alive with periodic health checks
    let enableKeepAlive: Bool
    
    /// Interval for keep-alive checks
    let keepAliveInterval: TimeInterval
    
    /// Default configuration with sensible defaults
    static let `default` = SSHTunnelConfiguration(
        maxRetries: 3,
        retryDelay: 2.0,
        connectionTimeout: 30.0,
        validateBeforeConnect: true,
        fallbackToIPAddress: true,
        enableKeepAlive: true,
        keepAliveInterval: 30.0
    )
    
    /// Configuration for testing/debugging
    static let debug = SSHTunnelConfiguration(
        maxRetries: 1,
        retryDelay: 1.0,
        connectionTimeout: 10.0,
        validateBeforeConnect: true,
        fallbackToIPAddress: true,
        enableKeepAlive: false,
        keepAliveInterval: 0
    )
}

/// Result of SSH tunnel validation
struct SSHTunnelValidationResult {
    let isValid: Bool
    let targetHost: String  // May be different from requested (e.g., IP instead of hostname)
    let targetPort: Int
    let warnings: [String]
    let errors: [String]
    
    var hasWarnings: Bool { !warnings.isEmpty }
    var hasErrors: Bool { !errors.isEmpty }
    
    var summary: String {
        if isValid {
            if hasWarnings {
                return "Tunnel configuration valid with warnings:\n" + warnings.joined(separator: "\n")
            }
            return "Tunnel configuration valid"
        } else {
            return "Tunnel configuration invalid:\n" + errors.joined(separator: "\n")
        }
    }
}