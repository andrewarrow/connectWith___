import Foundation
import CoreData
import UIKit

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