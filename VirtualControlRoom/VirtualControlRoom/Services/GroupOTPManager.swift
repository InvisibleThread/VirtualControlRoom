import Foundation
import SwiftUI
import Combine

/// Manages shared OTP authentication for connection groups
@MainActor
class GroupOTPManager: ObservableObject {
    static let shared = GroupOTPManager()
    
    @Published var isShowingOTPPrompt = false
    @Published var groupLaunchState: GroupLaunchState = .idle
    @Published var connectionStates: [String: GroupConnectionState] = [:]
    
    private var currentGroup: ConnectionGroup?
    private var otpCompletion: ((String?) -> Void)?
    private let diagnosticsManager = ConnectionDiagnosticsManager.shared
    private let gridLayoutManager = GridLayoutManager.shared
    private var windowEnvironment: OpenWindowAction?
    private var dismissWindowEnvironment: DismissWindowAction?
    private var progressWindowID: String?
    
    // Properties for OTP prompt display
    var otpPromptConnectionName: String {
        if let group = currentGroup, 
           let firstSSHConnection = group.connections.first(where: { $0.sshHost?.isEmpty == false }) {
            return firstSSHConnection.sshHost ?? "SSH Server"
        }
        return "Group Connections"
    }
    
    private init() {}
    
    /// Set the window environment for opening group windows
    func setWindowEnvironment(_ environment: OpenWindowAction) {
        self.windowEnvironment = environment
    }
    
    /// Set the dismiss window environment for closing windows
    func setDismissWindowEnvironment(_ environment: DismissWindowAction) {
        self.dismissWindowEnvironment = environment
    }
    
    // MARK: - Group Launch with Shared OTP
    
    /// Launch a group of connections with shared OTP authentication
    func launchGroup(_ group: ConnectionGroup) async {
        print("🚀 GroupOTPManager: Launching group '\(group.name ?? "Unknown")'")
        
        currentGroup = group
        groupLaunchState = .preparing
        
        // Get actual connections from the group
        let connections = group.connections
        
        // Initialize connection states
        for connection in connections {
            if let connectionId = connection.id?.uuidString {
                connectionStates[connectionId] = .preparing
            }
        }
        
        // Check if group requires shared OTP
        let requiresOTP = GroupManager.shared.requiresSharedOTP(group)
        
        if requiresOTP {
            print("🔑 Group requires shared OTP - prompting user")
            await promptForSharedOTP { [weak self] otpCode in
                Task { @MainActor [weak self] in
                    if let otpCode = otpCode {
                        await self?.launchConnectionsWithOTP(connections, otpCode: otpCode)
                    } else {
                        await self?.cancelGroupLaunch()
                    }
                }
            }
        } else {
            print("🔓 Group does not require OTP - launching directly")
            await launchConnectionsWithOTP(connections, otpCode: nil)
        }
    }
    
    /// Prompt user for shared OTP code
    private func promptForSharedOTP(completion: @escaping (String?) -> Void) async {
        otpCompletion = completion
        isShowingOTPPrompt = true
        groupLaunchState = .awaitingOTP
    }
    
    /// Submit the OTP code entered by user
    func submitOTP(_ otpCode: String) {
        let trimmedCode = otpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedCode.isEmpty else {
            print("⚠️ Empty OTP code provided")
            return
        }
        
        print("🔑 User provided OTP code: \(String(repeating: "*", count: trimmedCode.count))")
        
        otpCompletion?(trimmedCode)
        otpCompletion = nil
        isShowingOTPPrompt = false
    }
    
    /// Cancel OTP prompt and group launch
    func cancelOTPPrompt() {
        otpCompletion?(nil)
        otpCompletion = nil
        isShowingOTPPrompt = false
        
        Task {
            await cancelGroupLaunch()
        }
    }
    
    // MARK: - Connection Launch Orchestration
    
    /// Launch all connections in parallel with shared OTP
    private func launchConnectionsWithOTP(_ connections: [ConnectionProfile], otpCode: String?) async {
        print("🚀 Launching \(connections.count) connections with shared authentication")
        groupLaunchState = .connecting
        
        // Show progress window
        if let group = currentGroup,
           let windowEnvironment = windowEnvironment {
            let progressValue = GroupProgressValue(
                groupID: group.id?.uuidString ?? UUID().uuidString,
                groupName: group.name ?? "Unknown Group",
                connectionIDs: connections.compactMap { $0.id?.uuidString }
            )
            
            progressWindowID = "progress-\(progressValue.groupID)"
            windowEnvironment(id: "group-progress", value: progressValue)
            print("📊 Opened group connection progress window")
        }
        
        // Generate trace ID for this group launch
        if let firstConnection = connections.first,
           let connectionId = firstConnection.id?.uuidString {
            let _ = await diagnosticsManager.generateTraceID(for: connectionId)
            
            diagnosticsManager.addTraceLog(
                "GROUP_LAUNCH",
                method: "launchConnectionsWithOTP",
                id: "START",
                context: ["group": currentGroup?.name ?? "Unknown", "count": connections.count, "hasOTP": otpCode != nil],
                connectionID: connectionId,
                level: .info
            )
        }
        
        // Check if we can use optimized parallel SSH tunnel creation
        let requiresOTP = GroupManager.shared.requiresSharedOTP(currentGroup!)
        
        if requiresOTP && otpCode != nil {
            // Use optimized parallel SSH tunnel creation
            await launchGroupWithParallelSSH(connections, otpCode: otpCode!)
        } else {
            // Fall back to individual connection launch
            await withTaskGroup(of: Void.self) { taskGroup in
                for connection in connections {
                    taskGroup.addTask { [weak self] in
                        await self?.launchSingleConnection(connection, otpCode: otpCode)
                    }
                }
            }
        }
        
        // Update group launch state based on results
        await updateGroupLaunchResult()
    }
    
    /// Launch group by reusing the proven individual connection logic
    private func launchGroupWithParallelSSH(_ connections: [ConnectionProfile], otpCode: String) async {
        print("🚀 Launching group by reusing individual connection logic with shared OTP")
        
        // Use the proven individual connection flow for each connection
        // This reuses all the working SSH authentication, tunnel creation, and VNC monitoring logic
        
        for connection in connections {
            guard let connectionId = connection.id?.uuidString else { continue }
            
            connectionStates[connectionId] = .connecting
            print("🔌 Launching connection '\(connection.displayName)' using individual connection logic")
            
            // Reuse the individual connection logic by calling the same methods used in ConnectionListView
            await launchConnectionUsingIndividualLogic(connection, sharedOTP: otpCode)
            
            // Add small delay between connections for stability
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
    }
    
    /// Launch a single connection using the same proven logic as individual connections
    private func launchConnectionUsingIndividualLogic(_ connection: ConnectionProfile, sharedOTP: String) async {
        guard let profileID = connection.id else { return }
        let connectionID = profileID.uuidString
        
        // Mark profile as used (same as individual connections)
        ConnectionProfileManager.shared.markProfileAsUsed(connection)
        
        // Get VNC client (same as individual connections)
        let vncClient = ConnectionManager.shared.getVNCClient(for: profileID)
        
        // Check if SSH tunnel is enabled (same logic as individual connections)
        if let sshHost = connection.sshHost,
           !sshHost.isEmpty,
           let sshUsername = connection.sshUsername {
            
            print("🔒 SSH tunnel enabled for group connection: \(connection.displayName)")
            
            // Retrieve SSH password from Keychain (same as individual connections)
            let sshPassword = KeychainManager.shared.retrieveSSHPassword(for: profileID)
            
            // Create SSH config (same as individual connections)
            let sshConfig = SSHConnectionConfig(
                host: sshHost,
                port: Int(connection.sshPort),
                username: sshUsername,
                authMethod: .password(sshPassword ?? ""),
                connectTimeout: 30
            )
            
            // Create SSH tunnel with shared OTP (reuse handleOTPSubmit logic)
            await handleConnectionWithSSHTunnel(connection, sshConfig: sshConfig, sharedOTP: sharedOTP)
            
        } else {
            // Direct VNC connection (same as individual connections)
            await handleDirectVNCConnection(connection)
        }
    }
    
    /// Handle SSH tunnel connection using the same logic as individual connections
    private func handleConnectionWithSSHTunnel(_ connection: ConnectionProfile, sshConfig: SSHConnectionConfig, sharedOTP: String) async {
        guard let profileID = connection.id,
              let host = connection.host else { return }
        
        let connectionID = profileID.uuidString
        
        do {
            // Create SSH tunnel with OTP (same as individual handleOTPSubmit)
            let localPort = try await SSHTunnelManager.shared.createTunnel(
                connectionID: connectionID,
                sshConfig: sshConfig,
                vncHost: host,
                vncPort: Int(connection.port),
                otpCode: sharedOTP
            )
            
            print("✅ SSH tunnel created on local port: \(localPort) for group connection")
            
            // Wait longer for tunnel to establish in group mode
            // Group connections need more time due to multiplexing overhead
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 second delay
            
            // Connect VNC through tunnel (same as individual connections)
            let vncClient = ConnectionManager.shared.getVNCClient(for: profileID)
            
            // Apply optimization settings (same as individual connections)
            await VNCOptimizationManager.shared.configureVNCClient(vncClient, for: connection)
            
            // Retrieve VNC password (same as individual connections)
            var vncPassword: String?
            if connection.savePassword {
                vncPassword = KeychainManager.shared.retrievePassword(for: profileID)
            }
            
            // Log VNC connection parameters for debugging
            print("🖥️ Connecting VNC for '\(connection.displayName)':")
            print("   - SSH tunnel: localhost:\(localPort)")
            print("   - Original VNC target: \(host):\(connection.port)")
            print("   - Username: \(connection.username ?? "none")")
            print("   - Password saved: \(connection.savePassword)")
            
            // Connect VNC to tunnel (same as individual connections)
            await vncClient.connect(
                host: "localhost",
                port: localPort,
                username: connection.username,
                password: vncPassword
            )
            
            // Monitor connection state and open window (same as individual connections)
            let cancellable = vncClient.$connectionState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    Task { @MainActor [weak self] in
                        switch state {
                        case .connected:
                            self?.connectionStates[connectionID] = .connected
                            print("✅ Group SSH connection '\(connection.displayName)' established")
                            
                            // Note: Individual window opening removed - using unified grid window instead
                        print("✅ Group SSH connection '\(connection.displayName)' ready for grid display")
                            
                        case .failed(let error):
                            self?.connectionStates[connectionID] = .failed("VNC connection failed: \(error)")
                            print("❌ Group SSH connection '\(connection.displayName)' failed: \(error)")
                            
                        case .connecting:
                            print("🔄 Group SSH connection '\(connection.displayName)' connecting...")
                            
                        case .disconnected:
                            print("🔌 Group SSH connection '\(connection.displayName)' disconnected")
                        }
                    }
                }
            
            // Clean up subscription (same as individual connections)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                cancellable.cancel()
            }
            
        } catch {
            await MainActor.run {
                connectionStates[connectionID] = .failed("SSH tunnel failed: \(error.localizedDescription)")
            }
            print("❌ SSH tunnel creation failed for group connection \(connection.displayName): \(error)")
        }
    }
    
    /// Handle direct VNC connection using the same logic as individual connections
    private func handleDirectVNCConnection(_ connection: ConnectionProfile) async {
        guard let profileID = connection.id,
              let host = connection.host else { return }
        
        let connectionID = profileID.uuidString
        let vncClient = ConnectionManager.shared.getVNCClient(for: profileID)
        
        // Apply optimization settings (same as individual connections)
        await VNCOptimizationManager.shared.configureVNCClient(vncClient, for: connection)
        
        // Get VNC password (same as individual connections)
        var connectionPassword: String?
        if connection.savePassword {
            connectionPassword = KeychainManager.shared.retrievePassword(for: profileID)
        }
        
        // Connect directly (same as individual connections)
        await vncClient.connect(
            host: host,
            port: Int(connection.port),
            username: connection.username,
            password: connectionPassword
        )
        
        // Monitor connection state and open window (same as individual connections)
        let cancellable = vncClient.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .connected:
                        self?.connectionStates[connectionID] = .connected
                        print("✅ Group direct connection '\(connection.displayName)' established")
                        
                        // Note: Individual window opening removed - using unified grid window instead
                        print("✅ Group direct connection '\(connection.displayName)' ready for grid display")
                        
                    case .failed(let error):
                        self?.connectionStates[connectionID] = .failed("VNC connection failed: \(error)")
                        print("❌ Group direct connection '\(connection.displayName)' failed: \(error)")
                        
                    case .connecting:
                        print("🔄 Group direct connection '\(connection.displayName)' connecting...")
                        
                    case .disconnected:
                        print("🔌 Group direct connection '\(connection.displayName)' disconnected")
                    }
                }
            }
        
        // Clean up subscription (same as individual connections)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            cancellable.cancel()
        }
    }
    
    
    /// Launch a single connection with optional OTP
    private func launchSingleConnection(_ connection: ConnectionProfile, otpCode: String?) async {
        guard let connectionId = connection.id?.uuidString else { return }
        
        print("🔌 Launching connection '\(connection.displayName)' with shared OTP")
        connectionStates[connectionId] = .connecting
        
        diagnosticsManager.addTraceLog(
            "GROUP_CONNECTION",
            method: "launchSingleConnection",
            id: "START",
            context: ["connection": connection.displayName, "hasOTP": otpCode != nil],
            connectionID: connectionId
        )
        
        do {
            // Get VNC client for this connection
            let vncClient = ConnectionManager.shared.getVNCClient(for: connection.id!)
            
            // Determine SSH configuration
            var sshConfig: SSHConnectionConfig?
            if let sshHost = connection.sshHost,
               let sshUsername = connection.sshUsername,
               !sshHost.isEmpty {
                
                // Get saved password from keychain
                let savedPassword = KeychainManager.shared.retrievePassword(for: connection.id!) ?? ""
                let finalPassword = otpCode != nil ? savedPassword + otpCode! : savedPassword
                
                sshConfig = SSHConnectionConfig(
                    host: sshHost,
                    port: Int(connection.sshPort),
                    username: sshUsername,
                    authMethod: .password(finalPassword),
                    connectTimeout: 15.0
                )
            }
            
            if let sshConfig = sshConfig {
                // Create SSH tunnel first using the SSHTunnelManager (which handles the complexity)
                let localPort = try await SSHTunnelManager.shared.createTunnel(
                    connectionID: connectionId,
                    sshConfig: sshConfig,
                    vncHost: connection.host ?? "localhost",
                    vncPort: Int(connection.port),
                    otpCode: nil // OTP already included in password
                )
                
                // Connect VNC through tunnel
                await vncClient.connect(
                    host: "localhost",
                    port: localPort,
                    username: connection.username,
                    password: KeychainManager.shared.retrievePassword(for: connection.id!)
                )
            } else {
                // Direct VNC connection (no SSH tunnel)
                await vncClient.connect(
                    host: connection.host ?? "localhost",
                    port: Int(connection.port),
                    username: connection.username,
                    password: KeychainManager.shared.retrievePassword(for: connection.id!)
                )
            }
            
            connectionStates[connectionId] = .connected
            
            diagnosticsManager.addTraceLog(
                "GROUP_CONNECTION",
                method: "launchSingleConnection",
                id: "SUCCESS",
                result: "Connected successfully",
                connectionID: connectionId,
                level: .success
            )
            
            print("✅ Connection '\(connection.displayName)' launched successfully")
        } catch {
            connectionStates[connectionId] = .failed(error.localizedDescription)
            
            diagnosticsManager.addTraceLog(
                "GROUP_CONNECTION",
                method: "launchSingleConnection",
                id: "FAILED",
                context: ["error": error.localizedDescription],
                result: "FAIL",
                connectionID: connectionId,
                level: .error
            )
            
            print("❌ Connection '\(connection.displayName)' failed: \(error.localizedDescription)")
        }
    }
    
    /// Update overall group launch result and open windows in grid layout
    private func updateGroupLaunchResult() async {
        let states = Array(connectionStates.values)
        let connectedCount = states.filter { if case .connected = $0 { return true }; return false }.count
        let failedCount = states.filter { if case .failed = $0 { return true }; return false }.count
        
        if connectedCount == states.count {
            groupLaunchState = .completed(.allSucceeded)
            print("🎉 All connections launched successfully")
            
            // Open unified grid window for all connections
            if let group = currentGroup {
                await openUnifiedGridWindow(group, includeAllConnections: true)
            }
        } else if connectedCount > 0 {
            groupLaunchState = .completed(.partialSuccess(connected: connectedCount, failed: failedCount))
            print("⚠️ Partial success: \(connectedCount) connected, \(failedCount) failed")
            
            // Open unified grid window for all connections to show placeholders for failed ones
            if let group = currentGroup {
                await openUnifiedGridWindow(group, includeAllConnections: true)
            }
        } else {
            groupLaunchState = .completed(.allFailed)
            print("❌ All connections failed")
            
            // Close progress window even if all failed
            if let dismissEnvironment = dismissWindowEnvironment,
               let progressID = progressWindowID {
                dismissEnvironment(id: "group-progress")
                print("📊 Closed group connection progress window (all failed)")
                progressWindowID = nil
            }
        }
        
        // Update group's last used date
        if let group = currentGroup {
            group.lastUsedAt = Date()
            try? GroupManager.shared.context.save()
        }
        
        // Auto-dismiss after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.resetLaunchState()
        }
    }
    
    /// Open unified grid window containing all connections in a single 2D window
    private func openUnifiedGridWindow(_ group: ConnectionGroup, includeAllConnections: Bool) async {
        let allConnections = group.connections
        let connectionsToInclude: [ConnectionProfile]
        
        if includeAllConnections {
            connectionsToInclude = allConnections
        } else {
            // Only include successful connections
            connectionsToInclude = allConnections.filter { connection in
                guard let connectionId = connection.id?.uuidString else { return false }
                if case .connected = connectionStates[connectionId] {
                    return true
                }
                return false
            }
        }
        
        guard !connectionsToInclude.isEmpty else {
            print("⚠️ No connections to display in grid window")
            return
        }
        
        let layoutType = GroupManager.shared.getRecommendedLayout(for: group)
        let groupID = group.id?.uuidString ?? UUID().uuidString
        let groupName = group.name ?? "Unknown Group"
        
        print("🏗️ Opening unified grid window for \(connectionsToInclude.count) connections in \(layoutType) layout")
        
        // Create group grid value
        let connectionIDs = connectionsToInclude.compactMap { $0.id?.uuidString }
        let groupGridValue = GroupGridValue(
            groupID: groupID,
            groupName: groupName,
            connectionIDs: connectionIDs,
            layoutType: layoutType
        )
        
        // Close progress window if it's open
        if let dismissEnvironment = dismissWindowEnvironment,
           let progressID = progressWindowID {
            dismissEnvironment(id: "group-progress")
            print("📊 Closed group connection progress window")
            progressWindowID = nil
        }
        
        // Open single grid window
        if let windowEnvironment = getWindowEnvironment() {
            windowEnvironment(id: "vnc-group-grid", value: groupGridValue)
            print("🪟 Opened unified grid window for group '\(groupName)' with \(connectionIDs.count) connections")
        } else {
            print("⚠️ Window environment not available for opening unified grid window")
        }
    }
    
    /// Get the window opening environment
    private func getWindowEnvironment() -> OpenWindowAction? {
        return windowEnvironment
    }
    
    /// Cancel group launch
    private func cancelGroupLaunch() async {
        print("❌ Group launch cancelled")
        
        // Close progress window if it's open
        if let dismissEnvironment = dismissWindowEnvironment,
           let progressID = progressWindowID {
            dismissEnvironment(id: "group-progress")
            print("📊 Closed group connection progress window (cancelled)")
            progressWindowID = nil
        }
        
        groupLaunchState = .idle
        connectionStates.removeAll()
        currentGroup = nil
    }
    
    /// Reset launch state to idle
    func resetLaunchState() {
        groupLaunchState = .idle
        connectionStates.removeAll()
        currentGroup = nil
    }
    
    // MARK: - Group Management
    
    /// Close all connections in a group
    func closeGroup(_ group: ConnectionGroup) async {
        print("🔌 Closing all connections in group '\(group.name ?? "Unknown")'")
        
        let groupID = group.id?.uuidString ?? "unknown"
        
        // Close group windows via GridLayoutManager
        gridLayoutManager.closeGroupWindows(groupID: groupID)
        
        // Get actual connections from the group
        let connections = group.connections
        
        for connection in connections {
            guard let connectionId = connection.id else { continue }
            
            // Close VNC connection
            let vncClient = ConnectionManager.shared.getVNCClient(for: connectionId)
            vncClient.disconnect()
            
            // Close SSH tunnel if exists
            let connectionIdString = connectionId.uuidString
            if SSHTunnelManager.shared.hasTunnel(for: connectionIdString) {
                SSHTunnelManager.shared.closeTunnel(connectionID: connectionIdString)
            }
        }
        
        // Reset group launch state
        resetLaunchState()
        
        print("✅ Closed all connections and windows in group")
    }
}

// MARK: - Supporting Types

enum GroupLaunchState: Equatable {
    case idle
    case preparing
    case awaitingOTP
    case connecting
    case completed(GroupLaunchResult)
}

enum GroupLaunchResult: Equatable {
    case allSucceeded
    case partialSuccess(connected: Int, failed: Int)
    case allFailed
}

enum GroupConnectionState: Equatable {
    case preparing
    case connecting
    case connected
    case failed(String)
    
    var displayText: String {
        switch self {
        case .preparing:
            return "Preparing..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
    
    var isSuccessful: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}