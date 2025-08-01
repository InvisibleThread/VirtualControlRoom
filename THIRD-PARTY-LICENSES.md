# Third-Party Licenses

This document lists all third-party libraries and their licenses used in Virtual Control Room.

## ⚠️ GPL Licensing Notice

**IMPORTANT**: This project includes GPL v2 licensed components. Due to the "copyleft" nature of GPL, the entire application must be distributed under GPL v2 terms when LibVNC is included.

---

## Libraries and Dependencies

### 1. LibVNC (LibVNCServer/LibVNCClient)
- **Location**: `VirtualControlRoom/build-libs/libvncserver/`
- **License**: GNU General Public License v2
- **Purpose**: VNC protocol implementation for remote desktop connections
- **Website**: https://libvnc.github.io/
- **Source**: https://github.com/LibVNC/libvncserver

**GPL v2 Requirements**:
- Source code must be made available to users
- Derivative works must also be GPL licensed
- No additional restrictions can be placed on users' rights

### 2. Swift NIO SSH
- **Version**: 0.11.0
- **License**: Apache License 2.0
- **Purpose**: SSH tunneling implementation
- **Repository**: https://github.com/apple/swift-nio-ssh
- **Copyright**: Copyright 2019-2024 The SwiftNIO SSH Project

### 3. Swift NIO
- **Version**: 2.84.0
- **License**: Apache License 2.0
- **Purpose**: Networking foundation for SSH implementation
- **Repository**: https://github.com/apple/swift-nio
- **Copyright**: Copyright 2017-2024 The SwiftNIO Project

### 4. Swift Crypto
- **Version**: 3.12.3
- **License**: Apache License 2.0
- **Purpose**: Cryptographic operations for SSH
- **Repository**: https://github.com/apple/swift-crypto
- **Copyright**: Copyright 2019-2024 The SwiftCrypto Project

### 5. Swift ASN1
- **Version**: 1.4.0
- **License**: Apache License 2.0
- **Purpose**: ASN.1 parsing for SSH certificates
- **Repository**: https://github.com/apple/swift-asn1
- **Copyright**: Copyright 2023-2024 The SwiftASN1 Project

### 6. Swift Atomics
- **Version**: 1.3.0
- **License**: Apache License 2.0
- **Purpose**: Low-level atomic operations
- **Repository**: https://github.com/apple/swift-atomics
- **Copyright**: Copyright 2020-2024 The SwiftAtomics Project

### 7. Swift Collections
- **Version**: 1.2.0
- **License**: Apache License 2.0
- **Purpose**: Advanced data structures
- **Repository**: https://github.com/apple/swift-collections
- **Copyright**: Copyright 2020-2024 The SwiftCollections Project

### 8. Swift System
- **Version**: 1.5.0
- **License**: Apache License 2.0
- **Purpose**: Low-level system interfaces
- **Repository**: https://github.com/apple/swift-system
- **Copyright**: Copyright 2020-2024 The SwiftSystem Project

## Apple System Frameworks

The following Apple frameworks are used under Apple's standard developer license terms:

- **SwiftUI**: User interface framework
- **RealityKit**: Spatial computing and AR framework
- **Core Data**: Data persistence framework
- **Network**: Network connectivity monitoring
- **Security**: Keychain and security services
- **Combine**: Reactive programming framework
- **Foundation**: Core system services

## License Compatibility Summary

| Component | License | Compatible with BSD |
|-----------|---------|-------------------|
| LibVNC | GPL v2 | ❌ **NO** - Requires GPL |
| Swift NIO ecosystem | Apache 2.0 | ✅ Yes |
| Apple Frameworks | Proprietary | ✅ Yes (for app dev) |
| Virtual Control Room code | BSD 3-Clause | ✅ Yes |

## Full License Texts

### Apache License 2.0
Used by all Swift NIO components.

Full text available at: https://www.apache.org/licenses/LICENSE-2.0

### GNU General Public License v2
Used by LibVNC.

Full text available at: `VirtualControlRoom/build-libs/libvncserver/COPYING`
Online: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html

### BSD 3-Clause License
Used by Virtual Control Room source code.

Full text available at: `LICENSE`

## Compliance Requirements

### For GPL Compliance (Current State)
1. **Source Code Availability**: Complete source code must be provided to users
2. **License Notice**: GPL v2 license must be included with distributions
3. **No Additional Restrictions**: Cannot add terms beyond GPL v2
4. **User Rights**: Users must receive same rights as original GPL license

### For Pure BSD Licensing (Future)
To achieve pure BSD licensing, LibVNC must be replaced with:
- Custom RFB protocol implementation (recommended)
- BSD/MIT/Apache 2.0 licensed VNC library
- Commercial license for LibVNC (if available)

---

Last updated: January 8, 2025