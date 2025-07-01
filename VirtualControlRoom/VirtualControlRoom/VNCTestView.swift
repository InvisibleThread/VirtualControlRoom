import SwiftUI
import RealityKit
import RealityKitContent

struct VNCTestView: View {
    @EnvironmentObject var vncClient: LibVNCClient
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @State private var hostAddress = "192.168.86.54"
    @State private var port = "5900"
    @State private var username = ""
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPasswordPrompt = false
    @State private var promptedPassword = ""
    @State private var shouldDismissOnError = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                Text("VNC Proof of Concept")
                    .font(.title)
                    .padding(.top)
            
            
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
                    Label("Failed", systemImage: "exclamationmark.circle.fill")
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
                        
                        Button("Open Display Window") {
                            openWindow(id: "vnc-window")
                        }
                        .disabled(vncClient.connectionState != .connected)
                    }
                    .buttonStyle(.borderedProminent)
                    
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
                }
                .padding()
            }
            .alert("Connection Error", isPresented: $showError) {
                Button("Back to Connections") {
                    vncClient.disconnect()
                    dismiss()
                }
                Button("Try Again", role: .cancel) {
                    vncClient.disconnect()
                }
            } message: {
                Text(errorMessage)
            }
            .alert("VNC Password Required", isPresented: $showPasswordPrompt) {
                SecureField("Password", text: $promptedPassword)
                Button("Connect") {
                    Task {
                        await vncClient.retryWithPassword(promptedPassword)
                        promptedPassword = ""
                    }
                }
                Button("Cancel", role: .cancel) {
                    vncClient.disconnect()
                    promptedPassword = ""
                }
            } message: {
                Text("The VNC server requires a password to connect.")
            }
            .onChange(of: vncClient.passwordRequired) { _, newValue in
                if newValue {
                    showPasswordPrompt = true
                }
            }
            .onChange(of: vncClient.connectionState) { _, newState in
                print("🔄 VNCTestView: Connection state changed to: \(newState)")
                switch newState {
                case .failed(let error):
                    print("❌ VNCTestView: Connection failed with error: \(error)")
                    errorMessage = error
                    showError = true
                    shouldDismissOnError = true
                case .disconnected:
                    if shouldDismissOnError {
                        // Reset the flag
                        shouldDismissOnError = false
                    }
                default:
                    break
                }
            }
            .onChange(of: vncClient.lastError) { _, newError in
                if let error = newError, !error.isEmpty {
                    errorMessage = error
                    showError = true
                }
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
}
