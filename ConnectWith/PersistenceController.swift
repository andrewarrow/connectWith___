import CoreData
import UIKit

class PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    private let isPreview: Bool
    
    // Create a background context for operations that should not block the UI
    lazy var backgroundContext: NSManagedObjectContext = {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()
    
    // Initialize with option for preview data
    init(inMemory: Bool = false) {
        self.isPreview = inMemory
        container = NSPersistentContainer(name: "DeviceModel")
        
        if inMemory {
            // Use in-memory store for previews and tests
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure data protection - Complete protection (no access when device is locked)
            guard let storeDescription = container.persistentStoreDescriptions.first else {
                fatalError("Failed to retrieve store description")
            }
            
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            storeDescription.setOption(FileProtectionType.complete as NSString, forKey: NSPersistentStoreFileProtectionKey)
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                // In a production app, you might want to report this to an analytics service
                // rather than crashing the app
                fatalError("Error loading Core Data stores: \(error.localizedDescription)")
            }
            
            // Verify data protection is enabled
            if !inMemory {
                self.verifyDataProtection()
            }
        }
        
        // Configure view context
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Set up to merge changes from background contexts automatically
        NotificationCenter.default.addObserver(
            self, selector: #selector(managedObjectContextDidSave),
            name: .NSManagedObjectContextDidSave, object: nil
        )
        
        // If in preview mode, load sample data
        if inMemory {
            self.createSampleData()
        }
    }
    
    // MARK: - Context Management
    
    @objc private func managedObjectContextDidSave(notification: Notification) {
        // Only merge changes from other contexts into the view context
        let sender = notification.object as! NSManagedObjectContext
        if sender !== container.viewContext && 
            sender.persistentStoreCoordinator == container.persistentStoreCoordinator {
            container.viewContext.perform {
                self.container.viewContext.mergeChanges(fromContextDidSave: notification)
            }
        }
    }
    
    // MARK: - Data Operations
    
    /// Saves changes in the view context
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // In a production app, you would handle this error more gracefully
                print("Error saving view context: \(error)")
                
                // Provide more detailed error information in debug builds
                #if DEBUG
                let nsError = error as NSError
                print("Core Data save error: \(nsError), \(nsError.userInfo)")
                #endif
            }
        }
    }
    
    /// Performs work on a background context and saves
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            block(context)
            
            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    print("Background context save error: \(error)")
                }
            }
        }
    }
    
    /// Deletes all data from the persistent store
    func deleteAllData() {
        performBackgroundTask { context in
            // Delete all CoreData entities
            let entityNames = self.container.managedObjectModel.entities.compactMap { $0.name }
            
            for entityName in entityNames {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                batchDeleteRequest.resultType = .resultTypeObjectIDs
                
                do {
                    let batchResult = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
                    if let objectIDs = batchResult?.result as? [NSManagedObjectID] {
                        // Update view context with deletions
                        let changes = [NSDeletedObjectsKey: objectIDs]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.container.viewContext])
                    }
                } catch {
                    print("Error deleting \(entityName) entities: \(error)")
                }
            }
        }
    }
    
    // MARK: - Data Protection
    
    /// Verifies that data protection is properly enabled on the persistent store
    private func verifyDataProtection() {
        guard let storeURL = container.persistentStoreCoordinator.persistentStores.first?.url else {
            print("Warning: Could not determine store URL for data protection verification")
            return
        }
        
        do {
            let resourceValues = try storeURL.resourceValues(forKeys: [.fileProtectionKey])
            if let protection = resourceValues.fileProtection {
                print("Core Data store protection level: \(protection)")
                
                if protection != .complete {
                    print("Warning: Data protection is not set to Complete")
                }
            } else {
                print("Warning: Could not determine file protection level")
            }
        } catch {
            print("Error checking data protection: \(error)")
        }
    }
    
    /// Check if data protection is active
    func isDataProtectionActive() -> Bool {
        guard let storeURL = container.persistentStoreCoordinator.persistentStores.first?.url else {
            return false
        }
        
        do {
            let resourceValues = try storeURL.resourceValues(forKeys: [.fileProtectionKey])
            if let protection = resourceValues.fileProtection {
                return protection == .complete
            }
            return false
        } catch {
            print("Error checking data protection: \(error)")
            return false
        }
    }
    
    // MARK: - Sample Data
    
    /// Creates sample data for previews
    private func createSampleData() {
        let context = container.viewContext
        
        // Create sample events for each month
        for month in Month.allCases {
            let event = Event.create(
                in: context,
                title: "Sample \(month.rawValue) Event",
                location: "Location for \(month.rawValue)",
                day: Int.random(in: 1...28),
                month: month
            )
            
            // Add some edit history
            let history = EditHistory.create(in: context, for: event)
            history.recordChanges(
                previousTitle: nil,
                newTitle: event.title,
                previousLocation: nil,
                newLocation: event.location,
                previousDay: nil,
                newDay: Int(event.day)
            )
        }
        
        // Create sample devices
        let localDevice = FamilyDevice.createLocalDevice(in: context)
        
        // Create some family devices
        let familyMembers = ["Mom", "Dad", "Sister", "Brother"]
        for member in familyMembers {
            let device = FamilyDevice.create(
                in: context,
                bluetoothIdentifier: UUID().uuidString,
                customName: member
            )
            
            // Create sample sync log
            let syncLog = SyncLog.create(in: context, deviceId: device.bluetoothIdentifier, deviceName: device.customName)
            syncLog.eventsReceived = Int32.random(in: 1...12)
            syncLog.eventsSent = Int32.random(in: 1...12)
            syncLog.conflicts = Int32.random(in: 0...3)
            syncLog.resolutionMethod = "Automatic merge"
            syncLog.details = "Sample sync log for \(member)"
        }
        
        // Save the sample data
        save()
    }
}

// MARK: - DataManager Facade
class DataManager {
    static let shared = DataManager()
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    
    // Repositories
    private lazy var eventRepository: EventRepository = {
        EventRepository(context: viewContext)
    }()
    
    private lazy var editHistoryRepository: EditHistoryRepository = {
        EditHistoryRepository(context: viewContext)
    }()
    
    private lazy var familyDeviceRepository: FamilyDeviceRepository = {
        FamilyDeviceRepository(context: viewContext)
    }()
    
    private lazy var syncLogRepository: SyncLogRepository = {
        SyncLogRepository(context: viewContext)
    }()
    
    // Background repositories (for operations that shouldn't block the UI)
    private lazy var backgroundEventRepository: EventRepository = {
        EventRepository(context: backgroundContext)
    }()
    
    private lazy var backgroundEditHistoryRepository: EditHistoryRepository = {
        EditHistoryRepository(context: backgroundContext)
    }()
    
    private lazy var backgroundFamilyDeviceRepository: FamilyDeviceRepository = {
        FamilyDeviceRepository(context: backgroundContext)
    }()
    
    private lazy var backgroundSyncLogRepository: SyncLogRepository = {
        SyncLogRepository(context: backgroundContext)
    }()
    
    // Cache for frequently accessed data
    private var cachedLocalDevice: FamilyDevice?
    private var eventsByMonthCache: [Int: [Event]] = [:]
    private var deviceCache: [String: FamilyDevice] = [:]
    
    // Cache invalidation timestamp
    private var lastCacheInvalidation = Date()
    private let cacheInvalidationInterval: TimeInterval = 60 // 1 minute
    
    private init() {
        self.viewContext = PersistenceController.shared.container.viewContext
        self.backgroundContext = PersistenceController.shared.backgroundContext
        
        // Set up notification observer for changes that should invalidate cache
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(managedObjectContextDidSave),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )
    }
    
    @objc private func managedObjectContextDidSave(notification: Notification) {
        invalidateCache()
    }
    
    private func invalidateCache() {
        cachedLocalDevice = nil
        eventsByMonthCache.removeAll()
        deviceCache.removeAll()
        lastCacheInvalidation = Date()
    }
    
    // MARK: - Event Operations
    
    func getAllEvents() -> [Event] {
        return eventRepository.fetch()
    }
    
    func getEventsByMonth(month: Month) -> [Event] {
        // Check cache first
        let monthNumber = Int(month.monthNumber)
        if let cachedEvents = eventsByMonthCache[monthNumber],
           Date().timeIntervalSince(lastCacheInvalidation) < cacheInvalidationInterval {
            return cachedEvents
        }
        
        // Fetch events
        let events = eventRepository.fetchEventsByMonth(month: month)
        
        // Update cache
        eventsByMonthCache[monthNumber] = events
        
        return events
    }
    
    func getEvent(by id: UUID) -> Event? {
        return eventRepository.fetchEventById(id: id)
    }
    
    func createEvent(title: String, location: String?, day: Int, month: Month) -> Event {
        let event = eventRepository.createEvent(title: title, location: location, day: day, month: month)
        try? eventRepository.save()
        return event
    }
    
    func updateEvent(_ event: Event, title: String, location: String?, day: Int) -> EditHistory {
        let history = eventRepository.updateEvent(event, title: title, location: location, day: day)
        try? eventRepository.save()
        return history
    }
    
    func deleteEvent(_ event: Event) {
        try? eventRepository.delete(event)
    }
    
    func performEventBatchOperation(_ operation: @escaping () -> Void) {
        PersistenceController.shared.performBackgroundTask { _ in
            operation()
        }
    }
    
    // MARK: - EditHistory Operations
    
    func getHistoryForEvent(event: Event) -> [EditHistory] {
        return editHistoryRepository.fetchHistoryForEvent(event: event)
    }
    
    func getHistoryByDevice(deviceId: String) -> [EditHistory] {
        return editHistoryRepository.fetchHistoryByDevice(deviceId: deviceId)
    }
    
    func getHistoryByTimeFrame(startDate: Date, endDate: Date) -> [EditHistory] {
        return editHistoryRepository.fetchHistoryByTimeFrame(startDate: startDate, endDate: endDate)
    }
    
    // MARK: - FamilyDevice Operations
    
    func getAllDevices() -> [FamilyDevice] {
        return familyDeviceRepository.fetch()
    }
    
    func getLocalDevice() -> FamilyDevice {
        // Check cache first
        if let cachedDevice = cachedLocalDevice,
           Date().timeIntervalSince(lastCacheInvalidation) < cacheInvalidationInterval {
            return cachedDevice
        }
        
        // Get device
        let device = familyDeviceRepository.getOrCreateLocalDevice()
        
        // Update cache
        cachedLocalDevice = device
        
        return device
    }
    
    func getDevice(byBluetoothIdentifier identifier: String) -> FamilyDevice? {
        // Check cache first
        if let cachedDevice = deviceCache[identifier],
           Date().timeIntervalSince(lastCacheInvalidation) < cacheInvalidationInterval {
            return cachedDevice
        }
        
        // Fetch device
        let device = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: identifier)
        
        // Update cache if device found
        if let device = device {
            deviceCache[identifier] = device
        }
        
        return device
    }
    
    func registerDevice(bluetoothIdentifier: String, customName: String?) -> FamilyDevice {
        let device = familyDeviceRepository.registerDevice(
            bluetoothIdentifier: bluetoothIdentifier,
            customName: customName
        )
        try? familyDeviceRepository.save()
        return device
    }
    
    func updateDeviceName(device: FamilyDevice, name: String) {
        familyDeviceRepository.updateDeviceName(device: device, name: name)
    }
    
    func updateDeviceSyncTimestamp(device: FamilyDevice) {
        familyDeviceRepository.updateDeviceSyncTimestamp(device: device)
    }
    
    func deleteDevice(_ device: FamilyDevice) {
        try? familyDeviceRepository.delete(device)
    }
    
    // MARK: - SyncLog Operations
    
    func createSyncLog(deviceId: String, deviceName: String? = nil) -> SyncLog {
        let log = syncLogRepository.createSyncLog(deviceId: deviceId, deviceName: deviceName)
        try? syncLogRepository.save()
        return log
    }
    
    func getLogsByDevice(deviceId: String) -> [SyncLog] {
        return syncLogRepository.fetchLogsByDevice(deviceId: deviceId)
    }
    
    func getLogsByTimeFrame(startDate: Date, endDate: Date) -> [SyncLog] {
        return syncLogRepository.fetchLogsByTimeFrame(startDate: startDate, endDate: endDate)
    }
    
    func updateSyncLog(_ log: SyncLog, eventsReceived: Int32, eventsSent: Int32, conflicts: Int32, resolutionMethod: String?, details: String?) {
        syncLogRepository.updateSyncLog(log, eventsReceived: eventsReceived, eventsSent: eventsSent, conflicts: conflicts, resolutionMethod: resolutionMethod, details: details)
    }
    
    // MARK: - Complex Operations
    
    func syncDeviceWithEvents(device: FamilyDevice, receivedEvents: [Event], sentEvents: [Event], conflicts: Int32 = 0, resolutionMethod: String? = nil, details: String? = nil) {
        PersistenceController.shared.performBackgroundTask { _ in
            // Create a sync log
            let log = self.backgroundSyncLogRepository.createSyncLog(
                deviceId: device.bluetoothIdentifier,
                deviceName: device.customName
            )
            
            // Update the log with stats
            log.eventsReceived = Int32(receivedEvents.count)
            log.eventsSent = Int32(sentEvents.count)
            log.conflicts = conflicts
            log.resolutionMethod = resolutionMethod
            log.details = details
            
            // Update device's last sync timestamp
            if let deviceToUpdate = self.backgroundFamilyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: device.bluetoothIdentifier) {
                deviceToUpdate.lastSyncTimestamp = Date()
            }
            
            try? self.backgroundSyncLogRepository.save()
        }
    }
    
    // MARK: - Data Protection Utilities
    
    func isDataProtectionActive() -> Bool {
        return PersistenceController.shared.isDataProtectionActive()
    }
    
    // MARK: - Migration and Maintenance
    
    func performDataMigration() -> Bool {
        // This would handle any custom migrations beyond what Core Data provides
        return true
    }
    
    func verifyDataIntegrity() -> Bool {
        // This would check for any data inconsistencies and fix them
        return true
    }
    
    func performDatabaseMaintenance() {
        PersistenceController.shared.performBackgroundTask { _ in
            // Remove old sync logs (older than 30 days)
            let calendar = Calendar.current
            guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) else {
                return
            }
            
            let oldLogsPredicate = NSPredicate(format: "timestamp < %@", thirtyDaysAgo as NSDate)
            let oldLogs = self.backgroundSyncLogRepository.fetch(predicate: oldLogsPredicate)
            
            for log in oldLogs {
                try? self.backgroundSyncLogRepository.delete(log)
            }
        }
    }
}