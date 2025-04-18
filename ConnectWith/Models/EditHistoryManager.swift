import Foundation
import CoreData
import SwiftUI

/// Manages the retrieval and organization of edit history records
class HistoryManager {
    private let dataManager = DataManager.shared
    
    // MARK: - History Item Structs
    
    /// Represents a grouped set of history items by month
    struct HistoryGroup: Identifiable {
        let id = UUID()
        let month: Month
        let historyItems: [HistoryItem]
    }
    
    /// Represents a single edit history item for display in the UI
    struct HistoryItem: Identifiable {
        let id: UUID
        let eventId: UUID
        let deviceName: String
        let timestamp: Date
        let month: Month
        let changeDescription: String
        let changes: HistoryChanges
        
        init(from history: EditHistory) {
            self.id = history.id
            self.eventId = history.event?.id ?? UUID()
            self.deviceName = history.deviceName ?? "Unknown Device"
            self.timestamp = history.timestamp
            self.month = Month.from(monthNumber: history.event?.month ?? 1) ?? .january
            
            // Construct change description
            let changeTypes = [
                history.previousTitle != history.newTitle ? "title" : nil,
                history.previousLocation != history.newLocation ? "location" : nil,
                history.previousDay != history.newDay ? "date" : nil
            ].compactMap { $0 }
            
            if changeTypes.isEmpty {
                self.changeDescription = "No changes"
            } else if changeTypes.count == 1 {
                self.changeDescription = "Changed \(changeTypes[0])"
            } else {
                let lastChange = changeTypes.last!
                let otherChanges = changeTypes.dropLast().joined(separator: ", ")
                self.changeDescription = "Changed \(otherChanges) and \(lastChange)"
            }
            
            // Populate changes
            self.changes = HistoryChanges(
                previousTitle: history.previousTitle,
                newTitle: history.newTitle,
                previousLocation: history.previousLocation,
                newLocation: history.newLocation,
                previousDay: history.previousDay != 0 ? Int(history.previousDay) : nil,
                newDay: history.newDay != 0 ? Int(history.newDay) : nil
            )
        }
    }
    
    /// Holds the specific changes made in a history item
    struct HistoryChanges {
        let previousTitle: String?
        let newTitle: String?
        let previousLocation: String?
        let newLocation: String?
        let previousDay: Int?
        let newDay: Int?
        
        var titleChanged: Bool {
            return previousTitle != newTitle && newTitle != nil
        }
        
        var locationChanged: Bool {
            return previousLocation != newLocation && newLocation != nil
        }
        
        var dayChanged: Bool {
            return previousDay != newDay && newDay != nil
        }
    }
    
    // MARK: - History Data Management
    
    /// Fetches all history records sorted by date (newest first)
    func fetchAllHistory() -> [EditHistory] {
        let sortDescriptor = NSSortDescriptor(key: "timestamp", ascending: false)
        let editHistoryRepository = EditHistoryRepository(context: PersistenceController.shared.container.viewContext)
        return editHistoryRepository.fetch(predicate: nil, sortDescriptors: [sortDescriptor])
    }
    
    /// Fetches history records for a specific event
    func fetchHistoryForEvent(eventId: UUID) -> [EditHistory] {
        guard let event = dataManager.getEvent(by: eventId) else { return [] }
        let editHistoryRepository = EditHistoryRepository(context: PersistenceController.shared.container.viewContext)
        return editHistoryRepository.fetchHistoryForEvent(event: event)
    }
    
    /// Fetches history records by family member (device)
    func fetchHistoryByFamilyMember(deviceId: String) -> [EditHistory] {
        let editHistoryRepository = EditHistoryRepository(context: PersistenceController.shared.container.viewContext)
        return editHistoryRepository.fetchHistoryByDevice(deviceId: deviceId)
    }
    
    /// Fetches history records within a specific date range
    func fetchHistoryByDateRange(startDate: Date, endDate: Date) -> [EditHistory] {
        let editHistoryRepository = EditHistoryRepository(context: PersistenceController.shared.container.viewContext)
        return editHistoryRepository.fetchHistoryByTimeFrame(startDate: startDate, endDate: endDate)
    }
    
    // MARK: - Data Transformation for UI
    
    /// Converts EditHistory entities to HistoryItem models
    func createHistoryItems(from historyRecords: [EditHistory]) -> [HistoryItem] {
        return historyRecords.map { HistoryItem(from: $0) }
    }
    
    /// Groups history items by month
    func groupHistoryItemsByMonth(items: [HistoryItem]) -> [HistoryGroup] {
        // Group items by month
        let groupedItems = Dictionary(grouping: items) { $0.month }
        
        // Transform into array of HistoryGroups sorted by month
        return groupedItems.map { (month, items) in
            HistoryGroup(month: month, historyItems: items.sorted(by: { $0.timestamp > $1.timestamp }))
        }.sorted(by: { $0.month.monthNumber < $1.month.monthNumber })
    }
    
    // MARK: - Combined Operations
    
    /// Fetches and groups all history records
    func fetchAllHistoryGroupedByMonth() -> [HistoryGroup] {
        let historyRecords = fetchAllHistory()
        let historyItems = createHistoryItems(from: historyRecords)
        return groupHistoryItemsByMonth(items: historyItems)
    }
    
    /// Fetches and groups history records for a specific event
    func fetchEventHistoryGroupedByMonth(eventId: UUID) -> [HistoryGroup] {
        let historyRecords = fetchHistoryForEvent(eventId: eventId)
        let historyItems = createHistoryItems(from: historyRecords)
        return groupHistoryItemsByMonth(items: historyItems)
    }
    
    /// Fetches and groups history records for a specific family member
    func fetchFamilyMemberHistoryGroupedByMonth(deviceId: String) -> [HistoryGroup] {
        let historyRecords = fetchHistoryByFamilyMember(deviceId: deviceId)
        let historyItems = createHistoryItems(from: historyRecords)
        return groupHistoryItemsByMonth(items: historyItems)
    }
    
    /// Fetches and groups history records for a specific date range
    func fetchDateRangeHistoryGroupedByMonth(startDate: Date, endDate: Date) -> [HistoryGroup] {
        let historyRecords = fetchHistoryByDateRange(startDate: startDate, endDate: endDate)
        let historyItems = createHistoryItems(from: historyRecords)
        return groupHistoryItemsByMonth(items: historyItems)
    }
    
    // MARK: - Helper Methods
    
    /// Gets all family devices for filtering
    func getAllFamilyDevices() -> [FamilyDevice] {
        return dataManager.getAllDevices()
    }
    
    /// Gets the event associated with a history item
    func getEvent(for historyItem: HistoryItem) -> Event? {
        return dataManager.getEvent(by: historyItem.eventId)
    }
    
    /// Creates a formatted description of what changed
    func formatChangeDescription(changes: HistoryChanges) -> String {
        var changeDescriptions: [String] = []
        
        if changes.titleChanged {
            changeDescriptions.append("Title: \"\(changes.previousTitle ?? "None")\" → \"\(changes.newTitle!)\"")
        }
        
        if changes.locationChanged {
            changeDescriptions.append("Location: \"\(changes.previousLocation ?? "None")\" → \"\(changes.newLocation!)\"")
        }
        
        if changes.dayChanged {
            let previousDayString = changes.previousDay != nil ? "\(changes.previousDay!)" : "None"
            changeDescriptions.append("Day: \(previousDayString) → \(changes.newDay!)")
        }
        
        return changeDescriptions.joined(separator: "\n")
    }
}

// MARK: - Month Enum Extension for Int
extension Month {
    /// Initializes a Month enum from a month number (1-12)
    static func from(monthNumber: Int) -> Month? {
        return from(monthNumber: Int16(monthNumber))
    }
}