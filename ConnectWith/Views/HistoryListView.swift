import SwiftUI
import CoreData

struct HistoryListView: View {
    @StateObject private var historyManager = HistoryManager()
    @State private var historyGroups: [HistoryManager.HistoryGroup] = []
    @State private var selectedDeviceId: String? = nil
    @State private var dateRange: DateRange = .all
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var expandedItems: Set<UUID> = []
    @State private var showFilterOptions = false
    @State private var selectedSection: Month? = nil
    
    enum DateRange: String, CaseIterable, Identifiable {
        case all = "All Time"
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case last30Days = "Last 30 Days"
        case custom = "Custom Range"
        
        var id: String { self.rawValue }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Filter Controls
                filterView
                
                // History List Content
                if historyGroups.isEmpty {
                    emptyStateView
                } else {
                    historyListContent
                }
            }
            .navigationTitle("Edit History")
            .navigationBarItems(trailing: Button(action: {
                showFilterOptions.toggle()
            }) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .imageScale(.large)
            })
            .onAppear {
                loadHistoryData()
            }
            .onChange(of: selectedDeviceId) { _ in
                loadHistoryData()
            }
            .onChange(of: dateRange) { _ in
                updateDateRange()
                loadHistoryData()
            }
            .onChange(of: startDate) { _ in
                if dateRange == .custom {
                    loadHistoryData()
                }
            }
            .onChange(of: endDate) { _ in
                if dateRange == .custom {
                    loadHistoryData()
                }
            }
            .sheet(isPresented: $showFilterOptions) {
                FilterOptionsView(
                    selectedDeviceId: $selectedDeviceId,
                    dateRange: $dateRange,
                    startDate: $startDate,
                    endDate: $endDate,
                    familyDevices: historyManager.getAllFamilyDevices()
                )
            }
        }
    }
    
    // MARK: - Filter View
    
    var filterView: some View {
        VStack(spacing: 0) {
            // Applied Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if let deviceId = selectedDeviceId, 
                       let device = historyManager.getAllFamilyDevices().first(where: { $0.bluetoothIdentifier == deviceId }) {
                        FilterChip(label: "Device: \(device.customName ?? "Unknown")", color: .blue) {
                            selectedDeviceId = nil
                        }
                    }
                    
                    if dateRange != .all {
                        FilterChip(label: "Period: \(dateRange.rawValue)", color: .purple) {
                            dateRange = .all
                        }
                    }
                    
                    if historyGroups.isEmpty == false && (selectedDeviceId != nil || dateRange != .all) {
                        Button("Clear All") {
                            selectedDeviceId = nil
                            dateRange = .all
                        }
                        .font(.footnote)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            
            Divider()
        }
        .opacity((selectedDeviceId != nil || dateRange != .all) ? 1 : 0)
        .frame(height: (selectedDeviceId != nil || dateRange != .all) ? nil : 0)
    }
    
    // MARK: - Empty State
    
    var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            Text("No Edit History Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Edit history will appear here when changes are made to your events.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            if selectedDeviceId != nil || dateRange != .all {
                Button("Clear Filters") {
                    selectedDeviceId = nil
                    dateRange = .all
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.top, 10)
            }
        }
        .padding()
    }
    
    // MARK: - History List Content
    
    var historyListContent: some View {
        List {
            ForEach(historyGroups) { group in
                Section(header: MonthHeaderView(month: group.month, isExpanded: isExpanded(group.id)) {
                    toggleSection(group.id)
                }) {
                    if isExpanded(group.id) {
                        ForEach(group.historyItems) { item in
                            HistoryItemRow(item: item, formatChangeDescription: historyManager.formatChangeDescription(changes:))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    toggleItem(item.id)
                                }
                            
                            if expandedItems.contains(item.id) {
                                HistoryItemDetailView(item: item, formatChangeDescription: historyManager.formatChangeDescription(changes:))
                            }
                        }
                    } else {
                        Text("\(group.historyItems.count) changes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }
    
    // MARK: - Helper Functions
    
    private func loadHistoryData() {
        if let deviceId = selectedDeviceId {
            if dateRange == .custom {
                // Filter by both device and custom date range
                let records = historyManager.fetchHistoryByFamilyMember(deviceId: deviceId)
                    .filter { isDateInRange($0.timestamp, start: startDate, end: endDate) }
                let items = historyManager.createHistoryItems(from: records)
                historyGroups = historyManager.groupHistoryItemsByMonth(items: items)
            } else if dateRange == .all {
                // Filter by device only
                historyGroups = historyManager.fetchFamilyMemberHistoryGroupedByMonth(deviceId: deviceId)
            } else {
                // Filter by device and predefined date range
                let (start, end) = getDateRangeValues()
                let records = historyManager.fetchHistoryByFamilyMember(deviceId: deviceId)
                    .filter { isDateInRange($0.timestamp, start: start, end: end) }
                let items = historyManager.createHistoryItems(from: records)
                historyGroups = historyManager.groupHistoryItemsByMonth(items: items)
            }
        } else if dateRange == .custom {
            // Filter by custom date range only
            historyGroups = historyManager.fetchDateRangeHistoryGroupedByMonth(startDate: startDate, endDate: endDate)
        } else if dateRange == .all {
            // No filters
            historyGroups = historyManager.fetchAllHistoryGroupedByMonth()
        } else {
            // Filter by predefined date range
            let (start, end) = getDateRangeValues()
            historyGroups = historyManager.fetchDateRangeHistoryGroupedByMonth(startDate: start, endDate: end)
        }

        // Auto-expand if there's only one group
        if historyGroups.count == 1 {
            expandedItems.insert(historyGroups[0].id)
        }
    }
    
    private func isDateInRange(_ date: Date, start: Date, end: Date) -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: start)
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
        
        return date >= startOfDay && date <= endOfDay
    }
    
    private func updateDateRange() {
        let (start, end) = getDateRangeValues()
        startDate = start
        endDate = end
    }
    
    private func getDateRangeValues() -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        
        switch dateRange {
        case .all:
            return (Date.distantPast, Date.distantFuture)
        case .today:
            return (calendar.startOfDay(for: now), endOfDay)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return (calendar.startOfDay(for: yesterday), 
                   calendar.date(bySettingHour: 23, minute: 59, second: 59, of: yesterday) ?? yesterday)
        case .thisWeek:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            return (startOfWeek, endOfDay)
        case .thisMonth:
            let components = calendar.dateComponents([.year, .month], from: now)
            let startOfMonth = calendar.date(from: components) ?? now
            return (startOfMonth, endOfDay)
        case .last30Days:
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (calendar.startOfDay(for: thirtyDaysAgo), endOfDay)
        case .custom:
            return (startDate, endDate)
        }
    }
    
    private func isExpanded(_ id: UUID) -> Bool {
        expandedItems.contains(id)
    }
    
    private func toggleSection(_ id: UUID) {
        if expandedItems.contains(id) {
            expandedItems.remove(id)
        } else {
            expandedItems.insert(id)
        }
    }
    
    private func toggleItem(_ id: UUID) {
        if expandedItems.contains(id) {
            expandedItems.remove(id)
        } else {
            expandedItems.insert(id)
        }
    }
}

// MARK: - Supporting Views

struct MonthHeaderView: View {
    let month: Month
    let isExpanded: Bool
    let toggleAction: () -> Void
    
    var body: some View {
        Button(action: toggleAction) {
            HStack {
                Text(month.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .medium))
                    .animation(.default, value: isExpanded)
            }
        }
    }
}

struct HistoryItemRow: View {
    let item: HistoryManager.HistoryItem
    let formatChangeDescription: (HistoryManager.HistoryChanges) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(item.changeDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("By: \(item.deviceName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(item.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(item.timestamp, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct HistoryItemDetailView: View {
    let item: HistoryManager.HistoryItem
    let formatChangeDescription: (HistoryManager.HistoryChanges) -> String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Change Details")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            
            Text(formatChangeDescription(item.changes))
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
    }
}

struct FilterChip: View {
    let label: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.footnote)
                    .foregroundColor(color)
                
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(color.opacity(0.7))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(color.opacity(0.1))
            .cornerRadius(16)
        }
    }
}

struct FilterOptionsView: View {
    @Binding var selectedDeviceId: String?
    @Binding var dateRange: HistoryListView.DateRange
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Environment(\.presentationMode) var presentationMode
    
    let familyDevices: [FamilyDevice]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Filter by Family Member")) {
                    Button("All Family Members") {
                        selectedDeviceId = nil
                    }
                    .foregroundColor(.blue)
                    
                    ForEach(familyDevices, id: \.id) { device in
                        Button {
                            selectedDeviceId = device.bluetoothIdentifier
                        } label: {
                            HStack {
                                Text(device.customName ?? "Unknown Device")
                                Spacer()
                                if device.bluetoothIdentifier == selectedDeviceId {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Filter by Date")) {
                    ForEach(HistoryListView.DateRange.allCases) { range in
                        Button {
                            dateRange = range
                        } label: {
                            HStack {
                                Text(range.rawValue)
                                Spacer()
                                if dateRange == range {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                if dateRange == .custom {
                    Section(header: Text("Custom Date Range")) {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                            .onChange(of: endDate) { newValue in
                                if newValue < startDate {
                                    startDate = newValue
                                }
                            }
                    }
                }
            }
            .navigationTitle("Filter Options")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// MARK: - Preview
struct HistoryListView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryListView()
    }
}