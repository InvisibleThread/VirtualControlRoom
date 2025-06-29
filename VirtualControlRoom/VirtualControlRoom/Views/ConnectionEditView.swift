import SwiftUI
import CoreData

struct ConnectionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    let connection: ConnectionProfile?
    
    @State private var name = ""
    @State private var host = ""
    @State private var port = "5900"
    @State private var username = ""
    @State private var passwordHint = ""
    @State private var savePassword = false
    @State private var password = ""
    @State private var useSSHTunnel = false
    @State private var sshHost = ""
    @State private var sshPort = "22"
    @State private var sshUsername = ""
    
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    
    var isNewConnection: Bool {
        connection == nil
    }
    
    var body: some View {
        Form {
            Section("Connection Details") {
                TextField("Connection Name", text: $name)
                    .textContentType(.name)
                
                TextField("VNC Host", text: $host)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                
                TextField("VNC Port", text: $port)
                    .keyboardType(.numberPad)
                
                TextField("Username (optional)", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)
            }
            
            Section("Authentication") {
                Toggle("Save Password", isOn: $savePassword.animation())
                
                if savePassword {
                    SecureField("VNC Password", text: $password)
                        .textContentType(.password)
                    
                    TextField("Password Hint (Optional)", text: $passwordHint)
                        .help("Enter a hint to remember your password")
                        .textContentType(.none)
                }
                
                if !savePassword {
                    Text("Password will be requested when connecting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Password will be stored securely in Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Toggle("Use SSH Tunnel", isOn: $useSSHTunnel.animation())
                
                if useSSHTunnel {
                    TextField("SSH Host", text: $sshHost)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    TextField("SSH Port", text: $sshPort)
                        .keyboardType(.numberPad)
                    
                    TextField("SSH Username", text: $sshUsername)
                        .textContentType(.username)
                        .autocapitalization(.none)
                }
            } header: {
                Text("SSH Tunnel (Recommended)")
            } footer: {
                if useSSHTunnel {
                    Text("VNC connection will be tunneled through SSH for enhanced security")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(isNewConnection ? "New Connection" : "Edit Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveConnection()
                }
                .fontWeight(.semibold)
            }
        }
        .alert("Validation Error", isPresented: $showingValidationAlert) {
            Button("OK") { }
        } message: {
            Text(validationMessage)
        }
        .onAppear {
            loadConnectionData()
        }
    }
    
    private func loadConnectionData() {
        guard let connection = connection else { return }
        
        name = connection.name ?? ""
        host = connection.host ?? ""
        port = String(connection.port)
        username = connection.username ?? ""
        passwordHint = connection.passwordHint ?? ""
        savePassword = connection.savePassword
        
        // Load saved password from Keychain if available
        if savePassword, let profileID = connection.id {
            password = KeychainManager.shared.retrievePassword(for: profileID) ?? ""
        }
        
        if let sshHostValue = connection.sshHost, !sshHostValue.isEmpty {
            useSSHTunnel = true
            sshHost = sshHostValue
            sshPort = String(connection.sshPort)
            sshUsername = connection.sshUsername ?? ""
        }
    }
    
    private func validateForm() -> Bool {
        // Validate required fields
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "Please enter a connection name"
            return false
        }
        
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "Please enter a VNC host"
            return false
        }
        
        // Validate port numbers
        guard let vncPort = Int32(port), vncPort > 0, vncPort <= 65535 else {
            validationMessage = "VNC port must be a number between 1 and 65535"
            return false
        }
        
        if useSSHTunnel {
            guard !sshHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                validationMessage = "Please enter an SSH host"
                return false
            }
            
            guard let sshPortNum = Int32(sshPort), sshPortNum > 0, sshPortNum <= 65535 else {
                validationMessage = "SSH port must be a number between 1 and 65535"
                return false
            }
            
            guard !sshUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                validationMessage = "Please enter an SSH username"
                return false
            }
        }
        
        return true
    }
    
    private func saveConnection() {
        guard validateForm() else {
            showingValidationAlert = true
            return
        }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let connection = connection {
            // Update existing connection
            connection.name = trimmedName
            connection.host = trimmedHost
            connection.port = Int32(port) ?? 5900
            connection.username = trimmedUsername.isEmpty ? nil : trimmedUsername
            connection.savePassword = savePassword
            connection.passwordHint = savePassword ? passwordHint.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            
            // Handle password storage in Keychain
            if let profileID = connection.id {
                if savePassword && !password.isEmpty {
                    // Store password in Keychain
                    let _ = KeychainManager.shared.storePassword(password, for: profileID)
                } else {
                    // Remove password from Keychain if not saving
                    let _ = KeychainManager.shared.deletePassword(for: profileID)
                }
            }
            
            if useSSHTunnel {
                connection.sshHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
                connection.sshPort = Int32(sshPort) ?? 22
                connection.sshUsername = sshUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                connection.sshHost = nil
                connection.sshPort = 22
                connection.sshUsername = nil
            }
            
            ConnectionProfileManager.shared.updateProfile(connection)
        } else {
            // Create new connection
            let profile = ConnectionProfileManager.shared.createProfile(
                name: trimmedName,
                host: trimmedHost,
                port: Int32(port) ?? 5900,
                username: trimmedUsername.isEmpty ? nil : trimmedUsername,
                sshHost: useSSHTunnel ? sshHost.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                sshPort: useSSHTunnel ? Int32(sshPort) : nil,
                sshUsername: useSSHTunnel ? sshUsername.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            )
            
            profile.savePassword = savePassword
            profile.passwordHint = savePassword ? passwordHint.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            
            // Handle password storage in Keychain
            if let profileID = profile.id {
                if savePassword && !password.isEmpty {
                    // Store password in Keychain
                    let _ = KeychainManager.shared.storePassword(password, for: profileID)
                } else {
                    // Remove password from Keychain if not saving
                    let _ = KeychainManager.shared.deletePassword(for: profileID)
                }
            }
            
            ConnectionProfileManager.shared.updateProfile(profile)
        }
        
        dismiss()
    }
}

#Preview("New Connection") {
    NavigationStack {
        ConnectionEditView(connection: nil)
            .environment(\.managedObjectContext, ConnectionProfileManager.shared.viewContext)
    }
}

#Preview("Edit Connection") {
    NavigationStack {
        ConnectionEditView(connection: nil) // Would use a sample connection in real preview
            .environment(\.managedObjectContext, ConnectionProfileManager.shared.viewContext)
    }
}