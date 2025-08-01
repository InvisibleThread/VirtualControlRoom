import SwiftUI

/// Console modal view displaying connection diagnostics and logs
struct ConnectionConsoleView: View {
    let connectionName: String
    let connectionID: String
    @Binding var isPresented: Bool
    
    @StateObject private var diagnosticsManager = ConnectionDiagnosticsManager.shared
    @State private var selectedCategory: DiagnosticCategory? = nil
    @State private var showingOnlyErrors = false
    @State private var autoScroll = true
    
    private var filteredLogs: [DiagnosticEntry] {
        let logs = diagnosticsManager.getLogs(for: connectionID)
        
        var filtered = logs
        
        // Filter by category if selected
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }
        
        // Filter by errors only if toggled
        if showingOnlyErrors {
            filtered = filtered.filter { $0.level == .error || $0.level == .warning }
        }
        
        return filtered
    }
    
    private var statusSummary: ConnectionStatusSummary {
        diagnosticsManager.getStatusSummary(for: connectionID)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with status summary
                statusHeader
                
                // Filter controls
                filterControls
                
                Divider()
                
                // Console logs
                consoleContent
                
                // Footer with controls
                consoleFooter
            }
            .navigationTitle("Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Clear Logs") {
                            diagnosticsManager.clearLogs(for: connectionID)
                        }
                        
                        Button("Copy All Logs") {
                            copyLogsToClipboard()
                        }
                        
                        Toggle("Auto Scroll", isOn: $autoScroll)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusSummary.status.icon)
                    .foregroundStyle(statusSummary.status.color)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(statusSummary.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(statusSummary.status.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(statusSummary.status.color)
                    
                    if let lastActivity = statusSummary.lastActivity {
                        Text(timeAgoString(from: lastActivity))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            if statusSummary.hasIssues {
                HStack {
                    if statusSummary.errorCount > 0 {
                        Label("\(statusSummary.errorCount)", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    if statusSummary.warningCount > 0 {
                        Label("\(statusSummary.warningCount)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    
                    Spacer()
                    
                    Text("\(statusSummary.totalLogs) total entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    private var filterControls: some View {
        HStack {
            // Category filter
            Menu {
                Button("All Categories") {
                    selectedCategory = nil
                }
                
                ForEach(DiagnosticCategory.allCases, id: \.self) { category in
                    Button(action: {
                        selectedCategory = category
                    }) {
                        HStack {
                            Image(systemName: category.icon)
                            Text(category.displayName)
                            
                            if selectedCategory == category {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: selectedCategory?.icon ?? "line.3.horizontal.decrease.circle")
                    Text(selectedCategory?.displayName ?? "All")
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            Spacer()
            
            // Error filter toggle
            Toggle("Errors Only", isOn: $showingOnlyErrors)
                .toggleStyle(SwitchToggleStyle(tint: .red))
                .font(.caption)
                .scaleEffect(0.8)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var consoleContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if filteredLogs.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredLogs) { entry in
                            logEntryView(entry)
                        }
                    }
                }
                .padding()
            }
            .font(.system(.caption, design: .monospaced))
            .onChange(of: filteredLogs.count) { _ in
                if autoScroll && !filteredLogs.isEmpty {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(filteredLogs.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            Text("No logs to display")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            if showingOnlyErrors {
                Text("No errors or warnings found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if selectedCategory != nil {
                Text("No logs in selected category")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connection activity will appear here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func logEntryView(_ entry: DiagnosticEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // Timestamp
            Text(entry.formattedTimestamp)
                .foregroundStyle(.secondary)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 50, alignment: .leading)
            
            // Level emoji
            Text(entry.level.emoji)
                .font(.caption)
                .frame(width: 16)
            
            // Category badge
            Text(entry.category.displayName.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 40, alignment: .center)
            
            // Message - This should take remaining space
            Text(entry.message)
                .foregroundStyle(entry.level.color)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .id(entry.id)
    }
    
    private var consoleFooter: some View {
        HStack {
            Text("\(filteredLogs.count) entries")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Clear button - prominent if there are logs
            if !filteredLogs.isEmpty {
                Button {
                    withAnimation {
                        diagnosticsManager.clearLogs(for: connectionID)
                    }
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if !autoScroll {
                Button("Scroll to Bottom") {
                    withAnimation {
                        // This will trigger the onChange above
                        autoScroll = true
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }
    
    // MARK: - Helper Methods
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
    
    private func copyLogsToClipboard() {
        let logText = filteredLogs.map { entry in
            "[\(entry.formattedTimestamp)] \(entry.level.emoji) \(entry.category.displayName.uppercased()): \(entry.message)"
        }.joined(separator: "\n")
        
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
        #else
        UIPasteboard.general.string = logText
        #endif
    }
}

#Preview {
    ConnectionConsoleView(
        connectionName: "Development Server",
        connectionID: "test-connection",
        isPresented: .constant(true)
    )
}