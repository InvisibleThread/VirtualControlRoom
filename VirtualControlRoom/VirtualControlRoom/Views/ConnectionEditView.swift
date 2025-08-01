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
    @State private var savePassword = false
    @State private var password = ""
    @State private var useSSHTunnel = false
    @State private var sshHost = ""
    @State private var sshPort = "22"
    @State private var sshUsername = ""
    @State private var sshPassword = ""
    
    // Performance/Optimization Settings
    @State private var useCustomOptimization = false
    @State private var selectedEncodings: Set<String> = ["tight", "zrle", "zlib", "raw"]
    @State private var compressionLevel = 6.0
    @State private var jpegQuality = 8.0
    @State private var pixelFormat = "rgb888"
    @State private var maxFrameRate = 30.0
    
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    
    var isNewConnection: Bool {
        connection == nil
    }
    
    // Optimization preset types
    enum OptimizationPreset {
        case auto
        case highQuality
        case balanced
        case lowBandwidth
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
                    
                    SecureField("SSH Password", text: $sshPassword)
                        .textContentType(.password)
                }
            } header: {
                Text("SSH Tunnel")
            } footer: {
                if useSSHTunnel {
                    Text("VNC connection will be tunneled through SSH for enhanced security")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Toggle("Custom Optimization Settings", isOn: $useCustomOptimization.animation())
                
                if useCustomOptimization {
                    VStack(alignment: .leading, spacing: 16) {
                        // Optimization Presets
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Presets")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                                Button("High Quality") {
                                    applyPreset(.highQuality)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button("Balanced") {
                                    applyPreset(.balanced)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button("Low Bandwidth") {
                                    applyPreset(.lowBandwidth)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button("Auto") {
                                    applyPreset(.auto)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        
                        Divider()
                        
                        // Encoding Selection
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Preferred Encodings")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                if selectedEncodings.isEmpty {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                }
                            }
                            
                            Text("Select encoding methods in order of preference. TIGHT and ZRLE offer good compression.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                                ForEach(["tight", "zrle", "zlib", "raw"], id: \.self) { encoding in
                                    Button(action: {
                                        if selectedEncodings.contains(encoding) {
                                            // Prevent removing all encodings
                                            if selectedEncodings.count > 1 {
                                                selectedEncodings.remove(encoding)
                                            }
                                        } else {
                                            selectedEncodings.insert(encoding)
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: selectedEncodings.contains(encoding) ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(selectedEncodings.contains(encoding) ? .blue : .secondary)
                                            Text(encoding.uppercased())
                                                .font(.caption)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(selectedEncodings.contains(encoding) ? Color.blue.opacity(0.1) : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(selectedEncodings.contains(encoding) ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            
                            if selectedEncodings.isEmpty {
                                Text("⚠️ At least one encoding must be selected")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        
                        // Compression Level
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Compression Level")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(compressionLevel))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Text(getCompressionDescription(Int(compressionLevel)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Slider(value: $compressionLevel, in: 0...9, step: 1)
                            HStack {
                                Text("0 (None)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("9 (Max)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // JPEG Quality
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("JPEG Quality")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(jpegQuality))")
                                    .font(.subheadline)
                                    .foregroundStyle(jpegQuality < 4 ? .orange : .secondary)
                            }
                            
                            Text(getJPEGQualityDescription(Int(jpegQuality)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Slider(value: $jpegQuality, in: 0...9, step: 1)
                            HStack {
                                Text("0 (Low)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("9 (High)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if jpegQuality < 4 {
                                Text("⚠️ Very low quality may result in pixelated images")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        
                        // Max Frame Rate
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Max Frame Rate")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int(maxFrameRate)) FPS")
                                    .font(.subheadline)
                                    .foregroundStyle(maxFrameRate > 45 ? .orange : .secondary)
                            }
                            
                            Text(getFrameRateDescription(Int(maxFrameRate)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Slider(value: $maxFrameRate, in: 5...60, step: 5)
                            HStack {
                                Text("5 FPS")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("60 FPS")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if maxFrameRate > 45 {
                                Text("⚠️ High frame rates require more bandwidth and processing power")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        
                        // Pixel Format
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pixel Format")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Picker("Pixel Format", selection: $pixelFormat) {
                                Text("RGB888 (24-bit, High Quality)").tag("rgb888")
                                Text("RGB565 (16-bit, Bandwidth Optimized)").tag("rgb565")
                                Text("RGB555 (15-bit, Low Bandwidth)").tag("rgb555")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("Performance Settings")
            } footer: {
                if useCustomOptimization {
                    Text("Adjust these settings to optimize performance for your network connection. Higher compression and lower quality reduce bandwidth usage but may impact visual quality.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Automatic optimization will be used based on network conditions")
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
            
            // Load SSH password from Keychain if available
            if let profileID = connection.id {
                sshPassword = KeychainManager.shared.retrieveSSHPassword(for: profileID) ?? ""
            }
        }
        
        // Load optimization settings
        useCustomOptimization = connection.useCustomOptimization
        compressionLevel = Double(connection.compressionLevel)
        jpegQuality = Double(connection.jpegQuality)
        maxFrameRate = Double(connection.maxFrameRate)
        pixelFormat = connection.pixelFormat ?? "rgb888"
        
        // Parse preferred encodings
        if let encodingsString = connection.preferredEncodings {
            selectedEncodings = Set(encodingsString.components(separatedBy: ","))
        } else {
            selectedEncodings = ["tight", "zrle", "zlib", "raw"]
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
        
        // Validate optimization settings if custom optimization is enabled
        if useCustomOptimization {
            if selectedEncodings.isEmpty {
                validationMessage = "Please select at least one VNC encoding"
                return false
            }
            
            if compressionLevel < 0 || compressionLevel > 9 {
                validationMessage = "Compression level must be between 0 and 9"
                return false
            }
            
            if jpegQuality < 0 || jpegQuality > 9 {
                validationMessage = "JPEG quality must be between 0 and 9"
                return false
            }
            
            if maxFrameRate < 5 || maxFrameRate > 60 {
                validationMessage = "Frame rate must be between 5 and 60 FPS"
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
            connection.passwordHint = nil
            
            // Handle password storage in Keychain
            if let profileID = connection.id {
                if savePassword && !password.isEmpty {
                    // Store VNC password in Keychain
                    let _ = KeychainManager.shared.storePassword(password, for: profileID)
                } else {
                    // Remove VNC password from Keychain if not saving
                    let _ = KeychainManager.shared.deletePassword(for: profileID)
                }
                
                // Handle SSH password storage
                if useSSHTunnel && !sshPassword.isEmpty {
                    // Store SSH password in Keychain
                    let _ = KeychainManager.shared.saveSSHPassword(sshPassword, for: profileID)
                } else if !useSSHTunnel {
                    // Remove SSH password if SSH is disabled
                    let _ = KeychainManager.shared.deleteSSHPassword(for: profileID)
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
            
            // Save optimization settings
            connection.useCustomOptimization = useCustomOptimization
            connection.compressionLevel = Int32(compressionLevel)
            connection.jpegQuality = Int32(jpegQuality)
            connection.maxFrameRate = Int32(maxFrameRate)
            connection.pixelFormat = pixelFormat
            connection.preferredEncodings = selectedEncodings.sorted().joined(separator: ",")
            
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
            profile.passwordHint = nil
            
            // Save optimization settings
            profile.useCustomOptimization = useCustomOptimization
            profile.compressionLevel = Int32(compressionLevel)
            profile.jpegQuality = Int32(jpegQuality)
            profile.maxFrameRate = Int32(maxFrameRate)
            profile.pixelFormat = pixelFormat
            profile.preferredEncodings = selectedEncodings.sorted().joined(separator: ",")
            
            // Handle password storage in Keychain
            if let profileID = profile.id {
                if savePassword && !password.isEmpty {
                    // Store VNC password in Keychain
                    let _ = KeychainManager.shared.storePassword(password, for: profileID)
                } else {
                    // Remove VNC password from Keychain if not saving
                    let _ = KeychainManager.shared.deletePassword(for: profileID)
                }
                
                // Handle SSH password storage
                if useSSHTunnel && !sshPassword.isEmpty {
                    // Store SSH password in Keychain
                    let _ = KeychainManager.shared.saveSSHPassword(sshPassword, for: profileID)
                } else if !useSSHTunnel {
                    // Remove SSH password if SSH is disabled
                    let _ = KeychainManager.shared.deleteSSHPassword(for: profileID)
                }
            }
            
            ConnectionProfileManager.shared.updateProfile(profile)
        }
        
        dismiss()
    }
    
    // Apply optimization preset
    private func applyPreset(_ preset: OptimizationPreset) {
        switch preset {
        case .auto:
            // Disable custom optimization to use automatic settings
            useCustomOptimization = false
            
        case .highQuality:
            // Settings optimized for high quality video
            selectedEncodings = ["zrle", "tight", "raw"]
            compressionLevel = 2.0
            jpegQuality = 9.0
            maxFrameRate = 60.0
            pixelFormat = "rgb888"
            
        case .balanced:
            // Balanced settings for good quality and reasonable bandwidth
            selectedEncodings = ["tight", "zrle", "zlib", "raw"]
            compressionLevel = 4.0
            jpegQuality = 8.0
            maxFrameRate = 30.0
            pixelFormat = "rgb888"
            
        case .lowBandwidth:
            // Settings optimized for low bandwidth connections
            selectedEncodings = ["tight", "zlib", "raw"]
            compressionLevel = 9.0
            jpegQuality = 4.0
            maxFrameRate = 15.0
            pixelFormat = "rgb565"
        }
        
        // Show a brief feedback that preset was applied
        // Could add haptic feedback here if desired
        print("📊 Applied optimization preset: \(preset)")
    }
    
    // Helper methods for user-friendly descriptions
    private func getCompressionDescription(_ level: Int) -> String {
        switch level {
        case 0...2: return "Low compression - Better quality, higher bandwidth"
        case 3...6: return "Medium compression - Balanced quality and bandwidth"
        case 7...9: return "High compression - Lower quality, reduced bandwidth"
        default: return "Medium compression"
        }
    }
    
    private func getJPEGQualityDescription(_ quality: Int) -> String {
        switch quality {
        case 0...3: return "Low quality - Highly compressed, may appear pixelated"
        case 4...6: return "Medium quality - Good balance of quality and size"
        case 7...9: return "High quality - Better visual quality, larger file size"
        default: return "Medium quality"
        }
    }
    
    private func getFrameRateDescription(_ fps: Int) -> String {
        switch fps {
        case 5...15: return "Low frame rate - Suitable for basic desktop use"
        case 20...30: return "Standard frame rate - Good for most applications"
        case 35...45: return "High frame rate - Smooth for video and gaming"
        case 50...60: return "Very high frame rate - Maximum smoothness, high bandwidth"
        default: return "Standard frame rate"
        }
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