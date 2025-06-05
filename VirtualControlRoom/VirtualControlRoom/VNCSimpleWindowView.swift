import SwiftUI

// Note: RTIInputSystemClient errors in console are a known visionOS Simulator issue
// when "Connect Hardware Keyboard" is enabled. To test with software keyboard:
// Simulator menu > I/O > Keyboard > uncheck "Connect Hardware Keyboard"
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
    
    var body: some View {
        ZStack {
            // Hidden TextField to capture keyboard focus
            TextField("", text: $keyboardProxy)
                .frame(width: 1, height: 1)
                .opacity(0.001)  // Nearly invisible but still focusable
                .focused($isInputFocused)
                .onKeyPress(phases: .up) { keyPress in
                    print("🔼 onKeyPress (.up phase): \(keyPress)")
                    return handleKeyEvent(keyPress)
                }
                .onSubmit {
                    // Handle Return/Enter key when TextField submits
                    print("⌨️ TextField onSubmit - sending Return key")
                    vncClient.sendKeyEvent(keysym: 0xFF0D, down: true)   // Return down
                    vncClient.sendKeyEvent(keysym: 0xFF0D, down: false)  // Return up
                    
                    // Clear the text field to prevent accumulation
                    keyboardProxy = ""
                    
                    // DON'T automatically regain focus as it causes onSubmit loop
                    // Instead, user can click to regain focus when needed
                    print("🔄 Return key sent, focus will be lost (click to regain)")
                }
                .onChange(of: isInputFocused) { _, newValue in
                    print("🎯 Focus changed: \(newValue)")
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
                            print("👆 Tap detected, requesting focus and sending mouse click")
                            
                            // Always try to regain focus first
                            isInputFocused = true
                            
                            // Clear any RTI interference by resetting the text field
                            keyboardProxy = ""
                            
                            handleMouseInput(at: location, in: geometry, pressed: true)
                            // Simulate quick press/release
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                handleMouseInput(at: location, in: geometry, pressed: false)
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    handleMouseInput(at: value.location, in: geometry, pressed: true)
                                }
                                .onEnded { value in
                                    handleMouseInput(at: value.location, in: geometry, pressed: false)
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
            idealWidth: min(1600, vncClient.screenSize.width * 0.2),
            minHeight: 600,
            idealHeight: min(900, vncClient.screenSize.height * 0.2)
        )
        .aspectRatio(vncClient.screenSize.width > 0 ? vncClient.screenSize : CGSize(width: 16, height: 9), contentMode: .fit)
        .navigationTitle("VNC Display")
        .onDisappear {
            // Clear any stuck modifiers
            clearAllModifiers()
            vncClient.disconnect()
        }
        .onAppear {
            isInputFocused = true
            print("VNC Screen Size: \(vncClient.screenSize)")
            // Reset all modifier states to ensure clean start
            print("🔄 Resetting modifier states on appear")
            shiftPressed = false
            controlPressed = false
            optionPressed = false
            commandPressed = false
        }
        .onChange(of: vncClient.screenSize) { _, newSize in
            print("VNC Screen Size changed to: \(newSize)")
        }
    }
    
    private func handleMouseInput(at location: CGPoint, in geometry: GeometryProxy, pressed: Bool) {
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
        
        // Send mouse event (button mask: 1 = left button)
        let buttonMask = pressed ? 1 : 0
        print("🖱️ VNC Mouse: (\(vncX), \(vncY)) button=\(buttonMask)")
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
                let baseKeysym = characterToBaseKeysym(char)
                
                // Special handling for Return/Enter characters
                if char == "\r" || char == "\n" {
                    print("⌨️ Simulating Return/Enter key: char='\(char)' keysym=0x\(String(0xFF0D, radix: 16))")
                    vncClient.sendKeyEvent(keysym: 0xFF0D, down: true)  // Return key
                    vncClient.sendKeyEvent(keysym: 0xFF0D, down: false)
                } else {
                    print("⌨️ Simulating key press: '\(char)' -> base keysym=0x\(String(baseKeysym, radix: 16)) modifiers=\(keyPress.modifiers)")
                    vncClient.sendKeyEvent(keysym: baseKeysym, down: true)
                    vncClient.sendKeyEvent(keysym: baseKeysym, down: false)
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
    
    // Convert character to base keysym (lowercase) - server handles shift state
    private func characterToBaseKeysym(_ char: Character) -> UInt32 {
        // For letters, always send lowercase
        if char.isLetter {
            return UInt32(char.lowercased().first?.asciiValue ?? 0)
        }
        
        // For numbers and special chars on number keys, send the base number
        switch char {
        case "!", "@", "#", "$", "%", "^", "&", "*", "(", ")":
            // Map shifted number row chars back to numbers
            let shiftedChars = "!@#$%^&*()"
            if let index = shiftedChars.firstIndex(of: char) {
                let number = shiftedChars.distance(from: shiftedChars.startIndex, to: index)
                if number == 9 { // ')' maps to '0'
                    return 0x30 // '0'
                } else {
                    return UInt32(0x31 + number) // '1', '2', ..., '9'
                }
            }
        default:
            break
        }
        
        // For other characters, use standard mapping
        return characterToKeysym(char)
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
            if ascii >= 32 && ascii <= 126 {
                return UInt32(ascii)
            }
            return UInt32(ascii)
        }
    }
}