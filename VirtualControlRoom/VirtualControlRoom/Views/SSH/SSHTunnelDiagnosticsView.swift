import SwiftUI

/// View for displaying SSH tunnel diagnostics and troubleshooting information
struct SSHTunnelDiagnosticsView: View {
    let connectionName: String
    let error: String
    let suggestions: [String]
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange)
                
                Text("SSH Tunnel Connection Issue")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(connectionName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Error details
            VStack(alignment: .leading, spacing: 12) {
                Label("Error", systemImage: "xmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                
                Text(error)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
            
            // Suggestions
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Troubleshooting Suggestions", systemImage: "lightbulb.fill")
                        .font(.headline)
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(suggestion)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
            }
            
            // Common issues
            DisclosureGroup("Common SSH Tunnel Issues") {
                VStack(alignment: .leading, spacing: 8) {
                    CommonIssueRow(
                        icon: "network.slash",
                        title: "No route to host",
                        description: "The SSH server cannot reach the target. Check if the hostname is correct from the bastion's perspective."
                    )
                    
                    CommonIssueRow(
                        icon: "lock.shield",
                        title: "Firewall blocking",
                        description: "Internal firewall rules may prevent the bastion from reaching the target port."
                    )
                    
                    CommonIssueRow(
                        icon: "server.rack",
                        title: "Service not running",
                        description: "The VNC service might not be running on the target host or port."
                    )
                    
                    CommonIssueRow(
                        icon: "globe",
                        title: "DNS resolution",
                        description: "The bastion might need to use a different hostname or IP address to reach the target."
                    )
                }
                .padding(.top, 8)
            }
            .tint(.blue)
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 15) {
                Button("Edit Connection") {
                    // TODO: Navigate to connection edit view
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Dismiss") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 500, height: 600)
    }
}

struct CommonIssueRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

// Preview
#Preview {
    SSHTunnelDiagnosticsView(
        connectionName: "access-ctrl1.als.lbl.gov → appsdev2.als.lbl.gov:5900",
        error: "SSH channel setup rejected: No route to host",
        suggestions: [
            "Verify the target hostname 'appsdev2.als.lbl.gov' is accessible from the bastion host",
            "Try using the IP address instead of hostname",
            "Check if port 5900 is open on the target host",
            "Contact your system administrator to verify network routing"
        ]
    )
}