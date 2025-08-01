# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Virtual Control Room is a native visionOS application that enables remote desktop access through VNC connections secured via SSH tunnels. The app allows users to view and interact with multiple remote desktops simultaneously in an AR/VR environment.

## Build Commands

```bash
# Build for Debug
xcodebuild -scheme VirtualControlRoom -configuration Debug build

# Build for Release  
xcodebuild -scheme VirtualControlRoom -configuration Release build

# Run tests
xcodebuild -scheme VirtualControlRoom test

# Clean build
xcodebuild -scheme VirtualControlRoom clean

# Build and run (must use Xcode IDE for visionOS simulator)
# Open VirtualControlRoom.xcodeproj in Xcode and press Cmd+R
```

## Architecture

### Technology Stack
- **Platform**: visionOS 2.0+, macOS 15+, iOS 18+
- **Language**: Swift 6.0
- **UI Framework**: SwiftUI
- **3D/AR Framework**: RealityKit
- **Package Management**: Swift Package Manager

### Core Architecture Pattern
The app follows a modular service architecture with clear separation of concerns:

```
VirtualControlRoomApp (Entry Point)
    ├── AppModel (Global State)
    ├── ContentView (Main UI)
    ├── ImmersiveView (AR Experience)
    └── Services/
        ├── ConnectionManager (Orchestration)
        ├── SSHTunnelService (SwiftNIO SSH)
        ├── VNCClientService (VNC Protocol)
        ├── AuthenticationManager (Credentials)
        ├── LayoutManager (Window Arrangements)
        └── PortManager (Dynamic Ports)
```

### Key Implementation Details

1. **Connection Flow**: 
   - User selects profile → SSH authentication (with OTP) → Establish tunnel → VNC connection → Render in AR

2. **Data Storage**:
   - Core Data: Connection profiles and layouts
   - Keychain: Secure credential storage
   - UserDefaults: App preferences

3. **Security**: All VNC connections tunneled through SSH, biometric-protected credentials

4. **Performance Targets**: <5s connection, 30+ FPS, <100ms latency

### Current Development Status
**Version 0.5 TestFlight Release**: ✅ COMPLETE - January 7, 2025

**Completed Features**:
- ✅ Real VNC connection using LibVNC (NOT RoyalVNC - RoyalVNC doesn't work with TightVNC servers)
- ✅ Desktop preview in connection UI
- ✅ Simple display window with proper aspect ratio
- ✅ Auto-disconnect on window close
- ✅ Clean, minimal UI
- ✅ Mouse and keyboard input implementation
- ✅ Real input forwarding to VNC servers
- ✅ **CRITICAL FIXES** (Dec 6, 2024):
  - Fixed RoyalVNCKit dependency removal (SIGABRT crash)
  - Fixed RealityKitContent package reference
  - Fixed EXC_BAD_ACCESS in LibVNCWrapper.m:143 (thread safety race condition)
  - App now builds and runs successfully on Apple Vision Pro

- ✅ **CRITICAL LIBVNC CRASH FIX** (Dec 13, 2024):
  - Fixed EXC_BAD_ACCESS crashes when connecting to invalid hosts
  - Root cause: rfbInitClient() failure triggered callbacks accessing freed memory
  - Solution: Set clientData=NULL initially, only set callbacks after rfbInitClient succeeds
  - Prevents double-cleanup and callback-during-cleanup crashes
  - References: LibVNC Issues #205, #47

**Key Files**:
- `VirtualControlRoom/VNCSimpleWindowView.swift` - Core VNC display component with input handling
- `VirtualControlRoom/Views/VNCConnectionWindowView.swift` - Connection-specific window wrapper with lifecycle management
- `VirtualControlRoom/Services/VNC/LibVNCClient.swift` - Swift wrapper for LibVNC integration
- `VirtualControlRoom/Services/VNC/LibVNCWrapper.m` - Objective-C wrapper for LibVNC C library
- `VirtualControlRoom/Services/ConnectionManager.swift` - Multi-connection state management and coordination
- `VirtualControlRoom/Views/ConnectionListView.swift` - Connection profile management interface
- `VirtualControlRoom/Views/ConnectionEditView.swift` - Profile creation and editing
- `VirtualControlRoom/Services/ConnectionProfileManager.swift` - Core Data profile management
- `VirtualControlRoom/Services/KeychainManager.swift` - Secure password storage
- `VirtualControlRoom/VNCTestView.swift` - Development/testing connection UI

**Key Production Components**:
- `VirtualControlRoom/Services/NetworkMonitor.swift` - System-wide connectivity intelligence
- `VirtualControlRoom/Services/SSH/SSHResilienceManager.swift` - SSH health monitoring and auto-reconnection
- `VirtualControlRoom/Services/VNC/VNCResilienceManager.swift` - VNC failover and error handling
- `VirtualControlRoom/Services/VNC/VNCOptimizationManager.swift` - Performance tuning and network adaptation
- `VirtualControlRoom/Services/ConnectionDiagnosticsManager.swift` - Structured logging and tracing
- `VirtualControlRoom/Services/SSH/SSHConnectionPool.swift` - SSH connection multiplexing
- `architecture-summary.md` - Current architectural overview and design principles

**VNC Implementation Note**: 
- Uses LibVNC C library for robust TightVNC server compatibility
- RoyalVNC completely removed from project (was causing runtime crashes)
- Swift wrapper provides clean interface to LibVNC
- Thread-safe property access implemented to prevent race conditions

**Development Milestones**:
- ✅ Real VNC connection using LibVNC (TightVNC server compatible)
- ✅ Complete connection profile management with Core Data
- ✅ Secure password storage using iOS Keychain Services
- ✅ Multi-connection support with separate windows per connection
- ✅ Enhanced keyboard and mouse input with right-click support
- ✅ SSH tunnel implementation with SwiftNIO SSH
- ✅ SSH connection pooling and multiplexing for efficiency
- ✅ OTP support for multi-factor authentication
- ✅ Network resilience with auto-reconnection (SSH: 3 attempts, VNC: 2 attempts)
- ✅ Performance optimization with network-adaptive settings (15-60 FPS)
- ✅ Production-ready error handling with user-friendly messages
- ✅ Comprehensive structured logging via ConnectionDiagnosticsManager
- ✅ Thread-safe operations throughout with modern Swift concurrency

**Current Status (Jan 7, 2025)**: 
- ✅ App builds and runs on Apple Vision Pro without crashes
- ✅ VNC connections work reliably with automatic password retrieval
- ✅ Multiple simultaneous connections with separate windows per connection
- ✅ Connection profile CRUD operations fully implemented
- ✅ Secure password storage with Keychain integration
- ✅ Robust multi-connection architecture with proper window lifecycle management
- ✅ Race condition fixes prevent crashes during connection/disconnection
- ✅ SSH tunnel integration complete with SwiftNIO SSH
- ✅ **PRODUCTION-READY SSH TUNNELED VNC CONNECTIONS**
- ✅ **VERSION 0.5 TESTFLIGHT RELEASE** - Alpha build ready for client testing

**Recent Code Quality Improvements** (Jan 8, 2025):
- ✅ Removed all debug logging with emoji prefixes
- ✅ Deleted development test views (VNCTestView, SSHTestView)
- ✅ Consolidated redundant cleanup methods in ConnectionManager
- ✅ Updated architecture documentation to match implementation
- ✅ Added comprehensive code comments to critical sections
- ✅ Cleaned up unused imports and empty code blocks

### Development Approach
- Production-ready codebase following Apple's visionOS best practices
- Modern Swift concurrency (async/await) throughout
- Comprehensive error handling and recovery mechanisms
- Network-adaptive performance optimization
- Clean separation of concerns with modular architecture
- **Version 0.5 TestFlight Release** ready for alpha testing
- See architecture-summary.md for detailed system design

## Important Implementation Notes

- VNC connections must be implemented through SSH tunnels for security
- SwiftNIO SSH used for secure tunnel management
- LibVNCClient wrapper implemented for reliable VNC connections
- RealityKit entities render remote desktop windows as Metal textures
- Support 6-8 concurrent connections with adaptive quality
- Follow Apple's visionOS Human Interface Guidelines for spatial computing