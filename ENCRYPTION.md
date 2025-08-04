# Encryption Documentation for Virtual Control Room

This document describes the encryption technologies used in Virtual Control Room for Apple App Store compliance and export control purposes.

## Overview

Virtual Control Room uses industry-standard encryption protocols solely for secure communication between the app and remote servers. All encryption is used for authentication and data protection during transmission. The app does not implement any proprietary encryption algorithms.

## Encryption Usage

### 1. SSH Tunnel Encryption (SwiftNIO SSH)

**Purpose**: Secure tunneling for VNC connections

**Implementation**: Apple's SwiftNIO SSH library (version 0.11.0)

**Algorithms Used**:
- Key Exchange: ECDH, DH
- Ciphers: AES-128/256 (CTR/GCM modes), ChaCha20-Poly1305
- MAC: HMAC-SHA256, HMAC-SHA1
- Public Key: RSA, ECDSA, Ed25519

**Standard Compliance**: Fully compliant with SSH-2 protocol (RFC 4253)

### 2. VNC Authentication (LibVNC)

**Purpose**: VNC server authentication

**Implementation**: LibVNCServer/LibVNCClient

**Algorithms Used**:
- DES (56-bit) for VNC password authentication
- Standard VNC protocol encryption as defined in RFB Protocol Specification

**Standard Compliance**: RFB Protocol 3.8 (RFC 6143)

### 3. iOS Keychain Services

**Purpose**: Secure storage of user credentials

**Implementation**: Apple's Security framework

**Algorithms Used**: Apple's built-in encryption (AES-256)

**Standard Compliance**: Uses iOS system encryption

## Export Compliance

### Classification

This app qualifies for export compliance under the following criteria:

1. **Uses only standard encryption protocols** - No proprietary algorithms
2. **Encryption is limited to**:
   - Authentication with remote servers
   - Protection of data in transit
   - Secure credential storage using OS-provided services

3. **Does NOT include**:
   - Proprietary encryption algorithms
   - Encryption of user data at rest (beyond OS-provided)
   - Key escrow features
   - Cryptanalytic capabilities

### ECCN Classification

Based on the encryption usage, this app likely falls under ECCN 5D002, which covers software containing standard encryption for authentication and data protection.

## App Store Declaration

The following has been declared in the app's Info.plist:
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
```

## Compliance Notes

1. All encryption is used solely for secure remote desktop connections
2. No encryption functionality is exposed to end users for other purposes
3. The app relies on well-established, publicly available encryption standards
4. No attempt is made to circumvent or weaken encryption
5. All cryptographic operations are performed by trusted, open-source libraries

## Updates and Maintenance

This document should be updated whenever:
- New encryption libraries are added
- Encryption algorithms are changed
- New features requiring encryption are implemented

Last Updated: 2025-08-04
Version: 0.70