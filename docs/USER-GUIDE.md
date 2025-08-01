# Virtual Control Room User Guide

## Table of Contents
1. [Getting Started](#getting-started)
2. [Creating Connection Profiles](#creating-connection-profiles)
3. [Connecting to Remote Desktops](#connecting-to-remote-desktops)
4. [Using the Interface](#using-the-interface)
5. [Keyboard and Mouse Controls](#keyboard-and-mouse-controls)
6. [Managing Multiple Connections](#managing-multiple-connections)
7. [Troubleshooting](#troubleshooting)
8. [Security Best Practices](#security-best-practices)

## Getting Started

### Prerequisites
Before using Virtual Control Room, ensure you have:
1. An Apple Vision Pro with visionOS 2.0 or later
2. Access to a remote computer with:
   - SSH server installed and running
   - VNC server installed and configured
   - Network connectivity from your Vision Pro

### First Launch
When you first open Virtual Control Room:
1. The app will request permission to access your local network
2. You'll see the main connection list (initially empty)
3. Tap "Add Connection" to create your first profile

## Creating Connection Profiles

### Basic Profile Setup

1. **Profile Name**: Give your connection a memorable name (e.g., "Work Desktop", "Home Server")

2. **SSH Configuration**:
   - **SSH Host**: The IP address or hostname of your SSH server
   - **SSH Port**: Usually 22 (default SSH port)
   - **SSH Username**: Your SSH login username
   - **SSH Password**: Your SSH password (stored securely in Keychain)
   - **Use OTP**: Enable if your server requires one-time passwords

3. **VNC Configuration**:
   - **VNC Host**: Usually "localhost" or "127.0.0.1" when tunneling
   - **VNC Port**: The VNC server port (commonly 5900, 5901, etc.)
   - **VNC Password**: Your VNC password (if required)

### Direct VNC Connection (Not Recommended)
If you must connect directly without SSH:
1. Toggle off "Use SSH Tunnel"
2. Enter the actual VNC server address in "VNC Host"
3. ⚠️ **Warning**: This is insecure and should only be used on trusted networks

### Advanced Options
- **Connect at Startup**: Automatically connect when the app launches
- **Quality Settings**: Choose between Automatic, High Quality, Balanced, or Fast
- **Frame Rate**: Set maximum FPS (15-60)

## Connecting to Remote Desktops

### Making a Connection
1. Select a profile from your connection list
2. Tap "Connect" or double-tap the profile
3. If using OTP, enter the current code when prompted
4. Wait for the connection to establish (typically 2-5 seconds)
5. Your remote desktop appears in a new spatial window

### Connection States
- 🔵 **Connecting**: Establishing SSH tunnel and VNC connection
- 🟢 **Connected**: Active connection, ready to use
- 🟡 **Reconnecting**: Temporary network issue, auto-recovery in progress
- 🔴 **Disconnected**: Connection closed or failed

## Using the Interface

### Window Management
- **Move Windows**: Look at the window bar and pinch to grab, then move your hand
- **Resize Windows**: Look at window corners and pinch-drag to resize
- **Close Windows**: Tap the close button (X) in the window bar
- **Minimize/Maximize**: Use the window control buttons

### Focus and Input
- **Focus a Window**: Look at it and tap, or tap the window directly
- **Keyboard Input**: Once focused, type normally on your keyboard
- **Virtual Keyboard**: Tap the keyboard button if no hardware keyboard is connected

## Keyboard and Mouse Controls

### Mouse Operations
- **Left Click**: Single tap on the remote desktop
- **Right Click**: Long press (hold for 0.5 seconds)
- **Drag**: Tap, hold, and drag your finger
- **Scroll**: Two-finger swipe up/down (if supported by VNC server)

### Keyboard Shortcuts
All standard keyboard shortcuts work as expected:
- **Cmd+C/V**: Copy/Paste (if clipboard sharing is enabled)
- **Cmd+Tab**: Switch applications (on remote system)
- **Modifier Keys**: Shift, Control, Option, Command all supported
- **Function Keys**: F1-F12 available via keyboard

### Special Keys
- **Escape**: Hardware keyboard ESC or virtual keyboard button
- **Tab**: Hardware keyboard or virtual keyboard
- **Arrow Keys**: Hardware keyboard or on-screen controls

## Managing Multiple Connections

### Simultaneous Connections
- Connect to up to 6-8 remote desktops simultaneously
- Each connection opens in its own spatial window
- Arrange windows around your workspace as needed

### Switching Between Connections
- Simply look at and tap the window you want to use
- Use the connection list to see all active connections
- Colored indicators show connection status

### Connection Groups
- Create folders to organize related connections
- Connect to all profiles in a group simultaneously
- Useful for monitoring multiple servers

## Troubleshooting

### Common Connection Issues

**"Connection Refused"**
- Verify SSH server is running: `sudo systemctl status sshd`
- Check firewall isn't blocking port 22
- Ensure correct IP address/hostname

**"Authentication Failed"**
- Double-check username and password
- For OTP, ensure codes are synchronized
- Try connecting via terminal first to verify credentials

**"VNC Connection Failed"**
- Ensure VNC server is running on the remote system
- Verify VNC port number (5900, 5901, etc.)
- Check if VNC requires a password

**"Connection Timeout"**
- Check network connectivity
- Verify server is accessible: `ping server-address`
- Try increasing connection timeout in settings

### Performance Issues

**Slow or Laggy Connection**
- Switch to "Fast" quality mode
- Reduce frame rate to 15-30 FPS
- Check network bandwidth and latency
- Move closer to WiFi router

**Blurry Display**
- Switch to "High Quality" mode if bandwidth allows
- Check VNC server resolution settings
- Ensure VNC color depth is set to 24-bit

### Input Problems

**Keyboard Not Working**
- Tap the window to ensure it has focus
- Check keyboard is connected and enabled
- Try toggling the virtual keyboard

**Mouse Clicks Not Registering**
- Ensure you're tapping within the remote desktop area
- Check if the remote system is responsive
- Try reconnecting if input stops working

## Security Best Practices

### SSH Security
1. **Use Key-Based Authentication** when possible
2. **Enable Two-Factor Authentication** on SSH server
3. **Change Default Ports** to reduce automated attacks
4. **Keep SSH Server Updated** with security patches
5. **Use Strong Passwords** (min 12 characters, mixed case, numbers, symbols)

### VNC Security
1. **Never Expose VNC Directly** to the internet
2. **Always Use SSH Tunneling** for VNC connections
3. **Set VNC Passwords** even when tunneling
4. **Limit VNC Access** to localhost only on server
5. **Use Encrypted VNC** protocols when available

### Network Security
1. **Use Trusted Networks** only
2. **Avoid Public WiFi** for sensitive connections
3. **Enable Firewall** on both client and server
4. **Monitor Access Logs** regularly
5. **Disconnect When Done** to free resources

### App Security
- All passwords are stored in iOS Keychain (encrypted)
- SSH keys are sandboxed per-app
- No connection data is sent to external servers
- Local-only operation (no cloud components)

## Tips and Tricks

### Productivity Tips
- Arrange windows in a semicircle for easy viewing
- Use connection groups for related servers
- Set up quick-connect profiles for frequent access
- Adjust quality per connection based on usage

### Performance Optimization
- Use wired network for servers when possible
- Close unused connections to free resources
- Lower quality for text-only work
- Increase quality for graphical applications

### Accessibility
- Adjust window distance for comfort
- Use larger text sizes on remote systems
- Enable high contrast if needed
- Take regular breaks to prevent eye strain

## Getting Help

### Resources
- Check the [FAQ](FAQ.md) for common questions
- Review [Troubleshooting](#troubleshooting) section
- Visit our website (coming soon)

### Support Channels
- TestFlight feedback button
- Email: support@virtualcontrolroom.app (coming soon)
- GitHub Issues (coming soon)

### Reporting Issues
When reporting problems, please include:
- visionOS version
- App version (see Settings > About)
- Connection type (SSH tunneled or direct)
- Error messages (exact text)
- Steps to reproduce the issue

---

© 2025 Virtual Control Room. All rights reserved.