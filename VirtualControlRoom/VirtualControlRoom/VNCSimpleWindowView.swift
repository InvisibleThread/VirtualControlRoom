import SwiftUI

// Note: RTIInputSystemClient errors in console are a known visionOS Simulator issue
// when "Connect Hardware Keyboard" is enabled. To test with software keyboard:
// Simulator menu > I/O > Keyboard > uncheck "Connect Hardware Keyboard"

enum MouseButton {
    case left, right, middle
}

struct VNCSimpleWindowView: View {
    @ObservedObject var vncClient: LibVNCClient
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool
    @State private var keyboardProxy = ""
    
    // Track modifier states
    @State private var shiftPressed = false
    @State private var controlPressed = false
    @State private var optionPressed = false
    @State private var commandPressed = false
    @State private var capsLockOn = false
    
    // Computed property for safe screen size
    private var validScreenSize: CGSize {
        let size = vncClient.screenSize
        if size.width > 0 && size.height > 0 && size.width.isFinite && size.height.isFinite {
            return size
        }
        return CGSize(width: 1920, height: 1080) // Default 16:9 ratio
    }
    
    var body: some View {
        Group {
            // Monitor connection state and dismiss window if disconnected
            if case .disconnected = vncClient.connectionState {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        print("🪟 VNC: Disconnected state detected - dismissing window")
                        dismiss()
                    }
            } else {
                actualVNCView
            }
        }
        .onDisappear {
            // Clear any stuck modifiers
            clearAllModifiers()
            // Note: Window lifecycle is now managed by parent VNCConnectionWindowView
        }
        .onAppear {
            // Reset input state when view appears
            isInputFocused = true
            print("VNC Screen Size: \(vncClient.screenSize)")
            // Reset all modifier states to ensure clean start
            print("🔄 Resetting modifier states on appear")
            shiftPressed = false
            controlPressed = false
            optionPressed = false
            commandPressed = false
            capsLockOn = false
        }
        .onChange(of: vncClient.connectionState) { _, newState in
            // Note: Window dismissal is now handled by VNCWindowView.onDisappear
            // to avoid circular dependency (disconnect -> dismiss -> disconnect)
            if case .disconnected = newState {
                print("🪟 VNC: Connection state changed to disconnected")
            }
        }
        .onChange(of: vncClient.screenSize) { _, newSize in
            print("VNC Screen Size changed to: \(newSize)")
        }
    }
    
    private var actualVNCView: some View {
        ZStack {
            // Hidden TextField to capture keyboard focus
            TextField("", text: $keyboardProxy)
                .frame(width: 1, height: 1)
                .opacity(0.001)  // Nearly invisible but still focusable
                .focused($isInputFocused)
                .autocorrectionDisabled(true)  // Disable autocorrection
                .textInputAutocapitalization(.never)  // Disable auto-capitalization
                .keyboardType(.asciiCapable)  // Use basic ASCII keyboard
                .textContentType(.none)  // No content type suggestions
                .disableAutocorrection(true)  // Additional autocorrection disable
                .onKeyPress(phases: .up) { keyPress in
                    print("🔼 onKeyPress (.up phase): \(keyPress)")
                    
                    // Immediately clear any text that might accumulate
                    keyboardProxy = ""
                    
                    return handleKeyEvent(keyPress)
                }
                .onSubmit {
                    // Handle Return/Enter key when TextField submits
                    print("⌨️ TextField onSubmit - sending Return key")
                    vncClient.sendKeyEvent(keysym: 0xFF0D, down: true)   // Return down
                    vncClient.sendKeyEvent(keysym: 0xFF0D, down: false)  // Return up
                    
                    // Clear the text field to prevent accumulation
                    keyboardProxy = ""
                    
                    // Maintain focus to keep keyboard input active
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isInputFocused = true
                    }
                    print("🔄 Return key sent, maintaining focus for continued typing")
                }
                .onChange(of: isInputFocused) { _, newValue in
                    print("🎯 Focus changed: \(newValue)")
                }
                .onChange(of: keyboardProxy) { _, newValue in
                    // Aggressively prevent text accumulation
                    if !newValue.isEmpty {
                        print("🚫 Clearing accumulated text: '\(newValue)'")
                        DispatchQueue.main.async {
                            keyboardProxy = ""
                        }
                    }
                }
            
            Color.black
            
            // VNC Display
            if let framebuffer = vncClient.framebuffer {
                GeometryReader { geometry in
                    Image(uiImage: UIImage(cgImage: framebuffer))
                        .resizable()
                        .aspectRatio(vncClient.screenSize, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            print("👆 Left click detected, requesting focus and sending mouse click")
                            
                            // Always try to regain focus first
                            isInputFocused = true
                            
                            // Clear any RTI interference by resetting the text field
                            keyboardProxy = ""
                            
                            handleMouseInput(at: location, in: geometry, pressed: true, button: .left)
                            // Simulate quick press/release
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                handleMouseInput(at: location, in: geometry, pressed: false, button: .left)
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    handleMouseInput(at: value.location, in: geometry, pressed: true, button: .left)
                                }
                                .onEnded { value in
                                    handleMouseInput(at: value.location, in: geometry, pressed: false, button: .left)
                                }
                        )
                }
            } else {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text("Waiting for VNC content...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(
            minWidth: 800,
            idealWidth: validScreenSize.width > 0 ? min(1600, validScreenSize.width * 0.4) : 1200,
            minHeight: 600,
            idealHeight: validScreenSize.height > 0 ? min(900, validScreenSize.height * 0.4) : 800
        )
        .aspectRatio(validScreenSize, contentMode: .fit)
        .navigationTitle("VNC Display")
    }
    
    private func handleMouseInput(at location: CGPoint, in geometry: GeometryProxy, pressed: Bool, button: MouseButton = .left) {
        guard vncClient.screenSize.width > 0 && vncClient.screenSize.height > 0 else { 
            return 
        }
        
        // Since we're using .aspectRatio(.fit), calculate the actual display area
        let imageAspectRatio = vncClient.screenSize.width / vncClient.screenSize.height
        let containerAspectRatio = geometry.size.width / geometry.size.height
        
        let displayArea: CGRect
        if imageAspectRatio > containerAspectRatio {
            // Image is wider than container, letterboxed top/bottom
            let displayHeight = geometry.size.width / imageAspectRatio
            let yOffset = (geometry.size.height - displayHeight) / 2
            displayArea = CGRect(x: 0, y: yOffset, width: geometry.size.width, height: displayHeight)
        } else {
            // Image is taller than container, letterboxed left/right
            let displayWidth = geometry.size.height * imageAspectRatio
            let xOffset = (geometry.size.width - displayWidth) / 2
            displayArea = CGRect(x: xOffset, y: 0, width: displayWidth, height: geometry.size.height)
        }
        
        // Check if click is within the image area
        guard displayArea.contains(location) else { 
            return 
        }
        
        // Convert to relative coordinates within the image
        let relativeX = (location.x - displayArea.origin.x) / displayArea.width
        let relativeY = (location.y - displayArea.origin.y) / displayArea.height
        
        // Convert to VNC coordinates
        let vncX = Int(relativeX * vncClient.screenSize.width)
        let vncY = Int(relativeY * vncClient.screenSize.height)
        
        // Send mouse event with proper button mask
        // VNC button masks: Left=1, Middle=2, Right=4
        let buttonValue = button == .left ? 1 : (button == .right ? 4 : 2)
        let buttonMask = pressed ? buttonValue : 0
        print("🖱️ VNC Mouse: (\(vncX), \(vncY)) button=\(button) mask=\(buttonMask)")
        vncClient.sendPointerEvent(x: vncX, y: vncY, buttonMask: buttonMask)
    }
    
    
    
    private func handleKeyEvent(_ keyPress: KeyPress) -> KeyPress.Result {
        print("⌨️ HANDLING KEY EVENT - characters: '\(keyPress.characters)' key: \(keyPress.key) modifiers: \(keyPress.modifiers)")
        
        // Since visionOS only gives us key-up events, simulate the full key press sequence:
        // 1. Update modifiers (send modifier down events if needed)
        // 2. Send key down 
        // 3. Send key up
        // 4. Update modifiers again (send modifier up events if needed)
        
        // Step 1: Update modifier states for key down
        updateModifierStates(keyPress.modifiers)
        
        // Step 2 & 3: Send the actual key press and release
        if !keyPress.characters.isEmpty {
            // Check if this is a special character that should be handled as a special key
            if let char = keyPress.characters.first {
                // Special handling for Return/Enter characters
                if char == "\r" || char == "\n" {
                    print("⌨️ Simulating Return/Enter key: char='\(char)' keysym=0x\(String(0xFF0D, radix: 16))")
                    vncClient.sendKeyEvent(keysym: 0xFF0D, down: true)  // Return key
                    vncClient.sendKeyEvent(keysym: 0xFF0D, down: false)
                } else {
                    // Handle modifier combinations - especially Shift for symbols and letters
                    let finalChar = applyModifiers(to: char, modifiers: keyPress.modifiers)
                    
                    let keysym = characterToKeysym(finalChar)
                    print("⌨️ Simulating key press: '\(char)' -> final='\(finalChar)' keysym=0x\(String(keysym, radix: 16)) modifiers=\(keyPress.modifiers)")
                    vncClient.sendKeyEvent(keysym: keysym, down: true)
                    vncClient.sendKeyEvent(keysym: keysym, down: false)
                }
            }
        } else {
            // Special key handling for keys without characters
            let keysym = keyPressToKeysym(keyPress)
            if keysym != 0 {
                print("⌨️ Simulating special key: \(keyPress.key) keysym=0x\(String(keysym, radix: 16))")
                vncClient.sendKeyEvent(keysym: keysym, down: true)
                vncClient.sendKeyEvent(keysym: keysym, down: false)
            } else {
                print("⚠️ Unknown special key: \(keyPress.key) - no keysym mapping found")
            }
        }
        
        // Step 4: Update modifier states for key up (this will handle modifier releases)
        // For now, we'll track when modifiers should be released based on subsequent key events
        
        return .handled
    }
    
    private func updateModifierStates(_ modifiers: EventModifiers) {
        print("🎛️ updateModifierStates called with: \(modifiers)")
        print("🎛️ Current states - shift:\(shiftPressed) ctrl:\(controlPressed) opt:\(optionPressed) cmd:\(commandPressed)")
        
        // Check and update Shift state
        let shiftNowPressed = modifiers.contains(.shift)
        print("🎛️ Shift comparison: now=\(shiftNowPressed) vs current=\(shiftPressed)")
        if shiftNowPressed != shiftPressed {
            shiftPressed = shiftNowPressed
            print("⌨️ Modifier: Shift \(shiftPressed ? "down" : "up")")
            vncClient.sendKeyEvent(keysym: 0xFFE1, down: shiftPressed) // Left Shift
        }
        
        // Check and update Control state
        let controlNowPressed = modifiers.contains(.control)
        if controlNowPressed != controlPressed {
            controlPressed = controlNowPressed
            print("⌨️ Modifier: Control \(controlPressed ? "down" : "up")")
            vncClient.sendKeyEvent(keysym: 0xFFE3, down: controlPressed) // Left Control
        }
        
        // Check and update Option/Alt state
        let optionNowPressed = modifiers.contains(.option)
        if optionNowPressed != optionPressed {
            optionPressed = optionNowPressed
            print("⌨️ Modifier: Alt/Option \(optionPressed ? "down" : "up")")
            vncClient.sendKeyEvent(keysym: 0xFFE9, down: optionPressed) // Left Alt
        }
        
        // Check and update Caps Lock state (toggle behavior)
        let capsLockNowPressed = modifiers.contains(.capsLock)
        if capsLockNowPressed && !capsLockOn {
            // Caps Lock key was pressed - toggle the state
            capsLockOn.toggle()
            print("⌨️ Modifier: Caps Lock toggled to \(capsLockOn ? "ON" : "OFF")")
            vncClient.sendKeyEvent(keysym: 0xFFE5, down: true)  // Caps Lock down
            vncClient.sendKeyEvent(keysym: 0xFFE5, down: false) // Caps Lock up (toggle)
        }
        
        // Check and update Command/Meta state
        let commandNowPressed = modifiers.contains(.command)
        if commandNowPressed != commandPressed {
            commandPressed = commandNowPressed
            print("⌨️ Modifier: Command/Meta \(commandPressed ? "down" : "up")")
            vncClient.sendKeyEvent(keysym: 0xFFE7, down: commandPressed) // Left Meta
        }
    }
    
    private func clearAllModifiers() {
        // Send release events for any pressed modifiers
        if shiftPressed {
            vncClient.sendKeyEvent(keysym: 0xFFE1, down: false)
            shiftPressed = false
        }
        if controlPressed {
            vncClient.sendKeyEvent(keysym: 0xFFE3, down: false)
            controlPressed = false
        }
        if optionPressed {
            vncClient.sendKeyEvent(keysym: 0xFFE9, down: false)
            optionPressed = false
        }
        if commandPressed {
            vncClient.sendKeyEvent(keysym: 0xFFE7, down: false)
            commandPressed = false
        }
    }
    
    
    private func keyPressToKeysym(_ keyPress: KeyPress) -> UInt32 {
        // Handle special keys first
        switch keyPress.key {
        case .delete:
            return 0xFF08  // Backspace
        case .deleteForward:
            return 0xFFFF  // Delete
        case .return:
            return 0xFF0D  // Return
        case .tab:
            return 0xFF09  // Tab
        case .space:
            return 0x0020  // Space
        case .escape:
            return 0xFF1B  // Escape
        case .upArrow:
            return 0xFF52  // Up
        case .downArrow:
            return 0xFF54  // Down
        case .leftArrow:
            return 0xFF51  // Left
        case .rightArrow:
            return 0xFF53  // Right
        case .home:
            return 0xFF50  // Home
        case .end:
            return 0xFF57  // End
        case .pageUp:
            return 0xFF55  // Page Up
        case .pageDown:
            return 0xFF56  // Page Down
        default:
            // For regular characters, use the actual character value (which includes shift modifications)
            if let char = keyPress.characters.first {
                // The character already reflects the modifier state (e.g., Shift+1 = "!")
                return characterToKeysym(char)
            }
            return 0
        }
    }
    
    private func applyModifiers(to char: Character, modifiers: EventModifiers) -> Character {
        // Handle Caps Lock for letters
        if modifiers.contains(.capsLock) {
            if char.isLetter {
                // Caps Lock inverts the case
                return capsLockOn ? char.uppercased().first ?? char : char.lowercased().first ?? char
            }
        }
        
        // If Shift is pressed, apply shift transformations
        if modifiers.contains(.shift) {
            // Handle letters - convert to uppercase (unless Caps Lock is on, then invert)
            if char.isLetter {
                if capsLockOn {
                    // Caps Lock is on, so Shift should make it lowercase
                    return char.lowercased().first ?? char
                } else {
                    // Normal shift behavior - uppercase
                    return char.uppercased().first ?? char
                }
            }
            
            // Handle numbers and symbols with Shift
            switch char {
            case "1": return "!"
            case "2": return "@"
            case "3": return "#"
            case "4": return "$"
            case "5": return "%"
            case "6": return "^"
            case "7": return "&"
            case "8": return "*"
            case "9": return "("
            case "0": return ")"
            case "-": return "_"
            case "=": return "+"
            case "[": return "{"
            case "]": return "}"
            case "\\": return "|"
            case ";": return ":"
            case "'": return "\""
            case ",": return "<"
            case ".": return ">"
            case "/": return "?"
            case "`": return "~"
            default:
                return char
            }
        }
        
        // Just Caps Lock (no Shift) - uppercase letters
        if capsLockOn && char.isLetter {
            return char.uppercased().first ?? char
        }
        
        // No modifiers or modifiers we don't handle - return original character
        return char
    }
    
    private func characterToKeysym(_ char: Character) -> UInt32 {
        let ascii = char.asciiValue ?? 0
        
        // Basic ASCII mapping to VNC keysyms
        switch char {
        case "\r", "\n":
            return 0xFF0D // Return key
        case "\t":
            return 0xFF09 // Tab key
        case "\u{8}":
            return 0xFF08 // Backspace
        case " ":
            return 0x0020 // Space
        default:
            // For most printable ASCII characters, keysym equals ASCII value
            // This preserves case (uppercase vs lowercase) and special characters
            if ascii >= 32 && ascii <= 126 {
                return UInt32(ascii)
            }
            return UInt32(ascii)
        }
    }
}