# Privacy Policy - Virtual Control Room

**Effective Date: January 7, 2025**  
**App Version: 0.5**

## Overview
Virtual Control Room is designed with privacy and security as core principles. This policy explains how we handle your data.

## Information We Collect

### Automatically Collected
- **App Usage Analytics**: Performance metrics, feature usage, crash reports
- **Device Information**: iOS version, device type (for compatibility)
- **Connection Metadata**: Number of connections, connection duration (no content)

### User-Provided Information
- **Connection Profiles**: Server hostnames, usernames, port numbers
- **SSH Configuration**: Host keys, connection settings (passwords stored in Keychain only)

## Information We Do NOT Collect
- ❌ Passwords or private keys
- ❌ VNC session content or screenshots
- ❌ Files accessed through remote connections
- ❌ Keyboard input or mouse movements
- ❌ Personal documents or data on remote systems
- ❌ Network traffic content

## How We Store Your Data

### Local Storage Only
- **Passwords & Keys**: Stored securely in iOS Keychain (never leaves your device)
- **Connection Profiles**: Stored locally using Core Data
- **App Preferences**: Stored in iOS UserDefaults

### No Cloud Storage
- We do not store any of your connection data on our servers
- All data remains on your device
- No automatic backups of sensitive information

## How We Use Information

### Analytics Data
- Improve app performance and stability
- Identify and fix bugs
- Understand feature usage to guide development
- All analytics are aggregated and anonymous

### Connection Data
- Enable VNC connections to your authorized servers
- Remember your connection preferences
- Provide connection history for convenience

## Data Sharing
We do **NOT** share your data with third parties, except:
- **Crash Reports**: Anonymous crash data may be shared with Apple for debugging
- **Legal Requirements**: If required by law (we will notify you unless prohibited)

## Security Measures
- **Encryption**: All VNC traffic encrypted through SSH tunnels
- **Keychain**: Passwords stored using iOS Keychain Services
- **Local Processing**: All credential handling happens on-device
- **No Transmission**: Credentials never transmitted to our servers

## Your Rights
- **Access**: All your data is stored locally and accessible to you
- **Deletion**: Delete the app to remove all stored data
- **Control**: You control all connection profiles and credentials
- **Opt-out**: Disable analytics in iOS Settings > Privacy & Security > Analytics

## Children's Privacy
Virtual Control Room is not directed at children under 13. We do not knowingly collect data from children under 13.

## International Users
If you use the app outside [YOUR COUNTRY], your data is still processed according to this policy and stored locally on your device.

## Changes to This Policy
We may update this policy for new app versions. Continued use constitutes acceptance of changes.

## Data Retention
- **Connection Profiles**: Retained until you delete them or the app
- **Analytics**: Aggregated data may be retained for development purposes
- **Crash Reports**: Retained as needed for debugging, then deleted

## Third-Party Components
The app uses open-source libraries that do not collect user data:
- LibVNC: VNC protocol implementation
- SwiftNIO SSH: SSH tunnel implementation
- Apple Frameworks: Standard iOS/visionOS functionality

## Contact Us
Privacy questions or concerns:
- **Email**: [YOUR PRIVACY EMAIL]
- **Website**: [YOUR WEBSITE]

## Compliance
This policy complies with:
- Apple App Store Review Guidelines
- iOS Privacy Standards
- General Data Protection practices

---

**Last Updated**: January 7, 2025  
**App Version**: 0.5  

*Virtual Control Room respects your privacy. All sensitive data stays on your device, and connections are always encrypted.*