import SwiftUI
import RealityKit
import RealityKitContent

struct VNCTestView: View {
    @StateObject private var vncClient = VNCClient()
    @State private var hostAddress = "localhost"
    @State private var port = "5900"
    @State private var password = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
            Text("VNC Proof of Concept")
                .font(.largeTitle)
                .padding()
            
            // Connection Form
            GroupBox("Connection Settings") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Host:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("localhost", text: $hostAddress)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Port:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("5900", text: $port)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Password:")
                            .frame(width: 100, alignment: .trailing)
                        SecureField("Optional", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }
            .frame(maxWidth: 500)
            
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
            HStack(spacing: 20) {
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
            
            // Preview
            if let framebuffer = vncClient.framebuffer {
                GroupBox("Desktop Preview") {
                    Image(uiImage: UIImage(cgImage: framebuffer))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .border(Color.gray, width: 1)
                }
                .frame(maxWidth: 600)
            }
            
            Spacer()
            }
            .padding()
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
            password: password.isEmpty ? nil : password
        )
    }
}