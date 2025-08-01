import SwiftUI
import CoreData

struct GroupListView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var groupManager = GroupManager.shared
    @StateObject private var otpManager = GroupOTPManager.shared
    @State private var showingCreateGroup = false
    @State private var groupToEdit: ConnectionGroup?
    @State private var groupToDelete: ConnectionGroup?
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                if groupManager.groups.isEmpty {
                    ContentUnavailableView(
                        "No Connection Groups",
                        systemImage: "rectangle.3.group",
                        description: Text("Create groups to launch multiple connections together")
                    )
                } else {
                    ForEach(groupManager.groups, id: \.id) { group in
                        GroupRowView(group: group)
                            .contextMenu {
                                Button("Edit") {
                                    groupToEdit = group
                                }
                                
                                Button("Duplicate") {
                                    let _ = groupManager.duplicateGroup(group)
                                }
                                
                                Divider()
                                
                                Button("Delete", role: .destructive) {
                                    groupToDelete = group
                                    showingDeleteAlert = true
                                }
                            }
                    }
                    .onDelete(perform: deleteGroups)
                }
            }
            .navigationTitle("Connection Groups")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Group") {
                        showingCreateGroup = true
                    }
                }
            }
            .sheet(isPresented: $showingCreateGroup) {
                CreateGroupView()
            }
            .sheet(item: $groupToEdit) { group in
                EditGroupView(group: group)
            }
            .alert("Delete Group", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let group = groupToDelete {
                        groupManager.deleteGroup(group)
                    }
                }
            } message: {
                Text("Are you sure you want to delete '\(groupToDelete?.name ?? "this group")'? This cannot be undone.")
            }
            .onAppear {
                // Inject window environment into GroupOTPManager
                otpManager.setWindowEnvironment(openWindow)
            }
            .sheet(isPresented: $otpManager.isShowingOTPPrompt) {
                OTPPromptView(
                    isPresented: $otpManager.isShowingOTPPrompt,
                    connectionName: otpManager.otpPromptConnectionName,
                    onSubmit: { otp in
                        otpManager.submitOTP(otp)
                    },
                    onCancel: {
                        otpManager.cancelOTPPrompt()
                    }
                )
            }
        }
    }
    
    private func deleteGroups(offsets: IndexSet) {
        for index in offsets {
            if groupManager.groups.indices.contains(index) {
                groupManager.deleteGroup(groupManager.groups[index])
            }
        }
    }
}

struct GroupRowView: View {
    let group: ConnectionGroup
    @StateObject private var groupManager = GroupManager.shared
    @StateObject private var otpManager = GroupOTPManager.shared
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    
    private var connectionCount: Int {
        return group.connections.count
    }
    
    private var layoutDescription: String {
        groupManager.getRecommendedLayout(for: group)
    }
    
    private var requiresOTP: Bool {
        groupManager.requiresSharedOTP(group)
    }
    
    private var validationResult: (isValid: Bool, issues: [String]) {
        groupManager.validateGroupForLaunch(group)
    }
    
    private var isGroupActive: Bool {
        otpManager.groupLaunchState != .idle
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Group info (tappable for navigation)
            NavigationLink(destination: GroupDetailView(group: group)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.name ?? "Untitled Group")
                            .font(.headline)
                        
                        Spacer()
                        
                        if requiresOTP {
                            Image(systemName: "key.fill")
                                .foregroundColor(.blue)
                                .help("Supports shared OTP")
                        }
                    }
                    
                    HStack {
                        Label("\(connectionCount) connections", systemImage: "network")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text(layoutDescription.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.regularMaterial)
                            .clipShape(Capsule())
                    }
                    
                    if let lastUsed = group.lastUsedAt {
                        Text("Last used \(lastUsed, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Action buttons
            HStack(spacing: 8) {
                // Play/Stop button (primary action)
                Button(action: {
                    Task {
                        if isGroupActive {
                            await otpManager.closeGroup(group)
                        } else {
                            await otpManager.launchGroup(group)
                        }
                    }
                }) {
                    if isGroupActive {
                        Label("Stop All Connections", systemImage: "stop.fill")
                            .labelStyle(.iconOnly)
                    } else {
                        Label("Launch Group", systemImage: "play.fill")
                            .labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!validationResult.isValid && !isGroupActive)
                
                // Edit button
                Button(action: {
                    showingEditSheet = true
                }) {
                    Label("Edit", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                
                // Delete button
                Button(action: {
                    showingDeleteAlert = true
                }) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditGroupView(group: group)
        }
        .alert("Delete Group", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                groupManager.deleteGroup(group)
            }
        } message: {
            Text("Are you sure you want to delete '\(group.name ?? "this group")'? This cannot be undone.")
        }
    }
}

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var groupManager = GroupManager.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ConnectionProfile.name, ascending: true)],
        animation: .default
    )
    private var availableProfiles: FetchedResults<ConnectionProfile>
    
    @State private var groupName = ""
    @State private var selectedConnections: Set<ConnectionProfile> = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Group Details") {
                    TextField("Group Name", text: $groupName)
                }
                
                Section("Connections") {
                    if availableProfiles.isEmpty {
                        Text("No connections available. Create connections first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableProfiles, id: \.id) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.displayName)
                                        .font(.headline)
                                    
                                    if let host = profile.host {
                                        Text(host)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if selectedConnections.contains(profile) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedConnections.contains(profile) {
                                    selectedConnections.remove(profile)
                                } else {
                                    selectedConnections.insert(profile)
                                }
                            }
                        }
                    }
                }
                
                if !selectedConnections.isEmpty {
                    Section("Preview") {
                        let layout = groupManager.getRecommendedLayout(for: createPreviewGroup())
                        Text("Layout: \(layout.replacingOccurrences(of: "_", with: " "))")
                        Text("\(selectedConnections.count) connections")
                        
                        if groupManager.requiresSharedOTP(createPreviewGroup()) {
                            Label("Supports shared OTP", systemImage: "key.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createGroup()
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func createPreviewGroup() -> ConnectionGroup {
        let previewGroup = ConnectionGroup(context: groupManager.context)
        // TODO: Set connections when Core Data relationships are added
        return previewGroup
    }
    
    private func createGroup() {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let _ = groupManager.createGroup(name: trimmedName, connections: Array(selectedConnections))
        dismiss()
    }
}

struct EditGroupView: View {
    let group: ConnectionGroup
    @Environment(\.dismiss) private var dismiss
    @StateObject private var groupManager = GroupManager.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ConnectionProfile.name, ascending: true)],
        animation: .default
    )
    private var availableProfiles: FetchedResults<ConnectionProfile>
    
    @State private var groupName: String
    @State private var selectedConnections: Set<ConnectionProfile>
    
    init(group: ConnectionGroup) {
        self.group = group
        self._groupName = State(initialValue: group.name ?? "")
        
        // TODO: Get connections when Core Data relationships are implemented
        let connections: [ConnectionProfile] = []
        self._selectedConnections = State(initialValue: Set(connections))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Group Details") {
                    TextField("Group Name", text: $groupName)
                }
                
                Section("Connections") {
                    if availableProfiles.isEmpty {
                        Text("No connections available.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableProfiles, id: \.id) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.displayName)
                                        .font(.headline)
                                    
                                    if let host = profile.host {
                                        Text(host)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if selectedConnections.contains(profile) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedConnections.contains(profile) {
                                    selectedConnections.remove(profile)
                                } else {
                                    selectedConnections.insert(profile)
                                }
                            }
                        }
                    }
                }
                
                Section("Preview") {
                    Text("Layout: \(groupManager.getRecommendedLayout(for: group).replacingOccurrences(of: "_", with: " "))")
                    Text("\(selectedConnections.count) connections")
                    
                    if groupManager.requiresSharedOTP(createPreviewGroup()) {
                        Label("Supports shared OTP", systemImage: "key.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func createPreviewGroup() -> ConnectionGroup {
        let previewGroup = ConnectionGroup(context: groupManager.context)
        // TODO: Set connections when Core Data relationships are added
        return previewGroup
    }
    
    private func saveChanges() {
        // Update group name
        groupManager.updateGroup(group, name: groupName.trimmingCharacters(in: .whitespacesAndNewlines))
        
        // Update connections (stubbed until Core Data relationships are implemented)
        let currentConnections: Set<ConnectionProfile> = []
        
        // Remove connections that are no longer selected
        for connection in currentConnections {
            if !selectedConnections.contains(connection) {
                groupManager.removeConnection(connection, from: group)
            }
        }
        
        // Add newly selected connections
        for connection in selectedConnections {
            if !currentConnections.contains(connection) {
                groupManager.addConnection(connection, to: group)
            }
        }
        
        dismiss()
    }
}

struct GroupDetailView: View {
    let group: ConnectionGroup
    @StateObject private var groupManager = GroupManager.shared
    @StateObject private var otpManager = GroupOTPManager.shared
    @State private var showingEditSheet = false
    
    private var connections: [ConnectionProfile] {
        return group.connections
    }
    
    private var validationResult: (isValid: Bool, issues: [String]) {
        groupManager.validateGroupForLaunch(group)
    }
    
    var body: some View {
        List {
            Section("Group Info") {
                HStack {
                    Text("Layout")
                    Spacer()
                    Text(groupManager.getRecommendedLayout(for: group).replacingOccurrences(of: "_", with: " "))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Connections")
                    Spacer()
                    Text("\(connections.count)")
                        .foregroundStyle(.secondary)
                }
                
                if groupManager.requiresSharedOTP(group) {
                    HStack {
                        Text("Shared OTP")
                        Spacer()
                        Label("Supported", systemImage: "key.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                if let createdAt = group.createdAt {
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(createdAt, style: .date)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("Connections") {
                if connections.isEmpty {
                    Text("No connections in this group")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(connections.enumerated()), id: \.element.id) { index, connection in
                        VStack(alignment: .leading) {
                            HStack {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .frame(width: 20, alignment: .leading)
                                
                                Text(connection.displayName)
                                    .font(.headline)
                                
                                Spacer()
                            }
                            
                            if let host = connection.host {
                                HStack {
                                    Text("")
                                        .frame(width: 20)
                                    
                                    Text(host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    if connection.sshHost != nil {
                                        Image(systemName: "lock.shield")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { source, destination in
                        groupManager.reorderConnections(in: group, from: IndexSet(source), to: destination)
                    }
                }
            }
            
            if !validationResult.isValid {
                Section("Issues") {
                    ForEach(validationResult.issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .navigationTitle(group.name ?? "Untitled Group")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button("Launch Group") {
                    Task {
                        await otpManager.launchGroup(group)
                    }
                }
                .disabled(!validationResult.isValid || otpManager.groupLaunchState != .idle)
            }
            
            if otpManager.groupLaunchState != .idle {
                ToolbarItem(placement: .secondaryAction) {
                    Button("Close All") {
                        Task {
                            await otpManager.closeGroup(group)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $otpManager.isShowingOTPPrompt) {
            OTPPromptView(
                isPresented: $otpManager.isShowingOTPPrompt,
                connectionName: otpManager.otpPromptConnectionName,
                onSubmit: { otp in
                    otpManager.submitOTP(otp)
                },
                onCancel: {
                    otpManager.cancelOTPPrompt()
                }
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            EditGroupView(group: group)
        }
        .overlay {
            if otpManager.groupLaunchState != .idle {
                GroupLaunchStatusView(group: group)
            }
        }
    }
}

#Preview {
    GroupListView()
        .environment(\.managedObjectContext, ConnectionProfileManager.shared.viewContext)
}