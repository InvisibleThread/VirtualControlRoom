import SwiftUI
import CoreData

struct ConnectionListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var vncClient: LibVNCClient
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ConnectionProfile.lastUsedAt, ascending: false),
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
                    if let profile = connectingProfile {
                        Task {
                            await performConnection(profile, password: enteredPassword)
                        }
                    }
                    enteredPassword = ""
                    connectingProfile = nil
                }
                Button("Cancel", role: .cancel) {
                    enteredPassword = ""
                    connectingProfile = nil
                }
            } message: {
                if let profile = connectingProfile {
                    Text("Enter password for \(profile.displayName)")
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
                    vncClient: vncClient
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
        ConnectionProfileManager.shared.markProfileAsUsed(profile)
        
        // Check if we need a password
        let needsPassword = !profile.savePassword && (profile.username?.isEmpty == false)
        
        if needsPassword {
            connectingProfile = profile
            showingPasswordDialog = true
        } else {
            Task {
                await performConnection(profile, password: nil)
            }
        }
    }
    
    private func performConnection(_ profile: ConnectionProfile, password: String?) async {
        guard let host = profile.host else { return }
        
        // For now, connect directly to VNC (SSH tunnel implementation in Sprint 2)
        await vncClient.connect(
            host: host,
            port: Int(profile.port),
            username: profile.username,
            password: password
        )
        
        // Open the display window if connection succeeds
        if case .connected = vncClient.connectionState {
            await MainActor.run {
                openWindow(id: "vnc-simple-window")
            }
        }
    }
    
    private func deleteConnection(_ connection: ConnectionProfile) {
        withAnimation {
            ConnectionProfileManager.shared.deleteProfile(connection)
        }
    }
}

struct ConnectionRowView: View {
    let connection: ConnectionProfile
    let vncClient: LibVNCClient
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
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
            
            HStack(spacing: 12) {
                Button {
                    onConnect()
                } label: {
                    switch vncClient.connectionState {
                    case .connecting:
                        Label("Connecting", systemImage: "arrow.triangle.2.circlepath")
                            .labelStyle(.iconOnly)
                    case .connected:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                    default:
                        Label("Connect", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vncClient.connectionState == .connecting)
                
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