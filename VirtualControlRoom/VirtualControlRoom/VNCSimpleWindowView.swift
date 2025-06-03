import SwiftUI

struct VNCSimpleWindowView: View {
    @ObservedObject var vncClient: LibVNCClient
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        ZStack {
            Color.black
            
            // VNC Display
            if let framebuffer = vncClient.framebuffer {
                GeometryReader { geometry in
                    Image(uiImage: UIImage(cgImage: framebuffer))
                        .resizable()
                        .aspectRatio(vncClient.screenSize, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .focused($isInputFocused)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            isInputFocused = true
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
                        .onKeyPress { keyPress in
                            return handleKeyInput(keyPress)
                        }
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
            vncClient.disconnect()
        }
        .onAppear {
            isInputFocused = true
            print("VNC Screen Size: \(vncClient.screenSize)")
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
    
    private func handleKeyInput(_ keyPress: KeyPress) -> KeyPress.Result {
        guard let key = keyPress.characters.first else { return .ignored }
        
        // Convert character to VNC keysym
        let keysym = characterToKeysym(key)
        
        // Send key down and key up events
        print("⌨️ VNC Key: '\(key)' -> keysym=0x\(String(keysym, radix: 16))")
        vncClient.sendKeyEvent(keysym: keysym, down: true)
        vncClient.sendKeyEvent(keysym: keysym, down: false)
        
        return .handled
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