# Sprint 2: SSH Setup Instructions

## Adding SwiftNIO SSH Dependency

To complete the SSH integration, you need to add the SwiftNIO SSH package dependency through Xcode:

### Step 1: Add Package Dependency

1. Open `VirtualControlRoom.xcodeproj` in Xcode
2. Select the project in the navigator (top level "VirtualControlRoom")
3. Select the "VirtualControlRoom" target
4. Go to the "Package Dependencies" tab
5. Click the "+" button to add a new package
6. Enter this URL: `https://github.com/apple/swift-nio-ssh.git`
7. Select "Up to Next Major Version" and ensure it's set to version 0.8.0 or later
8. Click "Add Package"
9. Select "NIOSSH" and "NIOSSHClient" libraries
10. Click "Add Package"

### Step 2: Update SSH Service Implementation

Once the package is added, you need to update the SSH service to use real SwiftNIO SSH instead of simulation:

1. Replace the simulation methods in `SSHConnectionService.swift` with actual SwiftNIO SSH calls
2. Import NIOSSH at the top of the file
3. Implement real SSH connection, authentication, and tunneling

### Step 3: Test the Implementation

Use the SSH Test View to validate each component:

1. Open the app and go to Settings → Test SSH Connection
2. Test connection functionality first
3. Test authentication with both password and key-based auth
4. Test tunnel creation independently
5. Run full integration test

## Testing Strategy

The SSH testing is designed to validate each component independently:

### Phase 1: Connection Testing
- Test basic SSH connectivity to servers
- Validate host resolution and port connectivity
- Test connection timeouts and error handling

### Phase 2: Authentication Testing
- Test password-based authentication
- Test private key authentication
- Test authentication failure scenarios

### Phase 3: Tunnel Testing
- Test SSH tunnel creation (port forwarding)
- Validate local port allocation
- Test tunnel data flow (without VNC)

### Phase 4: Integration Testing
- Combine SSH + VNC connections
- Test multi-connection scenarios with SSH tunnels
- Performance and stability testing

## Files Created

- `Services/SSH/SSHConnectionService.swift` - Main SSH service with testing framework
- `Views/SSH/SSHTestView.swift` - Independent SSH testing UI
- `docs/ssh-setup-instructions.md` - These setup instructions

## Next Steps After Package Addition

1. Replace simulation methods with real SwiftNIO SSH implementation
2. Add SSH configuration to connection profiles
3. Integrate SSH tunneling with existing VNC connections
4. Update connection manager to handle SSH tunnel lifecycle

## Security Considerations

- SSH private keys should be stored securely (consider Keychain integration)
- SSH host key verification should be implemented
- Connection timeouts and retry logic should be robust
- Tunnel ports should be managed to avoid conflicts

## Testing Checklist

- [ ] SwiftNIO SSH package added successfully
- [ ] SSH connection test passes
- [ ] Password authentication test passes
- [ ] Private key authentication test passes
- [ ] SSH tunnel creation test passes
- [ ] Error handling works correctly
- [ ] Multiple simultaneous tunnels work
- [ ] Integration with VNC connections works
- [ ] Connection cleanup works properly