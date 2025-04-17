import Foundation
import CoreData

public class BluetoothDevice: NSManagedObject {
    // This class is used as a placeholder to avoid generating a full managed object class
}

extension BluetoothDevice {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<BluetoothDevice> {
        return NSFetchRequest<BluetoothDevice>(entityName: "BluetoothDevice")
    }
    
    @NSManaged public var identifier: String
    @NSManaged public var deviceName: String?
    @NSManaged public var lastSeen: Date?
    @NSManaged public var advertisementData: Data?
    @NSManaged public var manufacturerData: Data?
}