import XCTest
import CoreData
@testable import ConnectWith

/// Tests for the HistoryManager class
class HistoryManagerTests: XCTestCase {
    
    // Test instances
    var historyManager: HistoryManager!
    var persistenceController: PersistenceController!
    var viewContext: NSManagedObjectContext!
    
    // Sample data
    var sampleEvent: Event!
    var sampleHistories: [EditHistory] = []
    var sampleDevice: FamilyDevice!
    
    override func setUp() {
        super.setUp()
        
        // Create an in-memory persistence controller for testing
        persistenceController = PersistenceController(inMemory: true)
        viewContext = persistenceController.container.viewContext
        
        // Create the history manager
        historyManager = HistoryManager()
        
        // Create test data
        createTestData()
    }
    
    override func tearDown() {
        // Clean up
        sampleEvent = nil
        sampleHistories = []
        sampleDevice = nil
        historyManager = nil
        viewContext = nil
        persistenceController = nil
        
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Creates test data for the tests
    private func createTestData() {
        // Create a sample event
        sampleEvent = Event.create(
            in: viewContext,
            title: "Test Event",
            location: "Test Location",
            day: 15,
            month: .march
        )
        
        // Create a sample device
        sampleDevice = FamilyDevice.create(
            in: viewContext,
            bluetoothIdentifier: "test-device-id",
            customName: "Test Device",
            isLocalDevice: true
        )
        
        // Create a series of edit history entries for the event
        let history1 = EditHistory.create(in: viewContext, for: sampleEvent)
        history1.deviceId = sampleDevice.bluetoothIdentifier
        history1.deviceName = sampleDevice.customName
        history1.recordChanges(
            previousTitle: nil,
            newTitle: "Test Event",
            previousLocation: nil,
            newLocation: "Test Location",
            previousDay: nil,
            newDay: 15
        )
        history1.timestamp = Date().addingTimeInterval(-86400 * 5) // 5 days ago
        
        let history2 = EditHistory.create(in: viewContext, for: sampleEvent)
        history2.deviceId = sampleDevice.bluetoothIdentifier
        history2.deviceName = sampleDevice.customName
        history2.recordChanges(
            previousTitle: "Test Event",
            newTitle: "Updated Event",
            previousLocation: "Test Location",
            newLocation: "Test Location",
            previousDay: 15,
            newDay: 15
        )
        history2.timestamp = Date().addingTimeInterval(-86400 * 3) // 3 days ago
        
        let history3 = EditHistory.create(in: viewContext, for: sampleEvent)
        history3.deviceId = sampleDevice.bluetoothIdentifier
        history3.deviceName = sampleDevice.customName
        history3.recordChanges(
            previousTitle: "Updated Event",
            newTitle: "Updated Event",
            previousLocation: "Test Location",
            newLocation: "New Location",
            previousDay: 15,
            newDay: 20
        )
        history3.timestamp = Date().addingTimeInterval(-86400) // 1 day ago
        
        sampleHistories = [history1, history2, history3]
        
        // Save the context
        try? viewContext.save()
    }
    
    // MARK: - Tests
    
    /// Tests fetching all history records
    func testFetchAllHistory() {
        // Execute
        let histories = historyManager.fetchAllHistory()
        
        // Verify
        XCTAssertGreaterThanOrEqual(histories.count, 3, "Should fetch at least 3 history records")
        
        // Check sorting (newest first)
        if histories.count >= 2 {
            XCTAssertGreaterThan(histories[0].timestamp, histories[1].timestamp, "Histories should be sorted by timestamp (newest first)")
        }
    }
    
    /// Tests fetching history for a specific event
    func testFetchHistoryForEvent() {
        // Execute
        let histories = historyManager.fetchHistoryForEvent(eventId: sampleEvent.id)
        
        // Verify
        XCTAssertEqual(histories.count, 3, "Should fetch 3 history records for the sample event")
    }
    
    /// Tests fetching history by family member (device)
    func testFetchHistoryByFamilyMember() {
        // Execute
        let histories = historyManager.fetchHistoryByFamilyMember(deviceId: sampleDevice.bluetoothIdentifier)
        
        // Verify
        XCTAssertEqual(histories.count, 3, "Should fetch 3 history records for the sample device")
    }
    
    /// Tests creating history items from history records
    func testCreateHistoryItems() {
        // Execute
        let historyItems = historyManager.createHistoryItems(from: sampleHistories)
        
        // Verify
        XCTAssertEqual(historyItems.count, 3, "Should create 3 history items")
        
        // Check first item (created event)
        XCTAssertEqual(historyItems[0].deviceName, "Test Device")
        XCTAssertEqual(historyItems[0].month, .march)
        XCTAssertTrue(historyItems[0].changeDescription.contains("title"), "Change description should mention title change")
        
        // Check last item (updated location and day)
        XCTAssertTrue(historyItems[2].changes.locationChanged, "Location should be marked as changed")
        XCTAssertTrue(historyItems[2].changes.dayChanged, "Day should be marked as changed")
        XCTAssertFalse(historyItems[2].changes.titleChanged, "Title should not be marked as changed")
    }
    
    /// Tests grouping history items by month
    func testGroupHistoryItemsByMonth() {
        // Create some additional history items for different months
        let aprilEvent = Event.create(
            in: viewContext,
            title: "April Event",
            location: "April Location",
            day: 10,
            month: .april
        )
        
        let aprilHistory = EditHistory.create(in: viewContext, for: aprilEvent)
        aprilHistory.deviceId = sampleDevice.bluetoothIdentifier
        aprilHistory.deviceName = sampleDevice.customName
        aprilHistory.recordChanges(
            previousTitle: nil,
            newTitle: "April Event",
            previousLocation: nil,
            newLocation: "April Location",
            previousDay: nil,
            newDay: 10
        )
        
        try? viewContext.save()
        
        // Execute
        let allHistories = historyManager.fetchAllHistory()
        let historyItems = historyManager.createHistoryItems(from: allHistories)
        let groupedItems = historyManager.groupHistoryItemsByMonth(items: historyItems)
        
        // Verify
        XCTAssertGreaterThanOrEqual(groupedItems.count, 2, "Should have at least 2 month groups")
        
        // Check that months are sorted correctly
        if groupedItems.count >= 2 {
            XCTAssertLessThan(groupedItems[0].month.monthNumber, groupedItems[1].month.monthNumber, "Months should be sorted in ascending order")
        }
        
        // Find march group and verify its contents
        let marchGroup = groupedItems.first { $0.month == .march }
        XCTAssertNotNil(marchGroup, "Should have a March group")
        XCTAssertEqual(marchGroup?.historyItems.count, 3, "March group should have 3 history items")
        
        // Verify items within group are sorted by timestamp (newest first)
        if let items = marchGroup?.historyItems, items.count >= 2 {
            XCTAssertGreaterThan(items[0].timestamp, items[1].timestamp, "Items within a group should be sorted by timestamp (newest first)")
        }
    }
    
    /// Tests formatting change descriptions
    func testFormatChangeDescription() {
        // Create test data
        let changes = HistoryManager.HistoryChanges(
            previousTitle: "Old Title",
            newTitle: "New Title",
            previousLocation: "Old Location",
            newLocation: "New Location",
            previousDay: 15,
            newDay: 20
        )
        
        // Execute
        let description = historyManager.formatChangeDescription(changes: changes)
        
        // Verify
        XCTAssertTrue(description.contains("Title: \"Old Title\" → \"New Title\""), "Description should contain title change")
        XCTAssertTrue(description.contains("Location: \"Old Location\" → \"New Location\""), "Description should contain location change")
        XCTAssertTrue(description.contains("Day: 15 → 20"), "Description should contain day change")
    }
    
    /// Tests combined fetch and group operations
    func testFetchAllHistoryGroupedByMonth() {
        // Execute
        let groupedHistory = historyManager.fetchAllHistoryGroupedByMonth()
        
        // Verify
        XCTAssertGreaterThanOrEqual(groupedHistory.count, 2, "Should have at least 2 month groups")
        
        // Check march group specifically
        let marchGroup = groupedHistory.first { $0.month == .march }
        XCTAssertNotNil(marchGroup, "Should have a March group")
        XCTAssertEqual(marchGroup?.historyItems.count, 3, "March group should have 3 history items")
    }
}