import SwiftUI
import CoreData
import Combine

struct ConnectionListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @StateObject private var connectionManager = ConnectionManager.shared
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
    
    var body: some View {
        NavigationStack {
            Group {
                if connections.isEmpty {
                    emptyStateView
                } else {
                    connectionsList
                }
            }
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
            } message: {
                if let profile = connectingProfile {
                    Text("Enter password for \(profile.displayName)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .vncPasswordRequired)) { notification in
                if let profileID = notification.userInfo?["profileID"] as? UUID,
                   profileID == connectingProfile?.id {
                    showingPasswordDialog = true
                }
            }
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
        
        // For now, connect directly to VNC (SSH tunnel implementation in Sprint 2)
        await vncClient.connect(
            host: host,
            port: Int(profile.port),
            username: profile.username,
            password: connectionPassword
        )
        
        // Open the display window if connection succeeds
        // Monitor connection state changes to open window when ready
        let cancellable = vncClient.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { state in
                if case .connected = state {
                    openWindow(id: "vnc-window", value: profileID)
                    print("🪟 Opening VNC window for profile \(profile.displayName) with ID \(profileID) - state: \(state)")
                } else if case .failed(let error) = state {
                    print("❌ Connection failed for \(profile.displayName): \(error)")
                }
            }
        
        // Clean up the subscription after a reasonable time
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            cancellable.cancel()
        }
    }
    
    private func deleteConnection(_ connection: ConnectionProfile) {
        withAnimation {
            ConnectionProfileManager.shared.deleteProfile(connection)
        }
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