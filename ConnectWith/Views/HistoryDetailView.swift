import SwiftUI

struct HistoryDetailView: View {
    let historyItem: HistoryManager.HistoryItem
    let event: Event?
    @StateObject private var historyManager = HistoryManager()
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with event info
                    eventHeaderView
                    
                    // Edit details
                    editDetailsView
                    
                    // Before and After comparison
                    changeComparisonView
                    
                    // Additional metadata
                    metadataView
                }
                .padding()
            }
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: closeButton)
        }
    }
    
    // MARK: - View Components
    
    private var closeButton: some View {
        Button("Done") {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private var eventHeaderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let event = event {
                Text(event.month.rawValue)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(event.month.color)
                
                Text(event.title ?? "Untitled Event")
                    .font(.headline)
            } else {
                Text(historyItem.month.rawValue)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(historyItem.month.color)
                
                Text("This event may have been deleted")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var editDetailsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Information")
                .font(.headline)
            
            HStack(alignment: .top) {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edited by")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(historyItem.deviceName)
                        .font(.body)
                }
            }
            
            HStack(alignment: .top) {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Date and time")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(formattedDate(historyItem.timestamp))
                        .font(.body)
                }
            }
            
            if isConflictResolution {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Conflict Resolution")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text("This edit was automatically merged from multiple changes")
                            .font(.body)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var changeComparisonView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Changes Made")
                .font(.headline)
            
            if historyItem.changes.titleChanged {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Event Title:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 0) {
                        VStack(alignment: .leading) {
                            Text("Before")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            Text(historyItem.changes.previousTitle ?? "None")
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                        
                        VStack(alignment: .leading) {
                            Text("After")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            Text(historyItem.changes.newTitle ?? "None")
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                Divider()
            }
            
            if historyItem.changes.locationChanged {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Event Location:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 0) {
                        VStack(alignment: .leading) {
                            Text("Before")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            Text(historyItem.changes.previousLocation ?? "None")
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                        
                        VStack(alignment: .leading) {
                            Text("After")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            Text(historyItem.changes.newLocation ?? "None")
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                Divider()
            }
            
            if historyItem.changes.dayChanged {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Event Date:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 0) {
                        VStack(alignment: .leading) {
                            Text("Before")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            Text(formattedDay(historyItem.changes.previousDay))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                        
                        VStack(alignment: .leading) {
                            Text("After")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            Text(formattedDay(historyItem.changes.newDay))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            
            if !historyItem.changes.titleChanged && !historyItem.changes.locationChanged && !historyItem.changes.dayChanged {
                Text("No visible changes detected in this edit.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private var metadataView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Technical Information")
                .font(.headline)
            
            HStack {
                Text("Edit ID:")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(historyItem.id.uuidString)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            HStack {
                Text("Event ID:")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(historyItem.eventId.uuidString)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            if let previousHistoryItem = getPreviousHistoryItem() {
                NavigationLink(destination: HistoryDetailView(historyItem: previousHistoryItem, event: event)) {
                    Label("Previous Edit", systemImage: "arrow.left.circle")
                }
            }
            
            if let nextHistoryItem = getNextHistoryItem() {
                NavigationLink(destination: HistoryDetailView(historyItem: nextHistoryItem, event: event)) {
                    Label("Next Edit", systemImage: "arrow.right.circle")
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    // MARK: - Helper Methods
    
    private var isConflictResolution: Bool {
        // This is a placeholder logic - in a real app, you would have
        // a specific flag or metadata in the EditHistory entity to indicate conflict resolution
        return historyItem.changeDescription.contains("merged") || historyItem.changeDescription.contains("conflict")
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formattedDay(_ day: Int?) -> String {
        guard let day = day else { return "Not set" }
        
        if day == 0 {
            return "Not set"
        }
        
        // Create a date formatter to get the proper ordinal suffix (e.g., "1st", "2nd", etc.)
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .ordinal
        return numberFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }
    
    private func getPreviousHistoryItem() -> HistoryManager.HistoryItem? {
        // In a real app, you would implement logic to fetch the previous history item
        // based on timestamp for the same event
        return nil
    }
    
    private func getNextHistoryItem() -> HistoryManager.HistoryItem? {
        // In a real app, you would implement logic to fetch the next history item
        // based on timestamp for the same event
        return nil
    }
}

// MARK: - Preview Provider
struct HistoryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        // Create sample data for preview
        let historyManager = HistoryManager()
        let changes = HistoryManager.HistoryChanges(
            previousTitle: "Family Dinner",
            newTitle: "Monthly Family Dinner",
            previousLocation: "Home",
            newLocation: "Mom's House",
            previousDay: 15,
            newDay: 20
        )
        
        let historyItem = HistoryManager.HistoryItem(
            id: UUID(),
            eventId: UUID(),
            deviceName: "Dad's Phone",
            timestamp: Date(),
            month: .july,
            changeDescription: "Changed title, location and date",
            changes: changes
        )
        
        return HistoryDetailView(historyItem: historyItem, event: nil)
    }
}