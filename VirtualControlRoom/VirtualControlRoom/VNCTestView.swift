import SwiftUI
import RealityKit
import RealityKitContent

struct VNCTestView: View {
    @StateObject private var vncClient = RoyalVNCClient()  // Using RoyalVNCClient instead of mock
    @State private var hostAddress = "localhost"
    @State private var port = "5900"
    @State private var username = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                Text("VNC Proof of Concept")
                    .font(.title)
                    .padding(.top)
            
                // DEBUG: Show current state (Compact)
                VStack {
                    Text("DEBUG STATE:")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Text("FB: \(vncClient.framebuffer != nil ? "\(vncClient.framebuffer!.width)x\(vncClient.framebuffer!.height)" : "NIL")")
                        .font(.caption2)
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .onReceive(vncClient.objectWillChange) {
                    print("UI DEBUG: VNCClient objectWillChange triggered")
                }
            
                // Connection Form (Compact)
                GroupBox("Connection Settings") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Host:")
                                .frame(width: 70, alignment: .trailing)
                            TextField("localhost", text: $hostAddress)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("Port:")
                                .frame(width: 70, alignment: .trailing)
                            TextField("5900", text: $port)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("User:")
                                .frame(width: 70, alignment: .trailing)
                            TextField("Username", text: $username)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            Text("Pass:")
                                .frame(width: 70, alignment: .trailing)
                            SecureField("Optional", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: 400)
            
            // Connection Status
            HStack {
                switch vncClient.connectionState {
                case .disconnected:
                    Label("Disconnected", systemImage: "circle.fill")
                        .foregroundColor(.gray)
                case .connecting:
                    Label("Connecting...", systemImage: "circle.fill")
                        .foregroundColor(.orange)
                case .connected:
                    Label("Connected", systemImage: "circle.fill")
                        .foregroundColor(.green)
                case .failed(let errorMessage):
                    Label("Failed: \(errorMessage)", systemImage: "circle.fill")
                        .foregroundColor(.red)
                }
            }
            
                // Control Buttons
                VStack(spacing: 10) {
                    HStack(spacing: 15) {
                        Button("Connect") {
                            Task {
                                await connectToVNC()
                            }
                        }
                        .disabled(vncClient.connectionState == .connecting || vncClient.connectionState == .connected)
                        
                        Button("Disconnect") {
                            vncClient.disconnect()
                        }
                        .disabled(vncClient.connectionState == .disconnected || vncClient.connectionState == .connecting)
                        
                        NavigationLink("Show in AR") {
                            VNCSpatialView(vncClient: vncClient)
                        }
                        .disabled(vncClient.connectionState != .connected)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    // DEBUG: Manual test buttons
                    HStack(spacing: 15) {
                        Button("Red") {
                            createManualTestPattern()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Blue") {
                            createBlueTestPattern()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Clear") {
                            vncClient.clearFramebuffer()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            
                // Preview - Always show this section
                GroupBox("Desktop Preview") {
                    VStack {
                        if let framebuffer = vncClient.framebuffer {
                            Text("Resolution: \(Int(framebuffer.width)) × \(Int(framebuffer.height))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Convert CGImage to UIImage for better visionOS compatibility
                            Image(uiImage: UIImage(cgImage: framebuffer))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 500, maxHeight: 300)
                                .border(Color.green, width: 2) // Green border to make it obvious
                                .clipped()
                            
                            Text("SUCCESS: Image displayed!")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else if vncClient.connectionState == .connected {
                            Text("Waiting for framebuffer data...")
                                .foregroundColor(.secondary)
                                .frame(height: 80)
                            
                            Text("Connected but no framebuffer yet")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        } else {
                            Text("Press 'Red' button to test or Connect to VNC")
                                .foregroundColor(.secondary)
                                .frame(height: 80)
                            
                            Text("No framebuffer")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: 550, minHeight: 120)
                }
                .onAppear {
                    print("UI DEBUG: Preview GroupBox appeared")
                }
                }
                .padding()
            }
            .alert("Connection Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func connectToVNC() async {
        guard let portNumber = Int(port) else {
            errorMessage = "Invalid port number"
            showError = true
            return
        }
        
        await vncClient.connect(
            host: hostAddress,
            port: portNumber,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password
        )
    }
    
    private func createManualTestPattern() {
        print("UI DEBUG: Creating manual red test pattern")
        
        let size = CGSize(width: 400, height: 300)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(data: nil,
                                    width: Int(size.width),
                                    height: Int(size.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: Int(size.width) * 4,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("UI DEBUG: Failed to create manual test pattern context")
            return
        }
        
        // Red background
        context.setFillColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        context.fill(CGRect(origin: .zero, size: size))
        
        // White text area
        context.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        context.fill(CGRect(x: 50, y: 120, width: 300, height: 60))
        
        guard let testImage = context.makeImage() else {
            print("UI DEBUG: Failed to create manual test image")
            return
        }
        
        print("UI DEBUG: Setting manual test pattern")
        vncClient.setTestFramebuffer(testImage)
    }
    
    private func createBlueTestPattern() {
        print("UI DEBUG: Creating manual blue test pattern")
        
        let size = CGSize(width: 400, height: 300)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(data: nil,
                                    width: Int(size.width),
                                    height: Int(size.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: Int(size.width) * 4,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return
        }
        
        // Blue background
        context.setFillColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0)
        context.fill(CGRect(origin: .zero, size: size))
        
        // Yellow text area
        context.setFillColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 50, y: 120, width: 300, height: 60))
        
        if let testImage = context.makeImage() {
            print("UI DEBUG: Setting blue test pattern")
            vncClient.setTestFramebuffer(testImage)
        }
    }
}