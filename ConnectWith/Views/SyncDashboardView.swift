import SwiftUI
import CoreData

/// A dashboard view for sync history, metrics, and activity
struct SyncDashboardView: View {
    // Reference to the sync history manager
    @ObservedObject private var syncHistoryManager = SyncHistoryManager.shared
    
    // Environment access to view context
    @Environment(\.managedObjectContext) private var viewContext
    
    // State variables
    @State private var selectedDeviceId: String?
    @State private var showAllHistory = false
    @State private var selectedTimeRange: TimeRange = .week
    @State private var showResolutionDetails = false
    @State private var selectedSyncLog: SyncLog?
    
    // Time range selection for filtering
    enum TimeRange: String, CaseIterable, Identifiable {
        case day = "24 Hours"
        case week = "7 Days"
        case month = "30 Days"
        case all = "All Time"
        
        var id: String { self.rawValue }
        
        var timeInterval: TimeInterval {
            switch self {
            case .day: return 60 * 60 * 24
            case .week: return 60 * 60 * 24 * 7
            case .month: return 60 * 60 * 24 * 30
            case .all: return 60 * 60 * 24 * 365 * 10 // Effectively "all time"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Health metrics
                Section(header: Text("Sync Health")) {
                    healthMetricsView
                }
                
                // Pending conflicts
                if !syncHistoryManager.pendingConflicts.isEmpty {
                    Section(header: Text("Pending Conflicts")) {
                        pendingConflictsView
                    }
                }
                
                // Sync history
                Section(header: Text("Recent Sync Activity")) {
                    syncHistoryFilterView
                    syncHistoryListView
                }
            }
            .navigationTitle("Sync Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    refreshButton
                }
            }
            .sheet(item: $selectedSyncLog) { log in
                syncLogDetailView(log: log)
            }
            .onAppear {
                // Refresh when view appears
                syncHistoryManager.refreshSyncData()
            }
        }
    }
    
    // MARK: - Health Metrics View
    
    private var healthMetricsView: some View {
        VStack(spacing: 20) {
            HStack {
                metricCard(
                    title: "Success Rate",
                    value: String(format: "%.1f%%", syncHistoryManager.syncHealthMetrics.successRate * 100),
                    color: syncStatusColor(success: syncHistoryManager.syncHealthMetrics.successRate > 0.8)
                )
                
                Spacer()
                
                metricCard(
                    title: "Avg. Duration",
                    value: String(format: "%.1fs", syncHistoryManager.syncHealthMetrics.averageDuration),
                    color: .blue
                )
            }
            
            HStack {
                metricCard(
                    title: "Conflicts Resolved",
                    value: "\(syncHistoryManager.syncHealthMetrics.totalConflictsResolved)",
                    color: .orange
                )
                
                Spacer()
                
                metricCard(
                    title: "Resolution Rate",
                    value: String(format: "%.1f%%", syncHistoryManager.syncHealthMetrics.conflictResolutionRate * 100),
                    color: syncStatusColor(success: syncHistoryManager.syncHealthMetrics.conflictResolutionRate > 0.9)
                )
            }
            
            VStack(alignment: .leading, spacing: 5) {
                Text("Last Sync: \(formattedDate(syncHistoryManager.syncHealthMetrics.lastSyncAttemptTime))")
                    .font(.caption)
                
                Text("Device Coverage: \(String(format: "%.1f%%", syncHistoryManager.syncHealthMetrics.deviceSyncCoverage * 100))")
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func metricCard(title: String, value: String, color: Color) -> some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(minWidth: 120, minHeight: 60)
        .padding(10)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Pending Conflicts View
    
    private var pendingConflictsView: some View {
        ForEach(syncHistoryManager.pendingConflicts) { conflict in
            VStack(alignment: .leading) {
                HStack {
                    Text(conflict.eventTitle)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Badge(text: conflict.severity.rawValue >= 3 ? "Critical" : "Needs Attention", color: conflict.severity.rawValue >= 3 ? .red : .orange)
                }
                
                Text("Device: \(conflict.deviceName)")
                    .font(.caption)
                
                Text("Fields: \(conflict.affectedFields.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(conflict.conflictDate, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if conflict.requiresManualResolution {
                    Button(action: {
                        // This would navigate to conflict resolution UI
                    }) {
                        Text("Resolve Now")
                            .font(.footnote)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Sync History Filter View
    
    private var syncHistoryFilterView: some View {
        HStack {
            Picker("Time Range", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedTimeRange) { _ in
                // Update sync history when time range changes
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Sync History List View
    
    private var syncHistoryListView: some View {
        ForEach(filteredSyncLogs) { log in
            syncLogRow(log: log)
                .onTapGesture {
                    selectedSyncLog = log
                }
        }
    }
    
    private func syncLogRow(log: SyncLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.deviceName ?? "Unknown Device")
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Badge(
                    text: syncStatusText(from: log),
                    color: syncStatusColor(from: log)
                )
            }
            
            HStack {
                Label("\(log.eventsReceived) received", systemImage: "arrow.down")
                    .font(.caption)
                
                Spacer()
                
                Label("\(log.eventsSent) sent", systemImage: "arrow.up")
                    .font(.caption)
                
                Spacer()
                
                if log.conflicts > 0 {
                    Label("\(log.conflicts) conflicts", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Text(log.timestamp ?? Date(), style: .date)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Sync Log Detail View
    
    private func syncLogDetailView(log: SyncLog) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sync with \(log.deviceName ?? "Unknown Device")")
                            .font(.headline)
                        
                        Text(log.timestamp ?? Date(), style: .date)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Stats
                    HStack(spacing: 20) {
                        VStack {
                            Text("\(log.eventsReceived)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Received")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(log.eventsSent)")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("Sent")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack {
                            Text("\(log.conflicts)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(log.conflicts > 0 ? .orange : .primary)
                            Text("Conflicts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Details
                    if let details = log.details {
                        Text("Details")
                            .font(.headline)
                            .padding(.top)
                        
                        Text(details)
                            .font(.body)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Sync Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        selectedSyncLog = nil
                    }
                }
            }
        }
    }
    
    // MARK: - Toolbar Items
    
    private var refreshButton: some View {
        Button(action: {
            syncHistoryManager.refreshSyncData()
        }) {
            Image(systemName: "arrow.clockwise")
        }
    }
    
    // MARK: - Helper Methods
    
    private var filteredSyncLogs: [SyncLog] {
        let logs = syncHistoryManager.recentSyncActivity
        
        // Filter by time range
        if selectedTimeRange != .all {
            let cutoffDate = Date().addingTimeInterval(-selectedTimeRange.timeInterval)
            return logs.filter { log in
                guard let timestamp = log.timestamp else { return false }
                return timestamp > cutoffDate
            }
        }
        
        return logs
    }
    
    private func syncStatusText(from log: SyncLog) -> String {
        if let details = log.details {
            if details.contains("Status: Success") {
                return "Success"
            } else if details.contains("Status: Failed") {
                return "Failed"
            }
        }
        
        // Default to success for backward compatibility with logs before status field was added
        return "Success"
    }
    
    private func syncStatusColor(from log: SyncLog) -> Color {
        return syncStatusColor(success: syncStatusText(from: log) == "Success")
    }
    
    private func syncStatusColor(success: Bool) -> Color {
        return success ? .green : .red
    }
    
    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else { return "Never" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Badge View

struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

// MARK: - Preview

struct SyncDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        SyncDashboardView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}

// MARK: - Extensions to make SyncLog identifiable for SwiftUI

extension SyncLog: Identifiable {
    public var id: UUID? {
        self.id
    }
}

extension ConflictDetector.ConflictSeverity: Comparable {
    public static func < (lhs: ConflictDetector.ConflictSeverity, rhs: ConflictDetector.ConflictSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}