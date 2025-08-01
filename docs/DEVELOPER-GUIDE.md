# Virtual Control Room Developer Guide

## Table of Contents
1. [Development Environment Setup](#development-environment-setup)
2. [Building the Project](#building-the-project)
3. [Architecture Overview](#architecture-overview)
4. [Key Components](#key-components)
5. [LibVNC Integration](#libvnc-integration)
6. [SSH Tunneling](#ssh-tunneling)
7. [Testing](#testing)
8. [Debugging](#debugging)
9. [Contributing](#contributing)

## Development Environment Setup

### Requirements
- **macOS**: 15.0 (Sequoia) or later
- **Xcode**: 16.0 or later
- **visionOS SDK**: 2.0+
- **Swift**: 6.0
- **Apple Vision Pro**: For device testing

### Initial Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/[organization]/VirtualControlRoom.git
   cd VirtualControlRoom
   ```

2. **Open in Xcode**:
   ```bash
   open VirtualControlRoom/VirtualControlRoom.xcodeproj
   ```

3. **Install dependencies**:
   - SwiftNIO SSH is included via Swift Package Manager
   - LibVNC is pre-built and included in the project

4. **Configure signing**:
   - Select your development team in project settings
   - Ensure proper entitlements for network access

## Building the Project

### Build Configurations

**Debug Build**:
```bash
xcodebuild -scheme VirtualControlRoom -configuration Debug build
```

**Release Build**:
```bash
xcodebuild -scheme VirtualControlRoom -configuration Release build
```

**Clean Build**:
```bash
xcodebuild -scheme VirtualControlRoom clean build
```

### Running on Simulator
1. Select "Apple Vision Pro" simulator in Xcode
2. Press Cmd+R to build and run
3. Note: Some features may be limited in simulator

### Running on Device
1. Connect Apple Vision Pro via USB-C
2. Enable Developer Mode on device
3. Select your device in Xcode
4. Press Cmd+R to build and run

## Architecture Overview

### Design Principles
- **Modular Architecture**: Separate managers for distinct responsibilities
- **Protocol-Oriented**: Heavy use of protocols for testability
- **Reactive**: Combine framework for data flow
- **Concurrent**: Modern Swift concurrency (async/await)

### Layer Structure
```
┌─────────────────────────────────────────────────┐
│                UI Layer (SwiftUI)               │
├─────────────────────────────────────────────────┤
│              Service Layer                      │
│  (ConnectionManager, SSHTunnelManager, etc.)   │
├─────────────────────────────────────────────────┤
│              Network Layer                      │
│    (LibVNC, SwiftNIO SSH, URLSession)         │
├─────────────────────────────────────────────────┤
│            Persistence Layer                    │
│      (Core Data, Keychain, UserDefaults)       │
└─────────────────────────────────────────────────┘
```

## Key Components

### ConnectionManager
Central orchestrator for all connections:
- Manages VNC client lifecycle
- Coordinates with SSH tunnel manager
- Handles connection state transitions
- Publishes connection updates to UI

**Key Methods**:
```swift
func connect(to profile: ConnectionProfile) async
func disconnect(connectionID: String)
func disconnectAll()
```

### SSHTunnelManager
Handles SSH tunnel creation and management:
- Creates secure tunnels for VNC
- Manages local port allocation
- Implements connection pooling
- Handles SSH authentication

**Key Features**:
- Dynamic port allocation (20000-30000)
- Connection multiplexing
- OTP support
- Auto-reconnection

### LibVNCClient
Swift wrapper around LibVNC C library:
- Manages VNC protocol communication
- Handles framebuffer updates
- Processes input events
- Thread-safe implementation

**Important**: Uses separate queues for event loop and input to prevent deadlock.

### VNCSimpleWindowView
Main UI component for VNC display:
- Renders remote desktop content
- Handles touch/mouse input
- Manages keyboard focus
- Implements gesture recognizers

## LibVNC Integration

### Architecture
```
VNCSimpleWindowView (SwiftUI)
        ↓
LibVNCClient (Swift)
        ↓
LibVNCWrapper (Objective-C)
        ↓
libvncclient (C Library)
```

### Building LibVNC
LibVNC is pre-built for arm64 architecture:

1. **Location**: `/VirtualControlRoom/build-libs/libvncserver/`

2. **Build Script** (if needed):
   ```bash
   cd VirtualControlRoom/build-libs
   ./build-libvnc.sh
   ```

3. **Architecture Support**:
   - Currently: arm64 (Apple Silicon, Vision Pro)
   - TODO: Add x86_64 for simulator support

### Input Queue Architecture
Critical fix in v0.70 - separate queues prevent deadlock:
```objc
// Event loop runs on vncQueue
_vncQueue = dispatch_queue_create("com.virtualcontrolroom.vnc", DISPATCH_QUEUE_SERIAL);

// Input events use separate queue
_inputQueue = dispatch_queue_create("com.virtualcontrolroom.vnc.input", DISPATCH_QUEUE_SERIAL);
```

## SSH Tunneling

### SwiftNIO SSH Integration
Uses Apple's SwiftNIO SSH for secure tunneling:

1. **Connection Flow**:
   ```
   App → SSHTunnelManager → MasterSSHConnection → SSH Server
                ↓
         Local Port Forwarding → VNC Server
   ```

2. **Multiplexing**:
   - Single SSH connection per host
   - Multiple channels for different forwards
   - Efficient resource usage

3. **Authentication**:
   - Password authentication
   - OTP support (append to password)
   - Key-based auth (future)

### Port Forwarding
Dynamic local port allocation:
```swift
let localPort = try portManager.allocatePort() // 20000-30000
try await createPortForwardingChannel(
    localPort: localPort,
    remoteHost: "localhost",
    remotePort: 5900
)
```

## Testing

### Unit Tests
```bash
xcodebuild -scheme VirtualControlRoom test
```

**Key Test Areas**:
- Connection profile CRUD operations
- SSH tunnel creation/teardown
- VNC connection states
- Input event handling
- Error scenarios

### Integration Tests
Test with real VNC servers:
1. Set up test VNC server
2. Configure test profiles
3. Run integration test suite
4. Verify frame updates and input

### Manual Testing Checklist
- [ ] Connection creation
- [ ] SSH authentication (password)
- [ ] SSH authentication (OTP)
- [ ] VNC connection
- [ ] Mouse input (tap, long-press, drag)
- [ ] Keyboard input
- [ ] Multiple connections
- [ ] Reconnection after network loss
- [ ] Error handling

## Debugging

### Common Issues

**LibVNC Crashes**:
- Check `clientData` initialization
- Verify callbacks set after `rfbInitClient`
- Look for memory management issues

**SSH Connection Failures**:
- Enable SSH debug logging
- Check authentication logs
- Verify port forwarding enabled on server

**Input Not Working**:
- Verify queue separation (vncQueue vs inputQueue)
- Check focus state
- Look for gesture recognizer conflicts

### Debug Logging

Enable verbose logging:
```swift
// In ConnectionDiagnosticsManager
static let enableVerboseLogging = true
```

View logs:
```bash
# In Xcode console or:
log show --predicate 'subsystem == "com.virtualcontrolroom"' --last 1h
```

### Performance Profiling
1. Use Instruments for performance analysis
2. Monitor frame rates with VNC optimization manager
3. Check network latency impact
4. Profile memory usage during long sessions

## Contributing

### Code Style
- Follow Swift API Design Guidelines
- Use meaningful variable names
- Add documentation comments for public APIs
- Keep functions focused and small

### Pull Request Process
1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Make changes with clear commits
4. Add/update tests as needed
5. Update documentation
6. Submit PR with description

### Commit Guidelines
Format: `<type>: <description>`

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `refactor`: Code refactoring
- `test`: Test additions/changes
- `chore`: Maintenance tasks

Example:
```
fix: Resolve mouse input deadlock with separate input queue
```

### Testing Requirements
- All new features must include tests
- Maintain >80% code coverage
- Test error scenarios
- Verify thread safety

### Documentation
- Update relevant .md files
- Add inline code comments
- Document complex algorithms
- Keep CHANGELOG.md current

## Advanced Topics

### Custom VNC Encodings
To add new VNC encoding support:
1. Implement in LibVNC C code
2. Update LibVNCWrapper interface
3. Add Swift wrapper methods
4. Update optimization manager

### Network Resilience
The app implements multiple resilience layers:
- SSH connection monitoring
- VNC health checks
- Automatic reconnection
- Network change adaptation

### Security Considerations
- All credentials in Keychain
- No plaintext password storage
- SSH tunnel enforcement
- Input validation
- Memory cleanup for sensitive data

## Resources

### Internal Documentation
- [Architecture Summary](../architecture-summary.md)
- [SSH Setup Instructions](ssh-setup-instructions.md)
- [CLAUDE.md](../CLAUDE.md) - AI assistance guide

### External Resources
- [LibVNC Documentation](https://libvnc.github.io/doc/html/)
- [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh)
- [visionOS Documentation](https://developer.apple.com/visionos/)
- [RealityKit Documentation](https://developer.apple.com/documentation/realitykit)

---

© 2025 Virtual Control Room. All rights reserved.