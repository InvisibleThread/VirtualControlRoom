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

### Current Development Phase
**Sprint 0.5 Status**: ✅ COMPLETE - December 5-6, 2024

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

**Key Files**:
- `VirtualControlRoom/VNCSimpleWindowView.swift` - Main VNC display window with input handling
- `VirtualControlRoom/Services/VNC/LibVNCClient.swift` - Swift wrapper for LibVNC integration
- `VirtualControlRoom/Services/VNC/LibVNCWrapper.m` - Objective-C wrapper for LibVNC C library
- `VirtualControlRoom/VNCTestView.swift` - Connection configuration UI

**VNC Implementation Note**: 
- Uses LibVNC C library for robust TightVNC server compatibility
- RoyalVNC completely removed from project (was causing runtime crashes)
- Swift wrapper provides clean interface to LibVNC
- Thread-safe property access implemented to prevent race conditions

**Current Status (Dec 6, 2024)**: 
- ✅ App builds and runs on Apple Vision Pro without crashes
- ✅ VNC Test method successfully connects to VNC servers
- ✅ All major stability issues resolved
- 🎯 **READY FOR NEXT DEVELOPMENT SESSION**

**Next Sprint**: 1 - Connection Profile UI
- Core Data models for connection profiles  
- CRUD operations for managing connections
- Profile selection UI

### Development Approach Updates
- Shifted from phase-based to sprint-based development (2-3 days per sprint)
- Each sprint delivers testable functionality for user feedback
- Sprint 0.5 validated that RealityKit texture updates work for VNC
- Real VNC protocol implementation deferred to Sprint 4
- See docs/development-tracker.md for detailed sprint plan and testing checkpoints

## Important Implementation Notes

- VNC connections must be implemented through SSH tunnels for security
- Use SwiftNIO SSH for tunnel management
- Consider LibVNCClient wrapper or pure Swift VNC implementation
- RealityKit entities render remote desktop windows as Metal textures
- Support 6-8 concurrent connections with adaptive quality
- Follow Apple's visionOS Human Interface Guidelines for spatial computing