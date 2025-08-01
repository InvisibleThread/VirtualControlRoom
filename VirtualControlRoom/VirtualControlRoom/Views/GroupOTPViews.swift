import SwiftUI

// GroupOTPPromptView removed - now reusing OTPPromptView from connections

struct GroupLaunchStatusView: View {
    let group: ConnectionGroup
    @StateObject private var otpManager = GroupOTPManager.shared
    
    private var connections: [ConnectionProfile] {
        return group.connections
    }
    
    private var statusText: String {
        switch otpManager.groupLaunchState {
        case .idle:
            return ""
        case .preparing:
            return "Preparing connections..."
        case .awaitingOTP:
            return "Waiting for authentication..."
        case .connecting:
            return "Connecting to servers..."
        case .completed(let result):
            switch result {
            case .allSucceeded:
                return "All connections successful!"
            case .partialSuccess(let connected, let failed):
                return "\(connected) connected, \(failed) failed"
            case .allFailed:
                return "All connections failed"
            }
        }
    }
    
    private var statusColor: Color {
        switch otpManager.groupLaunchState {
        case .completed(let result):
            switch result {
            case .allSucceeded:
                return .green
            case .partialSuccess:
                return .orange
            case .allFailed:
                return .red
            }
        default:
            return .blue
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    if case .connecting = otpManager.groupLaunchState {
                        ProgressView()
                            .scaleEffect(1.2)
                    } else if case .completed(let _) = otpManager.groupLaunchState {
                        Image(systemName: statusIcon)
                            .font(.system(size: 32))
                            .foregroundColor(statusColor)
                    }
                    
                    Text(statusText)
                        .font(.headline)
                        .foregroundColor(statusColor)
                        .multilineTextAlignment(.center)
                }
                
                if case .connecting = otpManager.groupLaunchState {
                    VStack(spacing: 8) {
                        ForEach(connections, id: \.id) { connection in
                            if let connectionId = connection.id?.uuidString,
                               let state = otpManager.connectionStates[connectionId] {
                                HStack {
                                    Text(connection.displayName)
                                        .font(.caption)
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 4) {
                                        if case .connecting = state {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                        } else if case .connected = state {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                        } else if case .failed = state {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                        }
                                        
                                        Text(state.displayText)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .frame(maxWidth: 300)
                }
                
                if case .completed = otpManager.groupLaunchState {
                    Button("Dismiss") {
                        otpManager.resetLaunchState()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 8)
            .frame(maxWidth: 400)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.3))
        .ignoresSafeArea()
    }
    
    private var statusIcon: String {
        switch otpManager.groupLaunchState {
        case .completed(let result):
            switch result {
            case .allSucceeded:
                return "checkmark.circle.fill"
            case .partialSuccess:
                return "exclamationmark.triangle.fill"
            case .allFailed:
                return "xmark.circle.fill"
            }
        default:
            return "circle"
        }
    }
}

#Preview("OTP Prompt") {
    // Preview removed - now using shared OTPPromptView
    Text("Using shared OTPPromptView")
}

#Preview("Launch Status") {
    // Create a sample group for preview
    let context = ConnectionProfileManager.shared.viewContext
    let sampleGroup = ConnectionGroup(context: context)
    sampleGroup.name = "Development Servers"
    sampleGroup.id = UUID()
    
    return GroupLaunchStatusView(group: sampleGroup)
}