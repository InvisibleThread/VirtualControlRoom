import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Note: RTIInputSystemClient errors in console are a known visionOS Simulator issue
// when "Connect Hardware Keyboard" is enabled. To test with software keyboard:
// Simulator menu > I/O > Keyboard > uncheck "Connect Hardware Keyboard"
//
// Right-click implementation for visionOS:
// - Long press (0.5 seconds) triggers right-click
// - Regular tap triggers left-click
// - This approach works reliably since Control+click detection doesn't work in visionOS

enum MouseButton {
    case left, right, middle
}

/// VNCSimpleWindowView is the main display component for VNC connections.
/// It renders the remote desktop framebuffer and handles all user input including
/// keyboard events, mouse movements, and clicks (including right-click via long press).
///
/// Key features:
/// - Displays VNC framebuffer with proper aspect ratio
/// - Handles keyboard input through a hidden TextField
/// - Supports mouse input with left and right clicks
/// - Right-click implemented via long press (0.5 seconds)
/// - Tracks keyboard modifier states (Shift, Control, Option, Command)
/// - Automatically dismisses when connection is lost
/// - Handles coordinate transformation from touch to VNC space
///
/// Input handling approach:
/// - Keyboard: Hidden TextField captures focus and key events
/// - Mouse: DragGesture(minimumDistance: 0) for all mouse interactions
/// - Right-click: LongPressGesture for touch-friendly right-click
struct VNCSimpleWindowView: View {
    @ObservedObject var vncClient: LibVNCClient
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool  // Keyboard focus state
    @State private var keyboardProxy = ""  // Hidden TextField content (always empty)
    
    // Track modifier states for keyboard input
    // These are managed separately from mouse input
    @State private var shiftPressed = false
    @State private var controlPressed = false
    @State private var optionPressed = false
    @State private var commandPressed = false
    @State private var capsLockOn = false
    
    // Track gesture states for mouse input
    @State private var isLongPressing = false  // Prevents tap during long press
    @State private var longPressLocation = CGPoint.zero  // Location for right-click
    @State private var isDragging = false  // Track if we're currently dragging
    
    /// Ensures we always have a valid screen size for layout calculations.
    /// Falls back to 1920x1080 if VNC hasn't reported dimensions yet.
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
                .onKeyPress(phases: [.up]) { keyPress in
                    // Only handle key up phase for actual key presses
                    // Note: Modifier detection doesn't work reliably in visionOS
                    updateModifierStates(keyPress.modifiers)
                    let result = handleKeyEvent(keyPress)
                    keyboardProxy = ""
                    return result
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
                    if newValue {
                        print("✅ TextField focused - keyboard input enabled")
                    }
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
                        .gesture(
                            // Single unified gesture that handles all mouse interactions
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // Always update stored location
                                    longPressLocation = value.location
                                    
                                    let distance = value.translation.width * value.translation.width + value.translation.height * value.translation.height
                                    
                                    // This is a drag if we've moved more than 4 pixels
                                    if distance > 16 {  
                                        print("🔄 Dragging: location=\(value.location)")
                                        // Send mouse move with button held down
                                        handleMouseInput(at: value.location, in: geometry, pressed: true, button: .left)
                                    }
                                }
                                .onEnded { value in
                                    let distance = value.translation.width * value.translation.width + value.translation.height * value.translation.height
                                    
                                    if distance <= 16 && !isLongPressing {
                                        // This was a tap (short distance, no long press)
                                        isInputFocused = true
                                        print("🖱️ Tap -> Left click at: \(value.location)")
                                        handleMouseInput(at: value.location, in: geometry, pressed: true, button: .left)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            handleMouseInput(at: value.location, in: geometry, pressed: false, button: .left)
                                        }
                                    } else if distance > 16 {
                                        // This was a drag - send mouse up
                                        print("🔄 Drag ended at: \(value.location)")
                                        handleMouseInput(at: value.location, in: geometry, pressed: false, button: .left)
                                    }
                                }
                        )
                        .simultaneousGesture(
                            // Long press for right-click
                            LongPressGesture(minimumDuration: 0.5, maximumDistance: 4)
                                .onEnded { _ in
                                    if !isLongPressing {
                                        isLongPressing = true
                                        isInputFocused = true
                                        
                                        print("🖱️ Long press -> Right click at: \(longPressLocation)")
                                        handleMouseInput(at: longPressLocation, in: geometry, pressed: true, button: .right)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            handleMouseInput(at: longPressLocation, in: geometry, pressed: false, button: .right)
                                            isLongPressing = false
                                        }
                                    }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(validScreenSize, contentMode: .fit)
        .navigationTitle("VNC Display")
    }
    
    /// Handles mouse input by converting touch coordinates to VNC screen coordinates
    /// and sending the appropriate pointer event to the VNC server.
    ///
    /// - Parameters:
    ///   - location: The touch location in the view's coordinate space
    ///   - geometry: The GeometryProxy providing the view's dimensions
    ///   - pressed: Whether the mouse button is pressed (true) or released (false)
    ///   - button: Which mouse button (left, right, or middle)
    ///
    /// The method performs the following transformations:
    /// 1. Calculates the actual display area accounting for aspect ratio letterboxing
    /// 2. Validates the touch is within the VNC content (not in letterbox area)
    /// 3. Converts touch coordinates to relative position (0.0 to 1.0)
    /// 4. Scales to VNC screen coordinates
    /// 5. Sends pointer event with appropriate button mask
    ///
    /// VNC button masks: Left=1, Middle=2, Right=4
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
        print("📤 VNCSimpleWindowView: Sending pointer event x:\(vncX) y:\(vncY) mask:\(buttonMask)")
        print("🔍 VNCSimpleWindowView: vncClient = \(String(describing: vncClient))")
        vncClient.sendPointerEvent(x: vncX, y: vncY, buttonMask: buttonMask)
    }
    
    
    
    private func handleKeyEvent(_ keyPress: KeyPress) -> KeyPress.Result {
        // Update modifier states for key events
        updateModifierStates(keyPress.modifiers)
        
        // Handle key press and release
        if !keyPress.characters.isEmpty {
            if let char = keyPress.characters.first {
                // Special handling for Return/Enter characters
                if char == "\r" || char == "\n" {
                    vncClient.sendKeyEvent(keysym: 0xFF0D, down: true)  // Return key
                    vncClient.sendKeyEvent(keysym: 0xFF0D, down: false)
                } else {
                    // Handle modifier combinations - especially Shift for symbols and letters
                    let finalChar = applyModifiers(to: char, modifiers: keyPress.modifiers)
                    let keysym = characterToKeysym(finalChar)
                    vncClient.sendKeyEvent(keysym: keysym, down: true)
                    vncClient.sendKeyEvent(keysym: keysym, down: false)
                }
            }
        } else {
            // Special key handling for keys without characters
            let keysym = keyPressToKeysym(keyPress)
            if keysym != 0 {
                vncClient.sendKeyEvent(keysym: keysym, down: true)
                vncClient.sendKeyEvent(keysym: keysym, down: false)
            }
        }
        
        return .handled
    }
    
    private func updateModifierStates(_ modifiers: EventModifiers) {
        // Check and update Shift state
        let shiftNowPressed = modifiers.contains(.shift)
        if shiftNowPressed != shiftPressed {
            shiftPressed = shiftNowPressed
            vncClient.sendKeyEvent(keysym: 0xFFE1, down: shiftPressed) // Left Shift
        }
        
        // Check and update Control state
        let controlNowPressed = modifiers.contains(.control)
        if controlNowPressed != controlPressed {
            controlPressed = controlNowPressed
            vncClient.sendKeyEvent(keysym: 0xFFE3, down: controlPressed) // Left Control
        }
        
        // Check and update Option/Alt state
        let optionNowPressed = modifiers.contains(.option)
        if optionNowPressed != optionPressed {
            optionPressed = optionNowPressed
            vncClient.sendKeyEvent(keysym: 0xFFE9, down: optionPressed) // Left Alt
        }
        
        // Check and update Caps Lock state (toggle behavior)
        let capsLockNowPressed = modifiers.contains(.capsLock)
        if capsLockNowPressed && !capsLockOn {
            // Caps Lock key was pressed - toggle the state
            capsLockOn.toggle()
            vncClient.sendKeyEvent(keysym: 0xFFE5, down: true)  // Caps Lock down
            vncClient.sendKeyEvent(keysym: 0xFFE5, down: false) // Caps Lock up (toggle)
        }
        
        // Check and update Command/Meta state
        let commandNowPressed = modifiers.contains(.command)
        if commandNowPressed != commandPressed {
            commandPressed = commandNowPressed
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