import SwiftUI

struct VNCConnectionWindowView: View {
    let connectionID: UUID
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var showDebugInfo = false
    
    // Get the specific VNC client for this connection
    private var vncClient: LibVNCClient? {
        // Only return client if it exists and has a valid connection
        if connectionManager.activeConnections.contains(connectionID) ||
           connectionManager.getLifecycleState(for: connectionID) != .idle {
            return connectionManager.getVNCClient(for: connectionID)
        }
        return nil
    }
    
    var body: some View {
        Group {
            if let client = vncClient {
                VStack {
                    // Connection header with ID for identification
                    HStack {
                        Text("Connection: \(connectionID.uuidString.prefix(8))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        // Show connection state
                        switch client.connectionState {
                        case .connecting:
                            Label("Connecting", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        case .connected:
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        case .disconnected:
                            Label("Disconnected", systemImage: "xmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        case .failed(let error):
                            Label("Failed", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                        
                        // Debug toggle button
                        Button(action: { showDebugInfo.toggle() }) {
                            Image(systemName: showDebugInfo ? "eye.slash" : "eye")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 32) // Increased to avoid corner radius cropping
                    .padding(.top, 12)        // Slightly increased top padding
                    
                    // Debug info section
                    if showDebugInfo {
                        VNCDebugInfoView(client: client)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }
                    
                    // The actual VNC display
                    VNCSimpleWindowView(vncClient: client)
                        .onAppear {
                            print("🪟 VNCConnectionWindowView appeared for connection \(connectionID)")
                            // Notify both the client and connection manager
                            client.windowDidOpen()
                            connectionManager.windowDidOpen(for: connectionID)
                        }
                        .onDisappear {
                            print("🪟 VNCConnectionWindowView disappeared for connection \(connectionID)")
                            // Notify both the client and connection manager if they still exist
                            if connectionManager.hasClient(for: connectionID) {
                                let currentClient = connectionManager.getVNCClient(for: connectionID)
                                currentClient.windowDidClose()
                            }
                            connectionManager.windowDidClose(for: connectionID)
                        }
                }
            } else {
                // No client found for this connection ID
                VStack {
                    Image(systemName: "network.slash")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    Text("Connection Not Found")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Connection \(connectionID.uuidString.prefix(8)) is no longer available")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32) // Increased to avoid corner radius cropping
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .navigationTitle("VNC Connection")
    }
}

struct VNCDebugInfoView: View {
    @ObservedObject var client: LibVNCClient
    
    private func securityTypeName(_ type: Int) -> String {
        switch type {
        case 0: return "Invalid"
        case 1: return "None"
        case 2: return "VncAuth"
        case 5: return "RA2"
        case 6: return "RA2ne"
        case 16: return "Tight"
        case 17: return "Ultra"
        case 18: return "TLS"
        case 19: return "VeNCrypt"
        case 20: return "GTK-VNC SASL"
        case 21: return "MD5 hash authentication"
        case 22: return "Colin's authentication"
        case 30: return "Apple Remote Desktop"
        case 129: return "TightVNC Unix Login"
        case 130: return "TightVNC External"
        case 0xfffffffe: return "UltraMSLogonI"
        case 0xffffffff: return "UltraMSLogonII"
        default: return "Unknown (\(type))"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VNC Debug Information")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Divider()
            
            // Security Negotiation Section
            VStack(alignment: .leading, spacing: 4) {
                Text("Security Negotiation")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                if !client.serverSecurityTypes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Server offered:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        let serverTypes = client.serverSecurityTypes.map { "\($0) (\(securityTypeName($0)))" }.joined(separator: ", ")
                        Text(serverTypes)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                if !client.clientSecurityTypes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Client supports:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        let clientTypes = client.clientSecurityTypes.map { "\($0) (\(securityTypeName($0)))" }.joined(separator: ", ")
                        Text(clientTypes)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                if client.selectedSecurityType != 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("\(client.selectedSecurityType) (\(securityTypeName(client.selectedSecurityType)))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            
            // Server Error Message Section
            if let serverReason = client.serverReasonMessage, !serverReason.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server Message")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Text(serverReason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            
            // LibVNC Log Messages Section
            if !client.libVNCLogMessages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LibVNC Messages")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(client.libVNCLogMessages.suffix(10).enumerated()), id: \.offset) { _, message in
                                Text(message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
    }
}

#Preview {
    VNCConnectionWindowView(connectionID: UUID())
        .environmentObject(ConnectionManager.shared)
}