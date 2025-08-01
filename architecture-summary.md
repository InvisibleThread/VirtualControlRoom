# VirtualControlRoom Architecture Summary - Version 0.70

## High-Level System Architecture

VirtualControlRoom implements a **multi-layered resilient architecture** for secure VNC-over-SSH connections on visionOS. The system is designed around independent, specialized managers that coordinate through notifications to provide robust, self-healing connections.

## Core Design Principles

### 1. **Separation of Concerns**
Each manager handles a specific domain:
- **ConnectionManager**: VNC client lifecycle and UI state orchestration
- **SSHTunnelManager**: SSH tunnel creation with connection pooling
- **SSHConnectionPool**: SSH connection multiplexing and reuse
- **SSHResilienceManager**: SSH health monitoring and auto-reconnection
- **VNCResilienceManager**: VNC health monitoring and user experience
- **VNCOptimizationManager**: Performance tuning and network adaptation
- **ConnectionDiagnosticsManager**: Centralized structured logging and tracing

### 2. **Independent Resilience**
- SSH and VNC resilience operate independently
- Each has its own health monitoring, reconnection logic, and failure handling
- Network changes trigger coordinated adaptation across all managers

### 3. **Notification-Based Coordination**
- Loose coupling via `NotificationCenter` 
- Prevents circular dependencies
- Allows independent testing and development

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        UI Layer (SwiftUI)                       │
├─────────────────────────────────────────────────────────────────┤
│                    ConnectionManager                            │
│                 (Central Orchestrator)                         │
├─────────────────┬─────────────────┬─────────────────────────────┤
│  SSHTunnelMgr   │ VNCClients      │  NetworkMonitor            │
│  (Tunnel Mgmt)  │ (LibVNC)        │  (Connectivity)            │
├─────────────────┼─────────────────┼─────────────────────────────┤
│ SSHConnPool     │ VNCResilience   │  VNCOptimization           │
│ (Multiplexing)  │ (VNC Health)    │  (Performance)             │
├─────────────────┼─────────────────┼─────────────────────────────┤
│ SSHResilience   │ DiagnosticsMgr  │  GridLayoutMgr             │
│ (SSH Health)    │ (Logging)       │  (Window Layout)           │
├─────────────────┴─────────────────┴─────────────────────────────┤
│        Infrastructure (Keychain, CoreData, Ports)              │
└─────────────────────────────────────────────────────────────────┘
```

## Key Architectural Patterns

### 1. **Manager Pattern**
Each major subsystem is implemented as a singleton manager with:
- `@MainActor` for thread safety
- `@Published` properties for reactive UI
- Clear public interface for coordination

### 2. **State Machine Integration**
- **ConnectionManager**: Primary state machine (`ConnectionLifecycleState`)
- **Resilience Managers**: Independent state tracking with coordination
- **Notification Synchronization**: Cross-manager state updates

### 3. **Network-Aware Adaptation**
- **NetworkMonitor**: Detects connection type and changes
- **Dynamic Optimization**: Adjusts VNC settings based on network
- **Resilience Adaptation**: Modifies reconnection behavior

## Connection Flow Architecture

### Establishment Sequence
```
User → ConnectionManager → SSHTunnelManager → SSH Connection
                ↓                ↓
        VNC Configuration ← Optimization ← Network Assessment
                ↓
        VNC Connection → Success → Health Monitoring
```

### Resilience Sequence  
```
Network Change → NetworkMonitor → All Managers
                      ↓
Health Check Failure → Resilience Manager → Reconnection Logic
                      ↓
    Auto-Recovery → Update State → Notify UI
```

## Technology Stack Integration

### **Swift Concurrency**
- `async/await` for connection establishment
- `Task` management for health monitoring
- `@MainActor` for UI thread safety
- Structured concurrency for cleanup operations

### **SwiftNIO SSH**
- Custom channel handlers (SSHChannelDataUnwrappingHandler)
- Event loop integration with MultiThreadedEventLoopGroup
- SSH connection multiplexing via MasterSSHConnection
- Port forwarding implementation (SSHPortForwardingHandler)

### **LibVNC Integration**
- Thread-safe wrapper (LibVNCWrapper) for C library
- Proper memory management and cleanup
- Framebuffer optimization for performance
- Input event handling (mouse and keyboard)
- **Dual-Queue Architecture** (v0.70):
  - `vncQueue`: Handles VNC protocol and framebuffer updates
  - `inputQueue`: Processes mouse/keyboard events without blocking
  - Prevents deadlock between event loop and input handling

### **Combine Framework**
- Reactive UI updates via `@Published`
- Network change event streaming
- Cross-manager coordination via NotificationCenter

### **visionOS Integration**
- Window lifecycle management per connection
- Individual VNC windows (VNCConnectionWindowView)
- System notification handling
- RealityKit content integration

## Performance Characteristics

### **Connection Times**
- **Achieved**: <5 seconds for SSH tunnel + VNC connection
- **SSH Timeout**: 15 seconds for initial connection
- **VNC Timeout**: 15 seconds for initial connection
- **Optimization**: Dynamic encoding based on network type
- **Resilience**: <15 seconds for auto-reconnection

### **Resource Management**
- **Dynamic Port Allocation**: 20000-30000 range
- **Memory Optimization**: Adaptive framebuffer handling
- **Thread Management**: Dedicated EventLoopGroup for SSH

### **Network Adaptation**
- **Cellular**: High compression, low quality (15 FPS)
- **WiFi**: Balanced settings (30 FPS)  
- **Wired**: Performance settings (60 FPS)

## Security Architecture

### **Multi-Layer Security**
1. **SSH Tunneling**: All VNC traffic encrypted via SSH
2. **Keychain Integration**: Secure credential storage
3. **OTP Support**: Multi-factor authentication
4. **Host Key Validation**: Future Sprint 4 enhancement

### **Connection Security**
- All VNC connections require SSH tunnel
- No direct VNC connections allowed
- Automatic tunnel cleanup on disconnection
- Secure credential storage via iOS Keychain
- OTP support for multi-factor authentication

## Resilience Strategy

### **SSH Resilience**
- **Health Checks**: 30-second intervals
- **Auto-Reconnection**: Up to 3 attempts with 5-second delays
- **Network Awareness**: Adapts to connection type changes
- **Timeout Management**: 15-second connection timeout

### **VNC Resilience**
- **Health Checks**: 15-second intervals
- **Auto-Reconnection**: Up to 2 attempts with 3-second delays
- **Error Translation**: User-friendly error messages
- **SSH Coordination**: Defers to SSH resilience when tunnel fails

## Current Status - Version 0.70 TestFlight Release

### ✅ **Completed Features**
- Complete SSH tunnel implementation with SwiftNIO SSH
- SSH connection pooling and multiplexing (MasterSSHConnection)
- Multi-connection support with separate windows per connection
- Network monitoring and automatic adaptation
- SSH connection timeouts (15s) and resilience (3 retry attempts)
- SSH tunnel auto-reconnection with 5-second delays
- VNC failover and error handling with user-friendly messages
- Performance optimization framework with network-based settings
- Connection diagnostics with structured logging and tracing
- **Critical Fix (v0.70)**: Separate input queue architecture prevents deadlock between VNC event loop and input handling
- OTP support for multi-factor authentication
- Grid layout management for multiple connection windows
- Production-ready error handling and recovery mechanisms

### 🔧 **Recent Improvements**
- Removed debug logging and test views (VNCTestView, SSHTestView)
- Cleaned up redundant code paths in connection management
- Consolidated cleanup methods to prevent race conditions
- Enhanced thread safety with proper async/await patterns

### 📋 **Known Limitations**
1. **Host Key Verification**: Planned for future security hardening
2. **SSH Key Authentication**: Currently password/OTP only
3. **Certificate Authentication**: Not yet implemented
4. **Connection Sharing**: Each connection uses its own SSH tunnel

## Future Architecture Evolution

### **Version 1.0: Security Hardening**
- Host key verification and storage
- SSH key authentication support
- Certificate-based authentication
- Connection audit logging
- Biometric authentication for stored credentials

### **Version 1.1: Enterprise Features**
- Enhanced connection pooling and sharing
- Advanced diagnostics dashboard
- Performance analytics and reporting
- Bulk connection management
- Export/import connection profiles

## Architectural Benefits

### **Maintainability**
- Clear component boundaries
- Independent testing capability
- Modular development approach

### **Reliability**
- Multi-layer failure detection
- Automatic recovery mechanisms
- Network-aware adaptation

### **Performance**
- Dynamic optimization
- Resource efficiency
- Adaptive quality management

### **User Experience**
- Transparent resilience
- User-friendly error messages
- Seamless reconnection

## Implementation Notes

### **Key Architectural Decisions**
1. **SSH Multiplexing**: Reuse SSH connections via MasterSSHConnection to reduce overhead
2. **Structured Logging**: ConnectionDiagnosticsManager provides centralized, traceable logging
3. **Window Per Connection**: Each VNC connection gets its own window for better multi-tasking
4. **Async/Await**: Modern Swift concurrency for cleaner, safer asynchronous code
5. **Notification-Based Coordination**: Loose coupling between managers prevents circular dependencies

### **Production Readiness**
- Comprehensive error handling with user-friendly messages
- Automatic recovery from network interruptions
- Resource cleanup to prevent memory leaks
- Thread-safe operations throughout
- Extensive logging for troubleshooting (without debug clutter)

This architecture has been battle-tested and is ready for production use in Version 0.70 TestFlight release, providing a robust foundation for secure VNC-over-SSH connections with comprehensive resilience and optimization features.