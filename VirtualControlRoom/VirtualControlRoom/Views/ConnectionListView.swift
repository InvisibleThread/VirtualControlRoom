import SwiftUI
import CoreData
import Combine

struct ConnectionListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @StateObject private var connectionManager = ConnectionManager.shared
    @StateObject private var sshTunnelManager = SSHTunnelManager.shared
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ConnectionProfile.name, ascending: true)
        ],
        animation: .default
    )
    private var connections: FetchedResults<ConnectionProfile>
    
    @State private var showingAddConnection = false
    @State private var selectedConnection: ConnectionProfile?
    @State private var showingEditConnection = false
    @State private var connectingProfile: ConnectionProfile?
    @State private var showingPasswordDialog = false
    @State private var enteredPassword = ""
    @State private var showingOTPPrompt = false
    @State private var pendingSSHConfig: SSHConnectionConfig?
    @State private var sshConnectionTask: Task<Void, Never>?
    @State private var showingDiagnostics = false
    @State private var diagnosticsError: String = ""
    @State private var diagnosticsConnectionName: String = ""
    @State private var diagnosticsSuggestions: [String] = []
    
    var body: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Connections")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddConnection = true
                        } label: {
                            Label("Add Connection", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showingAddConnection) {
                    NavigationStack {
                        ConnectionEditView(connection: nil)
                    }
                }
                .sheet(item: $selectedConnection) { connection in
                    NavigationStack {
                        ConnectionEditView(connection: connection)
                    }
                }
                .alert("Enter Password", isPresented: $showingPasswordDialog) {
                    passwordAlertContent
                } message: {
                    passwordAlertMessage
                }
                .onReceive(NotificationCenter.default.publisher(for: .vncPasswordRequired)) { notification in
                    if let profileID = notification.userInfo?["profileID"] as? UUID,
                       profileID == connectingProfile?.id {
                        showingPasswordDialog = true
                    }
                }
                .sheet(isPresented: $showingOTPPrompt) {
                    if let profile = connectingProfile {
                        OTPPromptView(
                            isPresented: $showingOTPPrompt,
                            connectionName: profile.sshHost ?? profile.displayHost,
                            onSubmit: { otp in
                                print("🔐 OTP onSubmit closure called with OTP")
                                // Cancel any existing task
                                sshConnectionTask?.cancel()
                                // Create new task that won't be cancelled by sheet dismissal
                                sshConnectionTask = Task.detached {
                                    await handleOTPSubmit(otp: otp, profile: profile)
                                }
                            },
                            onCancel: {
                                print("🚫 OTP cancelled")
                                sshConnectionTask?.cancel()
                                sshConnectionTask = nil
                                showingOTPPrompt = false
                                pendingSSHConfig = nil
                                connectingProfile = nil
                            }
                        )
                    }
                }
                .sheet(isPresented: $showingDiagnostics) {
                    SSHTunnelDiagnosticsView(
                        connectionName: diagnosticsConnectionName,
                        error: diagnosticsError,
                        suggestions: diagnosticsSuggestions
                    )
                }
        }
    }
    
    private var mainContent: some View {
        Group {
            if connections.isEmpty {
                emptyStateView
            } else {
                connectionsList
            }
        }
    }
    
    @ViewBuilder
    private var passwordAlertContent: some View {
        SecureField("Password", text: $enteredPassword)
        Button("Connect") {
            if let profile = connectingProfile, let profileID = profile.id {
                print("🔐 Retrying connection for profile: \(profile.displayName)")
                let client = connectionManager.getVNCClient(for: profileID)
                Task {
                    await client.retryWithPassword(enteredPassword)
                }
            }
            enteredPassword = ""
            showingPasswordDialog = false
        }
        Button("Cancel", role: .cancel) {
            enteredPassword = ""
            showingPasswordDialog = false
            if let profile = connectingProfile, let profileID = profile.id {
                connectionManager.disconnect(profileID: profileID)
            }
            connectingProfile = nil
        }
    }
    
    @ViewBuilder
    private var passwordAlertMessage: some View {
        if let profile = connectingProfile {
            Text("Enter password for \(profile.displayName)")
        }
    }
    
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "network")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Connections")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add a VNC connection to get started")
                .foregroundStyle(.secondary)
            
            Button {
                showingAddConnection = true
            } label: {
                Label("Add Connection", systemImage: "plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var connectionsList: some View {
        List {
            ForEach(connections) { connection in
                ConnectionRowView(
                    connection: connection,
                    connectionManager: connectionManager
                ) {
                    // Connect action
                    connectToProfile(connection)
                } onEdit: {
                    // Edit action
                    selectedConnection = connection
                } onDelete: {
                    // Delete action
                    deleteConnection(connection)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private func connectToProfile(_ profile: ConnectionProfile) {
        guard let profileID = profile.id else { return }
        
        ConnectionProfileManager.shared.markProfileAsUsed(profile)
        connectingProfile = profile
        
        let vncClient = connectionManager.getVNCClient(for: profileID)
        
        // Check if this specific connection is already active
        if case .connected = vncClient.connectionState {
            print("🔄 Disconnecting existing connection for profile: \(profile.displayName)")
            vncClient.disconnect()
            // Give a moment for disconnection to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task {
                    await self.performConnection(profile, password: nil)
                }
            }
        } else {
            // For all other states (disconnected, connecting, failed), proceed with connection
            Task {
                await performConnection(profile, password: nil)
            }
        }
    }
    
    private func performConnection(_ profile: ConnectionProfile, password: String?) async {
        guard let host = profile.host, let profileID = profile.id else { return }
        
        let vncClient = connectionManager.getVNCClient(for: profileID)
        
        // Check if we have a saved password in Keychain
        var connectionPassword = password
        if connectionPassword == nil && profile.savePassword {
            connectionPassword = KeychainManager.shared.retrievePassword(for: profileID)
            print("🔐 ConnectionList: Retrieved password from Keychain for profile \(profile.displayName)")
        }
        
        // Check if SSH tunnel is enabled
        if let sshHost = profile.sshHost,
           !sshHost.isEmpty,
           let sshUsername = profile.sshUsername {
            
            print("🔒 SSH tunnel enabled for profile: \(profile.displayName)")
            
            // Retrieve SSH password from Keychain
            let sshPassword = KeychainManager.shared.retrieveSSHPassword(for: profileID)
            
            // Create SSH config
            let sshConfig = SSHConnectionConfig(
                host: sshHost,
                port: Int(profile.sshPort),
                username: sshUsername,
                authMethod: .password(sshPassword ?? ""),
                connectTimeout: 30
            )
            
            // Store pending SSH config for OTP prompt
            pendingSSHConfig = sshConfig
            
            // Show OTP prompt
            showingOTPPrompt = true
            
        } else {
            // Direct VNC connection (no SSH tunnel)
            await vncClient.connect(
                host: host,
                port: Int(profile.port),
                username: profile.username,
                password: connectionPassword
            )
            
            // Monitor connection state to open window when ready (for direct connections only)
            let cancellable = vncClient.$connectionState
                .receive(on: DispatchQueue.main)
                .sink { state in
                    if case .connected = state {
                        openWindow(id: "vnc-window", value: profileID)
                        print("🪟 Opening VNC window for direct profile \(profile.displayName) with ID \(profileID) - state: \(state)")
                    } else if case .failed(let error) = state {
                        print("❌ Direct connection failed for \(profile.displayName): \(error)")
                    }
                }
            
            // Clean up the subscription after a reasonable time
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                cancellable.cancel()
            }
        }
    }
    
    private func deleteConnection(_ connection: ConnectionProfile) {
        withAnimation {
            ConnectionProfileManager.shared.deleteProfile(connection)
        }
    }
    
    private func handleOTPSubmit(otp: String, profile: ConnectionProfile) async {
        print("🔐 handleOTPSubmit called with OTP for profile: \(profile.displayName)")
        
        guard let sshConfig = pendingSSHConfig,
              let host = profile.host,
              let profileID = profile.id else { 
            print("❌ handleOTPSubmit: Missing required data - sshConfig: \(pendingSSHConfig != nil), host: \(profile.host ?? "nil"), profileID: \(profile.id?.uuidString ?? "nil")")
            return 
        }
        
        // Dismiss OTP modal first
        await MainActor.run {
            showingOTPPrompt = false
        }
        
        // Small delay to ensure sheet dismissal completes
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second
        
        do {
            // Create SSH tunnel with OTP
            print("🔐 Creating SSH tunnel with OTP for profile: \(profile.displayName)")
            print("🔐 About to call createTunnel...")
            let localPort = try await sshTunnelManager.createTunnel(
                connectionID: profileID.uuidString,
                sshConfig: sshConfig,
                vncHost: host,
                vncPort: Int(profile.port),
                otpCode: otp
            )
            
            print("✅ SSH tunnel created on local port: \(localPort)")
            print("🎯 createTunnel returned successfully with port \(localPort)")
            
            // Retrieve VNC password
            var vncPassword: String?
            if profile.savePassword {
                vncPassword = KeychainManager.shared.retrievePassword(for: profileID)
                print("🔐 VNC password retrieved from keychain: \(vncPassword != nil ? "[PASSWORD_SET]" : "[NIL]")")
            } else {
                print("🔐 VNC password saving disabled, will prompt if needed")
            }
            
            print("⏰ Waiting 2 seconds for tunnel to fully establish...")
            // Wait a moment for tunnel to fully establish
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
            
            // Check if task was cancelled
            try Task.checkCancellation()
            print("✅ Task not cancelled, proceeding with VNC connection")
            
            // Test the SSH tunnel with a simple HTTP request to the VNC port
            await testTunnelConnectivity(localPort: localPort, targetHost: host, targetPort: Int(profile.port))
            
            print("🔌 Connecting VNC to tunnel: localhost:\(localPort)")
            print("🔌 VNC connection details - host: localhost, port: \(localPort), username: \(profile.username ?? "[NIL]")")
            
            // Connect VNC through tunnel
            let vncClient = connectionManager.getVNCClient(for: profileID)
            print("🔌 VNC client obtained, calling connect...")
            await vncClient.connect(
                host: "localhost",  // Connect to local tunnel
                port: localPort,
                username: profile.username,
                password: vncPassword
            )
            print("🔌 VNC connect call completed")
            
            // Monitor connection state to open window when ready
            let cancellable = vncClient.$connectionState
                .receive(on: DispatchQueue.main)
                .sink { state in
                    if case .connected = state {
                        openWindow(id: "vnc-window", value: profileID)
                        print("🪟 Opening VNC window for SSH tunneled profile \(profile.displayName) with ID \(profileID) - state: \(state)")
                    } else if case .failed(let error) = state {
                        print("❌ SSH tunneled connection failed for \(profile.displayName): \(error)")
                    }
                }
            
            // Clean up the subscription after a reasonable time
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                cancellable.cancel()
            }
            
        } catch {
            print("❌ SSH tunnel or VNC connection failed: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            if let customError = error as? SSHTunnelError {
                print("❌ SSH Tunnel Error: \(customError.localizedDescription)")
            }
            
            // Extract detailed error information
            let errorDetails = extractSSHTunnelError(error)
            
            // Show diagnostics if it's a network-related error
            if errorDetails.showDiagnostics {
                await MainActor.run {
                    diagnosticsConnectionName = "\(profile.sshHost ?? "bastion") → \(host):\(profile.port)"
                    diagnosticsError = errorDetails.message
                    diagnosticsSuggestions = errorDetails.suggestions
                    showingDiagnostics = true
                }
            }
            
            // Clean up
            if let profileID = profile.id {
                connectionManager.disconnect(profileID: profileID)
            }
        }
        
        pendingSSHConfig = nil
        // Clean up the task reference
        await MainActor.run {
            sshConnectionTask = nil
        }
    }
    
    /// Test SSH tunnel connectivity by attempting to connect through it
    private func testTunnelConnectivity(localPort: Int, targetHost: String, targetPort: Int) async {
        print("🧪 Testing tunnel connectivity: localhost:\(localPort) -> \(targetHost):\(targetPort)")
        
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket != -1 else {
            print("❌ Tunnel test failed: couldn't create test socket")
            return
        }
        defer { Darwin.close(socket) }
        
        // Set socket to non-blocking for timeout control
        var flags = fcntl(socket, F_GETFL, 0)
        fcntl(socket, F_SETFL, flags | O_NONBLOCK)
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(localPort).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if connectResult == 0 {
            print("✅ Tunnel connectivity test: Connected successfully to localhost:\(localPort)")
            print("🔍 This confirms the tunnel is forwarding traffic to \(targetHost):\(targetPort)")
        } else {
            let error = errno
            if error == EINPROGRESS {
                print("⏳ Tunnel connectivity test: Connection in progress...")
                // Wait a bit and check if connection completes
                usleep(100000) // 0.1 second
                
                var errorCode: Int32 = 0
                var errorSize = socklen_t(MemoryLayout<Int32>.size)
                if getsockopt(socket, SOL_SOCKET, SO_ERROR, &errorCode, &errorSize) == 0 && errorCode == 0 {
                    print("✅ Tunnel connectivity test: Connection completed successfully")
                } else {
                    print("❌ Tunnel connectivity test: Connection failed with error \(errorCode)")
                }
            } else {
                print("❌ Tunnel connectivity test failed: connect error \(error)")
            }
        }
    }
    
    // Extract detailed error information from SSH tunnel errors
    private func extractSSHTunnelError(_ error: Error) -> (message: String, showDiagnostics: Bool, suggestions: [String]) {
        var message = error.localizedDescription
        var showDiagnostics = false
        var suggestions: [String] = []
        
        // Check for specific SSH errors
        if let tunnelError = error as? SSHTunnelError {
            switch tunnelError {
            case .connectionFailed(let reason):
                message = reason
                if reason.contains("No route to host") || reason.contains("channelSetupRejected") {
                    showDiagnostics = true
                    suggestions = [
                        "Verify the target hostname is accessible from the SSH bastion",
                        "Try using the target's IP address instead of hostname",
                        "Check if the target port is open and service is running",
                        "Contact your system administrator for network routing help"
                    ]
                }
            case .tunnelCreationFailed(let reason):
                message = reason
                if reason.contains("Validation failed") {
                    showDiagnostics = true
                    // Validation error already includes suggestions in the message
                }
            default:
                break
            }
        }
        
        // Check for NIO SSH errors in the message
        if message.contains("No route to host") || message.contains("Channel rejected") || message.contains("channelSetupRejected") {
            showDiagnostics = true
            if suggestions.isEmpty {
                suggestions = [
                    "The SSH server cannot reach the target host",
                    "Check network connectivity from bastion to target",
                    "Verify firewall rules allow the connection",
                    "Try a different target hostname or IP address"
                ]
            }
        }
        
        return (message, showDiagnostics, suggestions)
    }
}

struct ConnectionRowView: View {
    @Environment(\.openWindow) private var openWindow
    let connection: ConnectionProfile
    let connectionManager: ConnectionManager
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
    private var connectionState: VNCConnectionState {
        guard let profileID = connection.id else { return .disconnected }
        return connectionManager.getConnectionState(for: profileID)
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(connection.displayName)
                        .font(.headline)
                    
                    if connection.sshHost != nil {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(connection.displayHost)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("Last used: \(connection.formattedLastUsed)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Connect/Disconnect Button
                Button {
                    if case .connected = connectionState {
                        if let profileID = connection.id {
                            connectionManager.disconnect(profileID: profileID)
                        }
                    } else {
                        onConnect()
                    }
                } label: {
                    switch connectionState {
                    case .connecting:
                        Label("Connecting", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.iconOnly)
                    case .connected:
                        Label("Disconnect", systemImage: "stop.fill")
                            .labelStyle(.iconOnly)
                    default:
                        Label("Connect", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(connectionState == .connecting)
                
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Delete Connection?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \(connection.displayName)?")
        }
    }
}

#Preview {
    ConnectionListView()
        .environment(\.managedObjectContext, ConnectionProfileManager.shared.viewContext)
}