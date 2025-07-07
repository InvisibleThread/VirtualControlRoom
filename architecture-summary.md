# VirtualControlRoom Architecture Summary - Sprint 3

## High-Level System Architecture

VirtualControlRoom implements a **multi-layered resilient architecture** for secure VNC-over-SSH connections on visionOS. The system is designed around independent, specialized managers that coordinate through notifications to provide robust, self-healing connections.

## Core Design Principles

### 1. **Separation of Concerns**
Each manager handles a specific domain:
- **ConnectionManager**: VNC client lifecycle and UI state
- **SSHTunnelManager**: SSH tunnel creation and management  
- **SSHResilienceManager**: SSH health monitoring and auto-reconnection
- **VNCResilienceManager**: VNC health monitoring and user experience
- **VNCOptimizationManager**: Performance tuning and network adaptation

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
│ SSHResilience   │ VNCResilience   │  VNCOptimization           │
│ (SSH Health)    │ (VNC Health)    │  (Performance)             │
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

### **SwiftNIO SSH**
- Custom channel handlers for data conversion
- Event loop integration
- Proper resource management

### **Combine Framework**
- Reactive UI updates via `@Published`
- Network change event streaming
- Cross-manager coordination

### **visionOS Integration**
- Window lifecycle management
- AR space positioning
- System notification handling

## Performance Characteristics

### **Connection Times**
- **Target**: <5 seconds for SSH tunnel + VNC connection
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

## Current Sprint 3 Status

### ✅ **Completed Features**
- Network monitoring and adaptation
- SSH connection timeouts and resilience
- SSH tunnel auto-reconnection
- VNC failover and error handling
- Performance optimization framework

### 🔄 **In Progress**
- User-friendly error message integration
- Performance optimization implementation
- Background connection management
- Real-time health status UI

### 📋 **Technical Debt**
1. **Resource Management**: Complete SSHTunnel reference storage
2. **State Coordination**: Add central coordinator for cross-manager state
3. **Performance Integration**: Implement actual VNC optimization methods
4. **Error Handling**: Complete user-friendly error message system

## Future Architecture Evolution

### **Sprint 4: Security Hardening**
- Host key verification and storage
- SSH key authentication support
- Certificate-based authentication
- Connection audit logging

### **Sprint 5: Enterprise Features**
- Multi-profile management
- Connection pooling and sharing
- Advanced diagnostics and monitoring
- Performance analytics dashboard

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

This architecture provides a solid foundation for a production-ready VNC-over-SSH system with comprehensive resilience, optimization, and user experience features.