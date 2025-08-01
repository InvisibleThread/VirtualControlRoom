import SwiftUI

struct SSHTestView: View {
    @StateObject private var sshService = SSHConnectionService()
    
    // Connection settings
    @State private var host = "192.168.86.54"
    @State private var port = "22"
    @State private var username = "user"
    @State private var password = ""
    @State private var privateKey = ""
    @State private var passphrase = ""
    @State private var selectedAuthMethod: AuthMethod = .password
    
    // Tunnel settings
    @State private var tunnelLocalPort = ""
    @State private var tunnelRemoteHost = "localhost"
    @State private var tunnelRemotePort = "5900"
    
    // UI state
    @State private var showingAdvanced = false
    @State private var autoScroll = true
    
    enum AuthMethod: String, CaseIterable {
        case password = "Password"
        case privateKey = "Private Key"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    connectionConfigSection
                    authenticationSection
                    tunnelConfigSection
                    controlSection
                    statusSection
                    testResultsSection
                }
                .padding()
            }
            .navigationTitle("SSH Connection Test")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var headerSection: some View {
        VStack {
            Text("Sprint 2: SSH Testing")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Test SSH connections independently before VNC integration")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var connectionConfigSection: some View {
        GroupBox("SSH Connection") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Host:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("hostname or IP", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                HStack {
                    Text("Port:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("22", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
                
                HStack {
                    Text("Username:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var authenticationSection: some View {
        GroupBox("Authentication") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Method", selection: $selectedAuthMethod) {
                    ForEach(AuthMethod.allCases, id: \.id) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                
                switch selectedAuthMethod {
                case .password:
                    HStack {
                        Text("Password:")
                            .frame(width: 80, alignment: .trailing)
                        SecureField("password", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                case .privateKey:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Private Key:")
                            Spacer()
                        }
                        TextEditor(text: $privateKey)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        
                        HStack {
                            Text("Passphrase:")
                                .frame(width: 80, alignment: .trailing)
                            SecureField("optional", text: $passphrase)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var tunnelConfigSection: some View {
        GroupBox("Tunnel Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Local Port:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("auto", text: $tunnelLocalPort)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                    Text("(empty for auto)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Remote Host:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("localhost", text: $tunnelRemoteHost)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                HStack {
                    Text("Remote Port:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("5900", text: $tunnelRemotePort)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var controlSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 15) {
                Button("Test Connection") {
                    Task {
                        await testConnection()
                    }
                }
                .disabled(sshService.connectionState == .connecting)
                
                Button("Test Auth") {
                    Task {
                        await testAuthentication()
                    }
                }
                .disabled(sshService.connectionState == .connecting || sshService.connectionState == .authenticating)
                
                Button("Test Tunnel") {
                    Task {
                        await testTunnel()
                    }
                }
                .disabled(sshService.connectionState == .connecting)
            }
            .buttonStyle(.borderedProminent)
            
            HStack(spacing: 15) {
                Button("Full Test") {
                    Task {
                        await runFullTest()
                    }
                }
                .disabled(sshService.connectionState == .connecting || sshService.connectionState == .authenticating)
                
                if sshService.connectionState == .connecting || sshService.connectionState == .authenticating {
                    Button("Cancel") {
                        sshService.cancelAndDisconnect()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("Disconnect") {
                        sshService.disconnect()
                    }
                    .disabled(sshService.connectionState == .disconnected)
                }
                
                Button("Clear Results") {
                    sshService.clearTestResults()
                }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var statusSection: some View {
        GroupBox("Status") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("State:")
                        .fontWeight(.medium)
                    
                    switch sshService.connectionState {
                    case .disconnected:
                        Label("Disconnected", systemImage: "circle")
                            .foregroundStyle(.secondary)
                    case .connecting:
                        Label("Connecting...", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                    case .connected:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .authenticating:
                        Label("Authenticating...", systemImage: "key")
                            .foregroundStyle(.blue)
                    case .authenticated:
                        Label("Authenticated", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    case .failed(let error):
                        Label("Failed", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                
                if !sshService.connectionInfo.isEmpty {
                    Text(sshService.connectionInfo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let error = sshService.lastError {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                // Active tunnels
                if !sshService.activeTunnels.isEmpty {
                    Divider()
                    Text("Active Tunnels:")
                        .fontWeight(.medium)
                    
                    ForEach(sshService.activeTunnels.indices, id: \.self) { index in
                        let tunnel = sshService.activeTunnels[index]
                        HStack {
                            Text("localhost:\(tunnel.localPort) → \(tunnel.remoteHost):\(tunnel.remotePort)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if tunnel.isActive {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var testResultsSection: some View {
        Group {
            if !sshService.testResults.isEmpty {
                GroupBox("Test Results") {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(sshService.testResults.indices, id: \.self) { index in
                                let result = sshService.testResults[index]
                                testResultRow(result)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
    }
    
    private func testResultRow(_ result: SSHTestResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(result.testType)".capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                if result.success {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                
                if let duration = result.duration {
                    Text(String(format: "%.2fs", duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("\(result.username)@\(result.host):\(result.port)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            if let error = result.error {
                Text("Error: \(error)")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            
            if let details = result.details {
                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
    
    // MARK: - Test Methods
    
    private func testConnection() async {
        guard let config = createSSHConfig() else { return }
        await sshService.testConnection(config: config)
    }
    
    private func testAuthentication() async {
        guard let config = createSSHConfig() else { return }
        await sshService.testAuthentication(config: config)
    }
    
    private func testTunnel() async {
        guard let sshConfig = createSSHConfig() else { return }
        guard let tunnelConfig = createTunnelConfig() else { return }
        
        await sshService.testTunnel(sshConfig: sshConfig, tunnelConfig: tunnelConfig)
    }
    
    private func runFullTest() async {
        guard let sshConfig = createSSHConfig() else { return }
        guard let tunnelConfig = createTunnelConfig() else { return }
        
        // Run tests in sequence
        await sshService.testConnection(config: sshConfig)
        
        if case .connected = sshService.connectionState {
            await sshService.testAuthentication(config: sshConfig)
            
            if case .authenticated = sshService.connectionState {
                await sshService.testTunnel(sshConfig: sshConfig, tunnelConfig: tunnelConfig)
            }
        }
    }
    
    private func createSSHConfig() -> SSHConnectionConfig? {
        guard !host.isEmpty, !username.isEmpty else { return nil }
        guard let portNum = Int(port), portNum > 0 && portNum <= 65535 else { return nil }
        
        let authMethod: SSHAuthMethod
        switch selectedAuthMethod {
        case .password:
            authMethod = .password(password)
        case .privateKey:
            authMethod = .privateKey(privateKey: privateKey, passphrase: passphrase.isEmpty ? nil : passphrase)
        }
        
        return SSHConnectionConfig(
            host: host,
            port: portNum,
            username: username,
            authMethod: authMethod
        )
    }
    
    private func createTunnelConfig() -> SSHTunnelConfig? {
        guard !tunnelRemoteHost.isEmpty else { return nil }
        guard let remotePort = Int(tunnelRemotePort), remotePort > 0 && remotePort <= 65535 else { return nil }
        
        let localPort = tunnelLocalPort.isEmpty ? nil : Int(tunnelLocalPort)
        
        return SSHTunnelConfig(
            localPort: localPort,
            remoteHost: tunnelRemoteHost,
            remotePort: remotePort,
            tunnelType: .local
        )
    }
}

extension SSHTestResult.TestType: CustomStringConvertible {
    var description: String {
        switch self {
        case .connection: return "connection"
        case .authentication: return "authentication"
        case .tunnel: return "tunnel"
        }
    }
}

#Preview {
    SSHTestView()
}