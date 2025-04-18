import Foundation
import CoreData
import UIKit

// MARK: - Repository Protocol
public protocol DataRepository {
    associatedtype Entity
    
    func create() -> Entity
    func fetch(predicate: NSPredicate?, sortDescriptors: [NSSortDescriptor]?) -> [Entity]
    func fetchOne(predicate: NSPredicate) -> Entity?
    func save() throws
    func delete(_ entity: Entity) throws
}

// MARK: - RepositoryError
public enum RepositoryError: Error {
    case invalidEntity
    case saveFailed(Error)
    case fetchFailed(Error)
    case deleteFailed(Error)
    case transactionFailed(Error)
    case entityNotFound
    case invalidData
    
    var localizedDescription: String {
        switch self {
        case .invalidEntity:
            return "Invalid entity provided"
        case .saveFailed(let error):
            return "Failed to save entity: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch entity: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete entity: \(error.localizedDescription)"
        case .transactionFailed(let error):
            return "Transaction failed: \(error.localizedDescription)"
        case .entityNotFound:
            return "Entity not found"
        case .invalidData:
            return "Invalid data provided"
        }
    }
}

// MARK: - TransactionCoordinator
public class TransactionCoordinator {
    private let context: NSManagedObjectContext
    
    public init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    /// Executes a block of code within a transaction
    /// - Parameter block: The block of code to execute
    /// - Throws: RepositoryError if the transaction fails
    public func performTransaction(_ block: () throws -> Void) throws {
        // Start transaction
        context.performAndWait {
            do {
                // Execute the block
                try block()
                
                // Commit if context has changes
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                // Rollback in case of error
                context.rollback()
                print("Transaction rolled back: \(error.localizedDescription)")
                throw RepositoryError.transactionFailed(error)
            }
        }
    }
    
    /// Executes a block of code within a transaction asynchronously
    /// - Parameters:
    ///   - block: The block of code to execute
    ///   - completion: Completion handler with optional error
    public func performAsyncTransaction(_ block: @escaping () throws -> Void, completion: @escaping (Error?) -> Void) {
        context.perform {
            do {
                try block()
                
                if self.context.hasChanges {
                    try self.context.save()
                }
                completion(nil)
            } catch {
                self.context.rollback()
                print("Async transaction rolled back: \(error.localizedDescription)")
                completion(RepositoryError.transactionFailed(error))
            }
        }
    }
}

// MARK: - Event Entity
public class Event: NSManagedObject {
    // This class is used as a placeholder to avoid generating a full managed object class
}

extension Event {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Event> {
        return NSFetchRequest<Event>(entityName: "Event")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var location: String?
    @NSManaged public var day: Int16
    @NSManaged public var month: Int16
    @NSManaged public var createdAt: Date
    @NSManaged public var lastModifiedAt: Date
    @NSManaged public var lastModifiedBy: String
    @NSManaged public var color: String?
    @NSManaged public var history: Set<EditHistory>?
    
    // Convenience properties
    public var monthEnum: Month? {
        get { Month.from(monthNumber: month) }
        set { month = newValue?.monthNumber ?? 1 }
    }
    
    public var colorName: String {
        get { color ?? monthEnum?.color ?? "card.january" }
        set { color = newValue }
    }
    
    // Factory method
    public static func create(in context: NSManagedObjectContext, title: String, location: String?, day: Int, month: Month) -> Event {
        let event = Event(context: context)
        event.id = UUID()
        event.title = title
        event.location = location
        event.day = Int16(day)
        event.month = month.monthNumber
        
        let now = Date()
        event.createdAt = now
        event.lastModifiedAt = now
        
        // This should be replaced with actual device ID when available
        event.lastModifiedBy = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        
        return event
    }
}

// MARK: - EditHistory Entity
public class EditHistory: NSManagedObject {
    // This class is used as a placeholder to avoid generating a full managed object class
}

extension EditHistory {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<EditHistory> {
        return NSFetchRequest<EditHistory>(entityName: "EditHistory")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var deviceId: String
    @NSManaged public var deviceName: String?
    @NSManaged public var previousTitle: String?
    @NSManaged public var newTitle: String?
    @NSManaged public var previousLocation: String?
    @NSManaged public var newLocation: String?
    @NSManaged public var previousDay: Int16
    @NSManaged public var newDay: Int16
    @NSManaged public var timestamp: Date
    @NSManaged public var event: Event?
    
    // Factory method
    public static func create(in context: NSManagedObjectContext, for event: Event) -> EditHistory {
        let history = EditHistory(context: context)
        history.id = UUID()
        history.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        
        // Get device name from FamilyDevice if available, otherwise use device name
        history.deviceName = UIDevice.current.name
        
        history.timestamp = Date()
        history.event = event
        
        return history
    }
    
    // Record changes
    public func recordChanges(previousTitle: String?, newTitle: String?,
                              previousLocation: String?, newLocation: String?,
                              previousDay: Int?, newDay: Int?) {
        self.previousTitle = previousTitle
        self.newTitle = newTitle
        self.previousLocation = previousLocation
        self.newLocation = newLocation
        
        if let pDay = previousDay {
            self.previousDay = Int16(pDay)
        }
        
        if let nDay = newDay {
            self.newDay = Int16(nDay)
        }
    }
}

// MARK: - FamilyDevice Entity
public class FamilyDevice: NSManagedObject {
    // This class is used as a placeholder to avoid generating a full managed object class
}

extension FamilyDevice {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FamilyDevice> {
        return NSFetchRequest<FamilyDevice>(entityName: "FamilyDevice")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var bluetoothIdentifier: String
    @NSManaged public var customName: String?
    @NSManaged public var lastSyncTimestamp: Date?
    @NSManaged public var isLocalDevice: Bool
    
    // Factory method
    public static func create(in context: NSManagedObjectContext, bluetoothIdentifier: String, customName: String? = nil, isLocalDevice: Bool = false) -> FamilyDevice {
        let device = FamilyDevice(context: context)
        device.id = UUID()
        device.bluetoothIdentifier = bluetoothIdentifier
        device.customName = customName
        device.isLocalDevice = isLocalDevice
        
        return device
    }
    
    // Create local device
    public static func createLocalDevice(in context: NSManagedObjectContext) -> FamilyDevice {
        let identifier = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        return create(in: context, bluetoothIdentifier: identifier, customName: UIDevice.current.name, isLocalDevice: true)
    }
}

// MARK: - SyncLog Entity
public class SyncLog: NSManagedObject {
    // This class is used as a placeholder to avoid generating a full managed object class
}

extension SyncLog {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SyncLog> {
        return NSFetchRequest<SyncLog>(entityName: "SyncLog")
    }
    
    @NSManaged public var id: UUID
    @NSManaged public var timestamp: Date
    @NSManaged public var deviceId: String
    @NSManaged public var deviceName: String?
    @NSManaged public var eventsReceived: Int32
    @NSManaged public var eventsSent: Int32
    @NSManaged public var conflicts: Int32
    @NSManaged public var resolutionMethod: String?
    @NSManaged public var details: String?
    
    // Factory method
    public static func create(in context: NSManagedObjectContext, deviceId: String, deviceName: String? = nil) -> SyncLog {
        let log = SyncLog(context: context)
        log.id = UUID()
        log.timestamp = Date()
        log.deviceId = deviceId
        log.deviceName = deviceName
        log.eventsReceived = 0
        log.eventsSent = 0
        log.conflicts = 0
        
        return log
    }
}

// MARK: - Repository Implementations

// EventRepository
public class EventRepository: DataRepository {
    private let context: NSManagedObjectContext
    private lazy var transactionCoordinator = TransactionCoordinator(context: context)
    
    public init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    public func create() -> Event {
        return Event(context: context)
    }
    
    public func fetch(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> [Event] {
        let request = Event.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching events: \(error)")
            return []
        }
    }
    
    public func fetchOne(predicate: NSPredicate) -> Event? {
        let request = Event.fetchRequest()
        request.predicate = predicate
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("Error fetching event: \(error)")
            return nil
        }
    }
    
    public func save() throws {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving event context: \(error)")
                throw RepositoryError.saveFailed(error)
            }
        }
    }
    
    public func delete(_ entity: Event) throws {
        context.delete(entity)
        do {
            try save()
        } catch {
            throw RepositoryError.deleteFailed(error)
        }
    }
    
    // MARK: - Custom Event Methods
    
    public func createEvent(title: String, location: String?, day: Int, month: Month) -> Event {
        return Event.create(in: context, title: title, location: location, day: day, month: month)
    }
    
    public func fetchEventsByMonth(month: Month) -> [Event] {
        let predicate = NSPredicate(format: "month == %d", month.monthNumber)
        let sortDescriptor = NSSortDescriptor(key: "day", ascending: true)
        return fetch(predicate: predicate, sortDescriptors: [sortDescriptor])
    }
    
    public func fetchEventById(id: UUID) -> Event? {
        let predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return fetchOne(predicate: predicate)
    }
    
    public func updateEvent(_ event: Event, title: String, location: String?, day: Int) -> EditHistory {
        // Create history before updating
        let history = EditHistory.create(in: context, for: event)
        history.recordChanges(
            previousTitle: event.title,
            newTitle: title,
            previousLocation: event.location,
            newLocation: location,
            previousDay: Int(event.day),
            newDay: day
        )
        
        // Update event
        event.title = title
        event.location = location
        event.day = Int16(day)
        event.lastModifiedAt = Date()
        event.lastModifiedBy = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        
        return history
    }
    
    // Complex transactions
    
    /// Updates an event and records history in a single transaction
    /// - Parameters:
    ///   - event: The event to update
    ///   - title: New title
    ///   - location: New location
    ///   - day: New day
    /// - Returns: The edit history entry if successful
    /// - Throws: RepositoryError if the transaction fails
    public func updateEventWithTransaction(_ event: Event, title: String, location: String?, day: Int) throws -> EditHistory {
        var history: EditHistory!
        
        try transactionCoordinator.performTransaction {
            // Create history
            history = EditHistory.create(in: self.context, for: event)
            history.recordChanges(
                previousTitle: event.title,
                newTitle: title,
                previousLocation: event.location,
                newLocation: location,
                previousDay: Int(event.day),
                newDay: day
            )
            
            // Update event
            event.title = title
            event.location = location
            event.day = Int16(day)
            event.lastModifiedAt = Date()
            event.lastModifiedBy = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }
        
        return history
    }
    
    /// Deletes an event and related history in a single transaction
    /// - Parameter event: The event to delete
    /// - Throws: RepositoryError if the transaction fails
    public func deleteEventWithHistory(_ event: Event) throws {
        try transactionCoordinator.performTransaction {
            // Delete associated history entries
            if let history = event.history {
                for entry in history {
                    self.context.delete(entry)
                }
            }
            
            // Delete the event
            self.context.delete(event)
        }
    }
    
    /// Batch creates multiple events in a single transaction
    /// - Parameter eventData: Array of tuples with event data (title, location, day, month)
    /// - Returns: Array of created events
    /// - Throws: RepositoryError if the transaction fails
    public func batchCreateEvents(_ eventData: [(title: String, location: String?, day: Int, month: Month)]) throws -> [Event] {
        var createdEvents: [Event] = []
        
        try transactionCoordinator.performTransaction {
            for data in eventData {
                let event = Event.create(
                    in: self.context,
                    title: data.title,
                    location: data.location,
                    day: data.day,
                    month: data.month
                )
                createdEvents.append(event)
            }
        }
        
        return createdEvents
    }
}

// EditHistoryRepository
public class EditHistoryRepository: DataRepository {
    private let context: NSManagedObjectContext
    private lazy var transactionCoordinator = TransactionCoordinator(context: context)
    
    public init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    public func create() -> EditHistory {
        return EditHistory(context: context)
    }
    
    public func fetch(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> [EditHistory] {
        let request = EditHistory.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching edit history: \(error)")
            return []
        }
    }
    
    public func fetchOne(predicate: NSPredicate) -> EditHistory? {
        let request = EditHistory.fetchRequest()
        request.predicate = predicate
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("Error fetching edit history: \(error)")
            return nil
        }
    }
    
    public func save() throws {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving edit history context: \(error)")
                throw RepositoryError.saveFailed(error)
            }
        }
    }
    
    public func delete(_ entity: EditHistory) throws {
        context.delete(entity)
        do {
            try save()
        } catch {
            throw RepositoryError.deleteFailed(error)
        }
    }
    
    // MARK: - Custom EditHistory Methods
    
    public func fetchHistoryForEvent(event: Event) -> [EditHistory] {
        let predicate = NSPredicate(format: "event == %@", event)
        let sortDescriptor = NSSortDescriptor(key: "timestamp", ascending: false)
        return fetch(predicate: predicate, sortDescriptors: [sortDescriptor])
    }
    
    public func fetchHistoryByDevice(deviceId: String) -> [EditHistory] {
        let predicate = NSPredicate(format: "deviceId == %@", deviceId)
        return fetch(predicate: predicate)
    }
    
    public func fetchHistoryByTimeFrame(startDate: Date, endDate: Date) -> [EditHistory] {
        let predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", startDate as NSDate, endDate as NSDate)
        return fetch(predicate: predicate)
    }
    
    /// Bulk deletes history entries older than a specified date
    /// - Parameter date: The cutoff date
    /// - Returns: Number of entries deleted
    /// - Throws: RepositoryError if the operation fails
    public func deleteHistoryOlderThan(date: Date) throws -> Int {
        let fetchRequest = EditHistory.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
        
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest as! NSFetchRequest<NSFetchRequestResult>)
        batchDeleteRequest.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
            return result?.result as? Int ?? 0
        } catch {
            throw RepositoryError.deleteFailed(error)
        }
    }
    
    /// Creates multiple history entries for an event in a single transaction
    /// - Parameters:
    ///   - entries: Array of tuples with history data
    ///   - event: The event the history entries belong to
    /// - Returns: Array of created history entries
    /// - Throws: RepositoryError if the transaction fails
    public func batchCreateHistory(entries: [(previousTitle: String?, newTitle: String?, previousLocation: String?, newLocation: String?, previousDay: Int?, newDay: Int?)], event: Event) throws -> [EditHistory] {
        var createdEntries: [EditHistory] = []
        
        try transactionCoordinator.performTransaction {
            for entry in entries {
                let history = EditHistory.create(in: self.context, for: event)
                history.recordChanges(
                    previousTitle: entry.previousTitle,
                    newTitle: entry.newTitle,
                    previousLocation: entry.previousLocation,
                    newLocation: entry.newLocation,
                    previousDay: entry.previousDay,
                    newDay: entry.newDay
                )
                createdEntries.append(history)
            }
        }
        
        return createdEntries
    }
}

// FamilyDeviceRepository
public class FamilyDeviceRepository: DataRepository {
    private let context: NSManagedObjectContext
    private lazy var transactionCoordinator = TransactionCoordinator(context: context)
    
    public init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    public func create() -> FamilyDevice {
        return FamilyDevice(context: context)
    }
    
    public func fetch(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> [FamilyDevice] {
        let request = FamilyDevice.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching family devices: \(error)")
            return []
        }
    }
    
    public func fetchOne(predicate: NSPredicate) -> FamilyDevice? {
        let request = FamilyDevice.fetchRequest()
        request.predicate = predicate
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("Error fetching family device: \(error)")
            return nil
        }
    }
    
    public func save() throws {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving family device context: \(error)")
                throw RepositoryError.saveFailed(error)
            }
        }
    }
    
    public func delete(_ entity: FamilyDevice) throws {
        context.delete(entity)
        do {
            try save()
        } catch {
            throw RepositoryError.deleteFailed(error)
        }
    }
    
    // MARK: - Custom FamilyDevice Methods
    
    public func registerDevice(bluetoothIdentifier: String, customName: String?, isLocalDevice: Bool = false) -> FamilyDevice {
        return FamilyDevice.create(
            in: context,
            bluetoothIdentifier: bluetoothIdentifier,
            customName: customName,
            isLocalDevice: isLocalDevice
        )
    }
    
    public func getOrCreateLocalDevice() -> FamilyDevice {
        // First try to fetch the existing local device
        let predicate = NSPredicate(format: "isLocalDevice == YES")
        if let existingDevice = fetchOne(predicate: predicate) {
            return existingDevice
        }
        
        // Otherwise create a new one
        return FamilyDevice.createLocalDevice(in: context)
    }
    
    public func fetchDeviceByBluetoothIdentifier(identifier: String) -> FamilyDevice? {
        let predicate = NSPredicate(format: "bluetoothIdentifier == %@", identifier)
        return fetchOne(predicate: predicate)
    }
    
    public func updateDeviceSyncTimestamp(device: FamilyDevice) {
        device.lastSyncTimestamp = Date()
        try? save()
    }
    
    public func updateDeviceName(device: FamilyDevice, name: String) {
        device.customName = name
        try? save()
    }
    
    /// Registers multiple devices in a single transaction
    /// - Parameter devices: Array of tuples with device data
    /// - Returns: Array of created devices
    /// - Throws: RepositoryError if the transaction fails
    public func batchRegisterDevices(_ devices: [(bluetoothIdentifier: String, customName: String?, isLocalDevice: Bool)]) throws -> [FamilyDevice] {
        var createdDevices: [FamilyDevice] = []
        
        try transactionCoordinator.performTransaction {
            for deviceData in devices {
                let device = FamilyDevice.create(
                    in: self.context,
                    bluetoothIdentifier: deviceData.bluetoothIdentifier,
                    customName: deviceData.customName,
                    isLocalDevice: deviceData.isLocalDevice
                )
                createdDevices.append(device)
            }
        }
        
        return createdDevices
    }
    
    /// Deletes multiple devices in a single transaction
    /// - Parameter devices: Array of devices to delete
    /// - Throws: RepositoryError if the transaction fails
    public func batchDeleteDevices(_ devices: [FamilyDevice]) throws {
        try transactionCoordinator.performTransaction {
            for device in devices {
                self.context.delete(device)
            }
        }
    }
    
    /// Updates sync timestamps for multiple devices in a single transaction
    /// - Parameter devices: Array of devices to update
    /// - Throws: RepositoryError if the transaction fails
    public func batchUpdateSyncTimestamps(_ devices: [FamilyDevice]) throws {
        let now = Date()
        
        try transactionCoordinator.performTransaction {
            for device in devices {
                device.lastSyncTimestamp = now
            }
        }
    }
}

// SyncLogRepository
public class SyncLogRepository: DataRepository {
    private let context: NSManagedObjectContext
    private lazy var transactionCoordinator = TransactionCoordinator(context: context)
    
    public init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    public func create() -> SyncLog {
        return SyncLog(context: context)
    }
    
    public func fetch(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> [SyncLog] {
        let request = SyncLog.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching sync logs: \(error)")
            return []
        }
    }
    
    public func fetchOne(predicate: NSPredicate) -> SyncLog? {
        let request = SyncLog.fetchRequest()
        request.predicate = predicate
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            return results.first
        } catch {
            print("Error fetching sync log: \(error)")
            return nil
        }
    }
    
    public func save() throws {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving sync log context: \(error)")
                throw RepositoryError.saveFailed(error)
            }
        }
    }
    
    public func delete(_ entity: SyncLog) throws {
        context.delete(entity)
        do {
            try save()
        } catch {
            throw RepositoryError.deleteFailed(error)
        }
    }
    
    // MARK: - Custom SyncLog Methods
    
    public func createSyncLog(deviceId: String, deviceName: String? = nil) -> SyncLog {
        return SyncLog.create(in: context, deviceId: deviceId, deviceName: deviceName)
    }
    
    public func fetchLogsByDevice(deviceId: String) -> [SyncLog] {
        let predicate = NSPredicate(format: "deviceId == %@", deviceId)
        return fetch(predicate: predicate)
    }
    
    public func fetchLogsByTimeFrame(startDate: Date, endDate: Date) -> [SyncLog] {
        let predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", startDate as NSDate, endDate as NSDate)
        return fetch(predicate: predicate)
    }
    
    public func updateSyncLog(_ log: SyncLog, eventsReceived: Int32, eventsSent: Int32, conflicts: Int32, resolutionMethod: String?, details: String?) {
        log.eventsReceived = eventsReceived
        log.eventsSent = eventsSent
        log.conflicts = conflicts
        log.resolutionMethod = resolutionMethod
        log.details = details
        try? save()
    }
    
    /// Creates multiple sync logs in a single transaction
    /// - Parameter logs: Array of tuples with log data
    /// - Returns: Array of created logs
    /// - Throws: RepositoryError if the transaction fails
    public func batchCreateSyncLogs(_ logs: [(deviceId: String, deviceName: String?, eventsReceived: Int32, eventsSent: Int32, conflicts: Int32, resolutionMethod: String?, details: String?)]) throws -> [SyncLog] {
        var createdLogs: [SyncLog] = []
        
        try transactionCoordinator.performTransaction {
            for logData in logs {
                let log = SyncLog.create(in: self.context, deviceId: logData.deviceId, deviceName: logData.deviceName)
                log.eventsReceived = logData.eventsReceived
                log.eventsSent = logData.eventsSent
                log.conflicts = logData.conflicts
                log.resolutionMethod = logData.resolutionMethod
                log.details = logData.details
                
                createdLogs.append(log)
            }
        }
        
        return createdLogs
    }
    
    /// Deletes logs older than a specified date
    /// - Parameter date: The cutoff date
    /// - Returns: Number of logs deleted
    /// - Throws: RepositoryError if the operation fails
    public func deleteLogsOlderThan(date: Date) throws -> Int {
        let fetchRequest = SyncLog.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
        
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest as! NSFetchRequest<NSFetchRequestResult>)
        batchDeleteRequest.resultType = .resultTypeCount
        
        do {
            let result = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
            return result?.result as? Int ?? 0
        } catch {
            throw RepositoryError.deleteFailed(error)
        }
    }
}