import Foundation
import CoreData
import SwiftUI

/// A utility class to test the Core Data implementation
class CoreDataTests {
    
    /// Tests all repositories and the DataManager facade
    static func runTests() {
        print("Running Core Data Tests...")
        
        // Create an in-memory persistence controller for testing
        let persistenceController = PersistenceController(inMemory: true)
        let context = persistenceController.container.viewContext
        
        // Test repositories
        testEventRepository(context: context)
        testEditHistoryRepository(context: context)
        testFamilyDeviceRepository(context: context)
        testSyncLogRepository(context: context)
        
        // Test transactions
        testTransactionSupport(context: context)
        testBatchOperations(context: context)
        
        // Test DataManager facade
        testDataManagerFacade()
        
        print("All Core Data tests completed successfully!")
    }
    
    private static func testEventRepository(context: NSManagedObjectContext) {
        print("Testing EventRepository...")
        
        let eventRepo = EventRepository(context: context)
        
        // Test creating an event
        let event = eventRepo.createEvent(
            title: "Test Event",
            location: "Test Location",
            day: 15,
            month: .january
        )
        
        // Save the event
        try? eventRepo.save()
        
        // Test fetching the event by ID
        guard let fetchedEvent = eventRepo.fetchEventById(id: event.id) else {
            print("❌ Failed to fetch event by ID")
            return
        }
        
        // Test properties
        assert(fetchedEvent.title == "Test Event", "Event title mismatch")
        assert(fetchedEvent.location == "Test Location", "Event location mismatch")
        assert(fetchedEvent.day == 15, "Event day mismatch")
        assert(fetchedEvent.month == 1, "Event month mismatch")
        
        // Test updating the event
        let _ = eventRepo.updateEvent(
            fetchedEvent,
            title: "Updated Test Event",
            location: "Updated Location",
            day: 20
        )
        try? eventRepo.save()
        
        // Fetch again to verify update
        guard let updatedEvent = eventRepo.fetchEventById(id: event.id) else {
            print("❌ Failed to fetch updated event")
            return
        }
        
        assert(updatedEvent.title == "Updated Test Event", "Updated event title mismatch")
        
        // Test fetching events by month
        let januaryEvents = eventRepo.fetchEventsByMonth(month: .january)
        assert(januaryEvents.count == 1, "Incorrect number of January events")
        
        // Test deleting the event
        try? eventRepo.delete(updatedEvent)
        
        // Verify deletion
        let allEvents = eventRepo.fetch()
        assert(allEvents.isEmpty, "Event deletion failed")
        
        print("✅ EventRepository tests passed")
    }
    
    private static func testEditHistoryRepository(context: NSManagedObjectContext) {
        print("Testing EditHistoryRepository...")
        
        let eventRepo = EventRepository(context: context)
        let historyRepo = EditHistoryRepository(context: context)
        
        // Create an event to track history for
        let event = eventRepo.createEvent(
            title: "History Test Event",
            location: "History Location",
            day: 10,
            month: .february
        )
        
        // Create a history entry manually
        let history = EditHistory.create(in: context, for: event)
        history.recordChanges(
            previousTitle: nil,
            newTitle: "History Test Event",
            previousLocation: nil,
            newLocation: "History Location",
            previousDay: nil,
            newDay: 10
        )
        
        try? historyRepo.save()
        
        // Fetch history for the event
        let eventHistories = historyRepo.fetchHistoryForEvent(event: event)
        assert(eventHistories.count == 1, "Incorrect number of history entries")
        
        // Test updating event and auto-creating history
        let _ = eventRepo.updateEvent(
            event,
            title: "Updated Title",
            location: "Updated Location",
            day: 15
        )
        try? eventRepo.save()
        
        // Verify new history was created
        let updatedEventHistories = historyRepo.fetchHistoryForEvent(event: event)
        assert(updatedEventHistories.count == 2, "History not created on update")
        
        // Test fetching by device ID
        let deviceHistories = historyRepo.fetchHistoryByDevice(deviceId: history.deviceId)
        assert(!deviceHistories.isEmpty, "Device history fetch failed")
        
        // Test deleting history
        try? historyRepo.delete(history)
        
        // Verify deletion
        let remainingHistories = historyRepo.fetchHistoryForEvent(event: event)
        assert(remainingHistories.count == 1, "History deletion failed")
        
        print("✅ EditHistoryRepository tests passed")
    }
    
    private static func testFamilyDeviceRepository(context: NSManagedObjectContext) {
        print("Testing FamilyDeviceRepository...")
        
        let deviceRepo = FamilyDeviceRepository(context: context)
        
        // Test creating a local device
        let localDevice = deviceRepo.getOrCreateLocalDevice()
        assert(localDevice.isLocalDevice, "Local device property incorrect")
        
        // Test creating a remote device
        let remoteDevice = deviceRepo.registerDevice(
            bluetoothIdentifier: "test-bluetooth-id",
            customName: "Test Device"
        )
        try? deviceRepo.save()
        
        // Test fetching by bluetooth identifier
        guard let fetchedDevice = deviceRepo.fetchDeviceByBluetoothIdentifier(identifier: "test-bluetooth-id") else {
            print("❌ Failed to fetch device by bluetooth identifier")
            return
        }
        
        assert(fetchedDevice.customName == "Test Device", "Device name mismatch")
        
        // Test updating device name
        deviceRepo.updateDeviceName(device: fetchedDevice, name: "Updated Device Name")
        
        // Verify update
        guard let updatedDevice = deviceRepo.fetchDeviceByBluetoothIdentifier(identifier: "test-bluetooth-id") else {
            print("❌ Failed to fetch updated device")
            return
        }
        
        assert(updatedDevice.customName == "Updated Device Name", "Device name update failed")
        
        // Test updating sync timestamp
        deviceRepo.updateDeviceSyncTimestamp(device: updatedDevice)
        
        // Verify timestamp update
        guard let timestampUpdatedDevice = deviceRepo.fetchDeviceByBluetoothIdentifier(identifier: "test-bluetooth-id") else {
            print("❌ Failed to fetch timestamp updated device")
            return
        }
        
        assert(timestampUpdatedDevice.lastSyncTimestamp != nil, "Sync timestamp update failed")
        
        // Test fetching all devices
        let allDevices = deviceRepo.fetch()
        assert(allDevices.count == 2, "Incorrect device count") // Local + remote
        
        print("✅ FamilyDeviceRepository tests passed")
    }
    
    private static func testSyncLogRepository(context: NSManagedObjectContext) {
        print("Testing SyncLogRepository...")
        
        let syncLogRepo = SyncLogRepository(context: context)
        
        // Create a sync log
        let syncLog = syncLogRepo.createSyncLog(
            deviceId: "test-sync-device",
            deviceName: "Test Sync Device"
        )
        try? syncLogRepo.save()
        
        // Update the sync log
        syncLogRepo.updateSyncLog(
            syncLog,
            eventsReceived: 5,
            eventsSent: 10,
            conflicts: 2,
            resolutionMethod: "Test Method",
            details: "Test details for sync operation"
        )
        
        // Fetch logs by device
        let deviceLogs = syncLogRepo.fetchLogsByDevice(deviceId: "test-sync-device")
        assert(deviceLogs.count == 1, "Incorrect number of device logs")
        
        let log = deviceLogs.first!
        assert(log.eventsReceived == 5, "Incorrect events received count")
        assert(log.eventsSent == 10, "Incorrect events sent count")
        assert(log.conflicts == 2, "Incorrect conflicts count")
        assert(log.resolutionMethod == "Test Method", "Incorrect resolution method")
        
        // Test timeframe queries
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        
        let recentLogs = syncLogRepo.fetchLogsByTimeFrame(startDate: yesterday, endDate: tomorrow)
        assert(!recentLogs.isEmpty, "Timeframe query failed")
        
        // Test deleting logs
        try? syncLogRepo.delete(syncLog)
        
        // Verify deletion
        let remainingLogs = syncLogRepo.fetch()
        assert(remainingLogs.isEmpty, "Log deletion failed")
        
        print("✅ SyncLogRepository tests passed")
    }
    
    private static func testTransactionSupport(context: NSManagedObjectContext) {
        print("Testing transaction support...")
        
        let eventRepo = EventRepository(context: context)
        
        // Test transaction that should succeed
        do {
            let event = eventRepo.createEvent(
                title: "Transaction Test",
                location: "Test Location",
                day: 10,
                month: .february
            )
            
            let history = try eventRepo.updateEventWithTransaction(
                event,
                title: "Updated in Transaction",
                location: "New Location",
                day: 20
            )
            
            // Verify both the event and history were updated in a single transaction
            assert(event.title == "Updated in Transaction", "Transaction failed to update event")
            assert(history.newTitle == "Updated in Transaction", "Transaction failed to update history")
            assert(history.previousTitle == "Transaction Test", "Transaction failed to record previous title")
            
            // Test event deletion with history
            try eventRepo.deleteEventWithHistory(event)
            
            // Verify the event was deleted
            let fetchedEvent = eventRepo.fetchEventById(id: event.id)
            assert(fetchedEvent == nil, "Transaction failed to delete event")
            
            print("✅ Transaction support tests passed")
        } catch {
            print("❌ Transaction test failed with error: \(error)")
            assertionFailure("Transaction test failed")
        }
    }
    
    private static func testBatchOperations(context: NSManagedObjectContext) {
        print("Testing batch operations...")
        
        // Test batch event creation
        let eventRepo = EventRepository(context: context)
        let deviceRepo = FamilyDeviceRepository(context: context)
        let syncLogRepo = SyncLogRepository(context: context)
        
        do {
            // Test batch event creation
            let eventData = [
                (title: "Batch Event 1", location: "Location 1", day: 5, month: Month.march),
                (title: "Batch Event 2", location: "Location 2", day: 10, month: Month.april),
                (title: "Batch Event 3", location: "Location 3", day: 15, month: Month.may)
            ]
            
            let events = try eventRepo.batchCreateEvents(eventData)
            assert(events.count == 3, "Batch event creation failed")
            
            // Verify events were created properly
            let allEvents = eventRepo.fetch()
            assert(allEvents.count == 3, "Batch event count mismatch")
            
            // Test batch device registration
            let deviceData = [
                (bluetoothIdentifier: "device-1", customName: "Mom's iPhone", isLocalDevice: false),
                (bluetoothIdentifier: "device-2", customName: "Dad's iPhone", isLocalDevice: false),
                (bluetoothIdentifier: "device-3", customName: "Kid's iPad", isLocalDevice: false)
            ]
            
            let devices = try deviceRepo.batchRegisterDevices(deviceData)
            assert(devices.count == 3, "Batch device registration failed")
            
            // Test batch update timestamps
            try deviceRepo.batchUpdateSyncTimestamps(devices)
            
            // Verify all devices have timestamps
            let allHaveTimestamps = devices.allSatisfy { $0.lastSyncTimestamp != nil }
            assert(allHaveTimestamps, "Batch timestamp update failed")
            
            // Test batch sync log creation
            let syncLogData = [
                (deviceId: "device-1", deviceName: "Mom's iPhone", eventsReceived: 5, eventsSent: 3, conflicts: 1, resolutionMethod: "Auto merge", details: "Test details 1"),
                (deviceId: "device-2", deviceName: "Dad's iPhone", eventsReceived: 2, eventsSent: 4, conflicts: 0, resolutionMethod: "No conflicts", details: "Test details 2"),
                (deviceId: "device-3", deviceName: "Kid's iPad", eventsReceived: 3, eventsSent: 2, conflicts: 2, resolutionMethod: "Manual merge", details: "Test details 3")
            ]
            
            let logs = try syncLogRepo.batchCreateSyncLogs(syncLogData)
            assert(logs.count == 3, "Batch sync log creation failed")
            
            // Test bulk delete logs older than date
            // Create an old log
            let oldLog = syncLogRepo.createSyncLog(deviceId: "old-device", deviceName: "Old Device")
            oldLog.timestamp = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
            try syncLogRepo.save()
            
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            let deletedCount = try syncLogRepo.deleteLogsOlderThan(date: thirtyDaysAgo)
            assert(deletedCount > 0, "Batch delete logs failed")
            
            // Test bulk delete devices
            try deviceRepo.batchDeleteDevices([devices[0], devices[1]])
            
            // Verify two devices were deleted
            let remainingDevices = deviceRepo.fetch()
            assert(remainingDevices.count == 1, "Batch device deletion failed")
            
            // Test batch operation for edit history
            if let event = events.first {
                let historyRepo = EditHistoryRepository(context: context)
                let historyEntries = [
                    (previousTitle: "Original Title 1", newTitle: "New Title 1", previousLocation: "Original Location 1", newLocation: "New Location 1", previousDay: 1, newDay: 2),
                    (previousTitle: "Original Title 2", newTitle: "New Title 2", previousLocation: "Original Location 2", newLocation: "New Location 2", previousDay: 3, newDay: 4)
                ]
                
                let histories = try historyRepo.batchCreateHistory(entries: historyEntries, event: event)
                assert(histories.count == 2, "Batch history creation failed")
                
                // Test bulk delete history
                let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
                let _ = try historyRepo.deleteHistoryOlderThan(date: twoWeeksAgo)
            }
            
            print("✅ Batch operations tests passed")
        } catch {
            print("❌ Batch operations failed with error: \(error)")
            assertionFailure("Batch operations test failed")
        }
    }
    
    private static func testDataManagerFacade() {
        print("Testing DataManager facade...")
        
        // Use a fresh in-memory store for the facade test
        // This will initialize with the PersistenceController.shared instance
        // which already has sample data loaded
        let dataManager = DataManager.shared
        
        // Test event operations
        let allEvents = dataManager.getAllEvents()
        assert(!allEvents.isEmpty, "DataManager should have sample events")
        
        // Create a new event
        let newEvent = dataManager.createEvent(
            title: "Facade Test Event",
            location: "Facade Location",
            day: 5,
            month: .march
        )
        
        // Retrieve by ID
        guard let fetchedEvent = dataManager.getEvent(by: newEvent.id) else {
            print("❌ Failed to fetch event through facade")
            return
        }
        
        assert(fetchedEvent.title == "Facade Test Event", "Facade event title mismatch")
        
        // Test event retrieval by month
        let marchEvents = dataManager.getEventsByMonth(month: .march)
        assert(!marchEvents.isEmpty, "March events should not be empty")
        
        // Test getting all devices
        let allDevices = dataManager.getAllDevices()
        assert(!allDevices.isEmpty, "DataManager should have devices")
        
        // Test getting local device
        let localDevice = dataManager.getLocalDevice()
        assert(localDevice.isLocalDevice, "Local device property incorrect")
        
        // Test data protection
        let _ = dataManager.isDataProtectionActive()
        
        // Test database maintenance (no assertions, just ensure it runs)
        dataManager.performDatabaseMaintenance()
        
        print("✅ DataManager facade tests passed")
    }
}

/// SwiftUI view to run and display Core Data tests
struct CoreDataTestView: View {
    @State private var testsPassed = false
    @State private var isRunningTests = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Core Data Tests")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if isRunningTests {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text("Running tests...")
            } else if testsPassed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 60))
                Text("All tests passed!")
                    .fontWeight(.semibold)
            } else {
                Button(action: runTests) {
                    Text("Run Tests")
                        .fontWeight(.semibold)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding()
    }
    
    func runTests() {
        isRunningTests = true
        
        // Run tests on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            CoreDataTests.runTests()
            
            // Update UI on main thread
            DispatchQueue.main.async {
                isRunningTests = false
                testsPassed = true
            }
        }
    }
}

struct CoreDataTestView_Previews: PreviewProvider {
    static var previews: some View {
        CoreDataTestView()
    }
}