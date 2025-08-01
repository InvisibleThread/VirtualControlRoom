# Virtual Control Room

A native visionOS application that enables secure remote desktop access through VNC connections over SSH tunnels. Experience your remote desktops in an immersive AR/VR environment on Apple Vision Pro.

![Version](https://img.shields.io/badge/version-0.70-blue.svg)
![Platform](https://img.shields.io/badge/platform-visionOS%202.0%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/swift-6.0-orange.svg)
![License](https://img.shields.io/badge/license-GPL%20v2-blue.svg)

## Features

### 🥽 Native visionOS Experience
- Built specifically for Apple Vision Pro
- Immersive AR/VR workspace with multiple floating windows
- Spatial computing interface for natural interaction

### 🔒 Enterprise-Grade Security
- VNC connections have options to be secured through SSH tunnels
- Support for SSH key authentication and OTP
- Credentials stored securely in iOS Keychain

### 🖥️ Multi-Connection Support
- Connect to multiple remote desktops simultaneously
- Each connection in its own spatial window
- Organize your workspace in 3D space
- Quick switching between active sessions

### ⌨️ Full Input Support
- Complete keyboard input with modifier keys
- Mouse movement and clicking
- Right-click support via long press
- Drag and drop operations
- Hardware keyboard integration

### 🚀 High Performance
- Optimized for visionOS with Metal rendering
- Network-adaptive quality settings
- 15-60 FPS dynamic frame rate
- Low latency connections
- Automatic reconnection on network changes

### 📱 Professional Features
- Connection profiles with saved settings
- SSH connection pooling/multiplexing
- Comprehensive error handling
- Network resilience with auto-recovery
- Production-ready logging and diagnostics

## Requirements

- **Device**: Apple Vision Pro
- **OS**: visionOS 2.5 or later
- **Network**: WiFi or Ethernet connection
- **Server Requirements**:
  - SSH server with port forwarding enabled
  - VNC server (TightVNC, RealVNC, TigerVNC, etc.)
  - Valid SSH credentials (password or key-based)

## Quick Start

1. **Install the app** from TestFlight
2. **Create a connection profile**:
   - Tap "Add Connection"
   - Enter your SSH server details
   - Configure VNC settings (typically localhost:5900 when tunneled)
   - Save the profile
3. **Connect**:
   - Select your profile from the list
   - Enter SSH password/OTP if prompted
   - Your remote desktop appears in a spatial window
4. **Interact**:
   - Look at the window and tap to focus
   - Use keyboard for text input
   - Tap for mouse clicks, long press for right-click
   - Pinch and drag to move windows in space

## Documentation

- [User Guide](docs/USER-GUIDE.md) - Detailed setup and usage instructions
- [Developer Guide](docs/DEVELOPER-GUIDE.md) - Build instructions and architecture
- [Architecture Overview](architecture-summary.md) - Technical design documentation
- [Changelog](docs/CHANGELOG.md) - Version history and updates

## Security Best Practices

1. **Always use SSH tunneling** - Never expose VNC directly to the internet
2. **Use strong passwords** or SSH key authentication
3. **Enable two-factor authentication** where possible
4. **Keep your SSH and VNC servers updated**
5. **Use encrypted VNC sessions** when available

## Supported VNC Servers

Virtual Control Room has been tested with:
- TightVNC
- RealVNC
- TigerVNC
- macOS Screen Sharing

## Known Limitations

- Audio is not transmitted (VNC protocol limitation)
- File transfer not yet implemented
- Clipboard sharing coming in future update
- Maximum 6-8 simultaneous connections recommended

## Support

For issues, feature requests, or questions:
- TestFlight feedback
- GitHub Issues (coming soon)
- Email: support@virtualcontrolroom.app (coming soon)

## License

⚠️ **Important Licensing Information**

This project has a **dual licensing situation** due to GPL dependencies:

- **Virtual Control Room source code**: BSD 3-Clause License (see [LICENSE](LICENSE))
- **Complete application**: Must be distributed under **GPL v2** due to LibVNC dependency

### Why GPL v2?

LibVNC (our VNC protocol implementation) is licensed under GPL v2, which is a "copyleft" license. This means any software that includes GPL components must also be distributed under GPL terms.

### For Users
- You have full GPL v2 rights: use, study, modify, and distribute
- Complete source code is available in this repository
- See [GPL-COMPLIANCE.md](GPL-COMPLIANCE.md) for your rights and obligations

### For Developers
- The Virtual Control Room code itself is BSD 3-Clause licensed
- For purely BSD licensing, LibVNC would need to be replaced
- See [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) for all dependency licenses

### App Store Distribution
For App Store distribution only: See [LICENSE-EULA.md](LICENSE-EULA.md)

## Acknowledgments

Built with:
- [LibVNCClient](https://github.com/LibVNC/libvncserver) - VNC protocol implementation
- [SwiftNIO SSH](https://github.com/apple/swift-nio-ssh) - SSH tunneling
- Apple RealityKit and SwiftUI for visionOS

---

© 2025 Virtual Control Room. All rights reserved.