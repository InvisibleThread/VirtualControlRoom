# Virtual Control Room - Development Roadmap

## Overview
This roadmap breaks down the development into modular phases with specific testing checkpoints. Each phase builds upon the previous one, ensuring functionality is verified before proceeding.

## Phase 1: Project Foundation & Core Models (Week 1)

### 1.1 Project Setup
**Tasks:**
- Create visionOS project in Xcode
- Set up folder structure as specified
- Configure Git repository
- Add SwiftLint for code quality

**Deliverables:**
- Empty project with proper structure
- Basic app launches on Vision Pro simulator

### 1.2 Core Data Models
**Tasks:**
- Implement `ConnectionProfile` model
- Implement `BastionHost` model
- Create Core Data stack
- Add basic CRUD operations

**Code to implement:**
```swift
// Models/ConnectionProfile.swift
// Models/BastionHost.swift
// Services/CoreDataManager.swift
```

**Testing Checkpoint 1:**
- [ ] Create unit tests for models
- [ ] Verify Core Data persistence
- [ ] Test CRUD operations
- [ ] **USER TEST**: Run app, verify it launches without crashes

---

## Phase 2: Authentication & Security (Week 1-2)

### 2.1 Keychain Service
**Tasks:**
- Implement `KeychainService` class
- Add credential storage/retrieval
- Implement biometric authentication

**Code to implement:**
```swift
// Services/KeychainService.swift
// Services/BiometricAuthService.swift
```

### 2.2 Authentication Manager
**Tasks:**
- Implement `AuthenticationManager`
- Create OTP input UI component
- Build credential caching logic

**Code to implement:**
```swift
// Services/AuthenticationManager.swift
// UI/Components/OTPInputView.swift
```

**Testing Checkpoint 2:**
- [ ] Test keychain storage/retrieval
- [ ] Verify biometric authentication
- [ ] Test OTP input flow
- [ ] **USER TEST**: Create a test profile, save credentials, retrieve them

---

## Phase 3: Port Management & SSH Foundation (Week 2)

### 3.1 Port Manager
**Tasks:**
- Implement `PortManager` service
- Add port allocation/deallocation
- Create port availability checking

**Code to implement:**
```swift
// Services/PortManager.swift
```

### 3.2 SSH Tunnel Service (Basic)
**Tasks:**
- Set up SwiftNIO SSH dependency
- Create basic `SSHTunnelService` structure
- Implement connection establishment

**Code to implement:**
```swift
// Core/SSH/SSHTunnelService.swift
// Core/SSH/SSHTunnelConfiguration.swift
```

**Testing Checkpoint 3:**
- [ ] Unit test port allocation
- [ ] Test port conflict detection
- [ ] Verify SSH library integration
- [ ] **USER TEST**: Test SSH connection to bastion (may need VPN)

---

## Phase 4: VNC Client Integration (Week 3)

### 4.1 LibVNCClient Setup
**Tasks:**
- Add LibVNCClient to project
- Configure bridging header
- Implement basic VNCClient wrapper

**Code to implement:**
```swift
// Resources/VirtualControlRoom-Bridging-Header.h
// Core/VNC/VNCClient.swift
```

### 4.2 VNC Testing Interface
**Tasks:**
- Create simple test UI for VNC
- Implement direct VNC connection (no SSH)
- Add frame buffer display

**Code to implement:**
```swift
// UI/Views/VNCTestView.swift
// Core/VNC/VNCFrameBufferView.swift
```

**Testing Checkpoint 4:**
- [ ] Test VNC connection to local server
- [ ] Verify frame buffer updates
- [ ] Test keyboard/mouse input
- [ ] **USER TEST**: Connect to a test VNC server, verify display updates

---

## Phase 5: Connection Integration (Week 4)

### 5.1 Connection Manager
**Tasks:**
- Implement `ConnectionManager`
- Integrate SSH + VNC flow
- Add connection state management

**Code to implement:**
```swift
// Services/ConnectionManager.swift
// Core/VNC/VNCConnectionAdapter.swift
// Models/Connection.swift
```

### 5.2 Connection UI
**Tasks:**
- Create connection profile list
- Add connection status indicators
- Implement connection lifecycle UI

**Code to implement:**
```swift
// UI/Views/ConnectionListView.swift
// UI/Views/ConnectionDetailView.swift
// UI/ViewModels/ConnectionViewModel.swift
```

**Testing Checkpoint 5:**
- [ ] Test full connection flow (SSH → VNC)
- [ ] Verify state transitions
- [ ] Test error handling
- [ ] **USER TEST**: Create profile, connect through bastion to VNC server

---

## Phase 6: AR Window Rendering - Basic (Week 5)

### 6.1 Metal/RealityKit Setup
**Tasks:**
- Implement `VNCTextureProvider`
- Create basic AR window entity
- Set up texture streaming

**Code to implement:**
```swift
// Core/Rendering/VNCTextureProvider.swift
// Core/Rendering/ARWindowEntity.swift
```

### 6.2 Basic AR Window
**Tasks:**
- Create simple floating window
- Display VNC content in AR
- Add basic positioning

**Code to implement:**
```swift
// UI/Views/VNCWindowView.swift
// UI/Views/ARContainerView.swift
```

**Testing Checkpoint 6:**
- [ ] Test texture conversion
- [ ] Verify AR window appears
- [ ] Check VNC content displays
- [ ] **USER TEST**: Connect and see remote desktop in AR space

---

## Phase 7: Input Handling (Week 6)

### 7.1 Keyboard/Mouse Integration
**Tasks:**
- Capture Bluetooth keyboard input
- Implement mouse event handling
- Map inputs to VNC events

**Code to implement:**
```swift
// Services/InputManager.swift
// Extensions/VNCClient+Input.swift
```

### 7.2 Gesture Recognition
**Tasks:**
- Add tap-to-click
- Implement drag gestures
- Add pinch to zoom (optional)

**Code to implement:**
```swift
// UI/Gestures/VNCGestureHandlers.swift
```

**Testing Checkpoint 7:**
- [ ] Test keyboard input
- [ ] Verify mouse movements
- [ ] Test click/drag operations
- [ ] **USER TEST**: Control remote desktop with keyboard/mouse

---

## Phase 8: Multi-Window Support (Week 7)

### 8.1 Window Management
**Tasks:**
- Support multiple concurrent connections
- Implement window positioning system
- Add window focus management

**Code to implement:**
```swift
// Services/WindowManager.swift
// Models/WindowConfiguration.swift
```

### 8.2 Layout System
**Tasks:**
- Implement `LayoutManager`
- Add save/load layout functionality
- Create layout presets

**Code to implement:**
```swift
// Services/LayoutManager.swift
// UI/Views/LayoutManagerView.swift
```

**Testing Checkpoint 8:**
- [ ] Test multiple connections
- [ ] Verify window management
- [ ] Test layout save/load
- [ ] **USER TEST**: Open 3+ windows, arrange them, save layout

---

## Phase 9: Polish & Error Handling (Week 8)

### 9.1 Error Recovery
**Tasks:**
- Implement reconnection logic
- Add comprehensive error messages
- Create fallback mechanisms

**Code to implement:**
```swift
// Services/ErrorHandler.swift
// UI/Views/ErrorView.swift
```

### 9.2 Performance Optimization
**Tasks:**
- Profile and optimize rendering
- Implement frame rate limiting
- Add quality settings

**Code to implement:**
```swift
// Services/PerformanceMonitor.swift
// Settings/QualitySettings.swift
```

**Testing Checkpoint 9:**
- [ ] Test error scenarios
- [ ] Verify reconnection
- [ ] Check performance metrics
- [ ] **USER TEST**: Stress test with multiple windows

---

## Phase 10: Final UI & Settings (Week 9)

### 10.1 Settings Interface
**Tasks:**
- Create settings view
- Add connection preferences
- Implement app configuration

**Code to implement:**
```swift
// UI/Views/SettingsView.swift
// Models/AppSettings.swift
```

### 10.2 Onboarding
**Tasks:**
- Create first-launch experience
- Add connection profile wizard
- Build help system

**Code to implement:**
```swift
// UI/Views/OnboardingView.swift
// UI/Views/ConnectionWizardView.swift
```

**Testing Checkpoint 10:**
- [ ] Test all settings
- [ ] Verify onboarding flow
- [ ] Check help documentation
- [ ] **USER TEST**: Complete first-time setup flow

---

## Testing Strategy

### Unit Testing
- Each service class should have corresponding unit tests
- Aim for 80% code coverage on business logic
- Mock external dependencies

### Integration Testing
- Test service interactions
- Verify data flow between components
- Test error propagation

### User Acceptance Testing
- Each phase has specific user tests
- Document issues found
- Iterate based on feedback

### Performance Testing
- Monitor memory usage
- Check frame rates
- Test with varying network conditions

---

## Implementation Order for Each Component

When implementing each component, follow this pattern:

1. **Interface/Protocol Definition**
   ```swift
   protocol ServiceNameProtocol {
       // Define public interface
   }
   ```

2. **Mock Implementation**
   ```swift
   class MockServiceName: ServiceNameProtocol {
       // Simple implementation for testing
   }
   ```

3. **Real Implementation**
   ```swift
   class ServiceName: ServiceNameProtocol {
       // Actual implementation
   }
   ```

4. **Unit Tests**
   ```swift
   class ServiceNameTests: XCTestCase {
       // Test all public methods
   }
   ```

5. **Integration**
   - Wire into dependency injection
   - Update UI to use service
   - Test end-to-end flow

---

## Risk Mitigation Checkpoints

### After Phase 4 (VNC Client):
- **Decision Point**: Is LibVNCClient working well with visionOS?
- **Alternative**: Switch to pure Swift implementation if issues

### After Phase 6 (AR Rendering):
- **Decision Point**: Is performance acceptable?
- **Alternative**: Implement quality reduction or frame limiting

### After Phase 8 (Multi-Window):
- **Decision Point**: Can device handle multiple streams?
- **Alternative**: Implement connection limits or quality auto-adjust

---

## Daily Development Workflow

1. **Morning**: Review previous day's work
2. **Coding**: Implement 1-2 components
3. **Testing**: Write/run tests for new code
4. **Documentation**: Update code comments
5. **Commit**: Make atomic commits with clear messages
6. **End of Day**: Note any blockers or decisions needed

This modular approach ensures each component is properly tested before integration, reducing the risk of cascading failures and making debugging easier. 