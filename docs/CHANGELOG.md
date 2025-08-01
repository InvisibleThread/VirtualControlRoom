# Changelog

All notable changes to Virtual Control Room will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.70] - 2025-01-08

### Fixed
- **Critical**: Resolved mouse input deadlock issue where pointer events were not being processed
  - Root cause: VNC event loop was blocking the dispatch queue
  - Solution: Implemented separate input queue for mouse and keyboard events
- Improved thread safety in LibVNCWrapper input handling

### Changed
- Removed all debug logging with emoji prefixes for cleaner console output
- Deleted development test views (VNCTestView, SSHTestView)
- Consolidated redundant cleanup methods in ConnectionManager
- Simplified connection cleanup logic

### Added
- Comprehensive code documentation in critical sections
- Separate dispatch queue for input events (inputQueue)
- Detailed inline comments explaining queue architecture
- Public-facing README.md with feature overview
- User Guide documentation
- Developer Guide documentation

### Improved
- Code organization and maintainability
- Documentation structure for public release
- Error handling consistency

## [0.5] - 2025-01-07

### Added
- Initial TestFlight release
- Complete VNC connection support using LibVNC
- SSH tunnel integration with SwiftNIO SSH
- Multi-connection support with separate windows
- Full keyboard and mouse input
- Right-click support via long press
- Connection profile management with Core Data
- Secure credential storage using iOS Keychain
- Network resilience with auto-reconnection
- Performance optimization with adaptive quality
- Connection pooling for SSH efficiency
- OTP (One-Time Password) support
- Comprehensive error handling
- Production-ready logging system

### Features
- Native visionOS 2.0+ support
- Immersive AR/VR workspace
- SSH connection multiplexing
- Dynamic port allocation (20000-30000)
- Network-adaptive frame rates (15-60 FPS)
- Multiple VNC encoding support
- Automatic password retrieval from Keychain
- Connection state persistence

### Security
- All VNC connections tunneled through SSH
- No direct VNC connections allowed
- Encrypted credential storage
- Sandboxed SSH keys
- Input validation and sanitization

### Known Issues
- Audio not supported (VNC protocol limitation)
- File transfer not yet implemented
- Clipboard sharing pending
- Simulator requires x86_64 LibVNC build

## [0.4] - 2024-12-13

### Fixed
- Critical LibVNC crash when connecting to invalid hosts
- EXC_BAD_ACCESS in rfbInitClient failure scenarios
- Memory management issues in LibVNCWrapper
- Thread safety race conditions

### Changed
- LibVNC initialization sequence to prevent callback crashes
- Set clientData=NULL initially, only set after rfbInitClient succeeds

## [0.3] - 2024-12-06

### Fixed
- RoyalVNCKit dependency removal (SIGABRT crash)
- RealityKitContent package reference
- Thread safety race condition in LibVNCWrapper.m:143

### Added
- LibVNC integration for TightVNC compatibility
- Basic VNC connection functionality
- Desktop preview in connection UI

## [0.2] - 2024-11-15

### Added
- Connection profile management UI
- Core Data integration
- Keychain integration for passwords
- Basic SSH configuration UI

### Changed
- Migrated from RoyalVNC to LibVNC
- Improved error handling

## [0.1] - 2024-11-01

### Added
- Initial project setup
- Basic visionOS app structure
- SwiftUI interface foundation
- RealityKit integration

---

## Roadmap

### Planned for 0.80
- Clipboard sharing between local and remote
- File transfer support
- SSH key-based authentication
- Connection history and statistics

### Planned for 0.90
- Multi-monitor support
- Custom keyboard shortcuts
- Connection templates
- Gesture customization

### Planned for 1.0
- App Store release
- iCloud sync for profiles
- macOS companion app
- Advanced window layouts

---

For more details on each release, see the [GitHub Releases](https://github.com/[organization]/VirtualControlRoom/releases) page.