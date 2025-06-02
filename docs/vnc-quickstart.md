# VNC Implementation Quick Start Guide

## Step-by-Step Implementation

### 1. Create the Xcode Project

```bash
# Create a new visionOS app
1. Open Xcode
2. File → New → Project
3. Choose visionOS → App
4. Product Name: VirtualControlRoom
5. Organization Identifier: com.yourcompany
6. Interface: SwiftUI
7. Include Tests: Yes
```

### 2. Add LibVNCClient Dependency

#### Option A: Using CocoaPods (If available for visionOS)
```ruby
# Podfile
platform :visionos, '1.0'

target 'VirtualControlRoom' do
  use_frameworks!
  pod 'LibVNCClient'
end
```

#### Option B: Manual Integration
1. Download LibVNCClient source from: https://github.com/LibVNC/libvncserver
2. Add as a framework to your project
3. Update build settings for visionOS compatibility

### 3. Create Project Structure

```
VirtualControlRoom/
├── App/
│   └── VirtualControlRoomApp.swift
├── Core/
│   ├── VNC/
│   │   ├── VNCClient.swift
│   │   ├── VNCConnectionAdapter.swift
│   │   └── VNCTextureProvider.swift
│   ├── SSH/
│   │   └── SSHTunnelService.swift
│   └── Services/
│       ├── ConnectionManager.swift
│       ├── AuthenticationManager.swift
│       └── PortManager.swift
├── UI/
│   ├── Views/
│   │   ├── ConnectionListView.swift
│   │   └── VNCWindowView.swift
│   └── ViewModels/
│       └── ConnectionViewModel.swift
├── Models/
│   └── ConnectionProfile.swift
└── Resources/
    └── VirtualControlRoom-Bridging-Header.h
```

### 4. Create the Bridging Header

```c
// VirtualControlRoom-Bridging-Header.h
#ifndef VirtualControlRoom_Bridging_Header_h
#define VirtualControlRoom_Bridging_Header_h

#import <rfb/rfbclient.h>

typedef struct {
    void *swiftContext;
} SwiftCallbacks;

#endif
```

**Important**: In Build Settings, set "Objective-C Bridging Header" to the path of this file.

### 5. Implement Core VNC Wrapper

Create `Core/VNC/VNCClient.swift` with the implementation from the guide.

### 6. Create a Simple Test Connection

```swift
// UI/Views/TestConnectionView.swift
import SwiftUI

struct TestConnectionView: View {
    @StateObject private var vncClient = VNCClient()
    @State private var isConnecting = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("VNC Test Connection")
                .font(.largeTitle)
            
            if case .connected = vncClient.connectionState {
                Text("Connected!")
                    .foregroundColor(.green)
                
                // Show frame buffer preview
                if let texture = getCurrentTexture() {
                    Image(texture: texture)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 800, maxHeight: 600)
                }
            }
            
            Button(action: connect) {
                Label("Connect to Test Server", systemImage: "network")
            }
            .disabled(isConnecting)
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
    
    private func connect() {
        isConnecting = true
        errorMessage = nil
        
        Task {
            do {
                // For testing, connect to a local VNC server
                try await vncClient.connect(
                    host: "localhost",
                    port: 5900,
                    username: "test",
                    password: "test"
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }
    
    private func getCurrentTexture() -> MTLTexture? {
        // This would be implemented with the texture provider
        return nil
    }
}
```

### 7. Integration Checklist

- [ ] Add LibVNCClient to project
- [ ] Configure bridging header
- [ ] Implement VNCClient.swift
- [ ] Create test view
- [ ] Test with local VNC server
- [ ] Implement texture rendering
- [ ] Add error handling
- [ ] Integrate with SSH tunnel
- [ ] Connect to Connection Manager

### 8. Testing with a Local VNC Server

#### macOS Built-in VNC Server
```bash
# Enable Screen Sharing in System Preferences
# System Preferences → Sharing → Screen Sharing
# Set VNC password in "Computer Settings..."
```

#### Test VNC Server (Development)
```bash
# Install x11vnc via Homebrew
brew install x11vnc

# Run test server
x11vnc -display :0 -passwd testpass -port 5900
```

### 9. Common Issues and Solutions

#### Issue: LibVNCClient won't compile for visionOS
**Solution**: You may need to modify the build settings:
```
OTHER_CFLAGS = -DTARGET_OS_VISION=1
VALID_ARCHS = arm64
```

#### Issue: Bridging header not found
**Solution**: Use relative path from project root:
```
$(PROJECT_DIR)/VirtualControlRoom/Resources/VirtualControlRoom-Bridging-Header.h
```

#### Issue: Memory issues with frame buffer
**Solution**: Implement proper cleanup in callbacks:
```swift
deinit {
    disconnect()
    // Ensure all C memory is freed
}
```

### 10. Next Steps After Basic Connection Works

1. **Implement SSH Tunnel Integration**
   ```swift
   // Connect through SSH tunnel
   let localPort = try await sshService.createTunnel(
       to: connectionProfile
   )
   try await vncClient.connect(
       host: "localhost",
       port: localPort,
       username: profile.vncUsername,
       password: profile.vncPassword
   )
   ```

2. **Add RealityKit Window Rendering**
   ```swift
   struct VNCWindowView: View {
       @StateObject var textureProvider = VNCTextureProvider()
       
       var body: some View {
           RealityView { content in
               // Create AR window with VNC texture
           }
       }
   }
   ```

3. **Implement Connection Manager**
   ```swift
   class ConnectionManager {
       func createConnection(profile: ConnectionProfile) async throws {
           // 1. Create SSH tunnel
           // 2. Connect VNC
           // 3. Create AR window
       }
   }
   ```

This quick start guide should get you up and running with the VNC implementation. Start with the basic connection test, then gradually add the SSH tunneling and AR rendering components. 