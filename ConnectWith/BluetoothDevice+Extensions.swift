import Foundation
import CoreData
import CoreBluetooth

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
    
    // MARK: - Helper Methods
    
    /// Creates a formatted description of the device
    public var formattedDescription: String {
        let name = deviceName ?? "Unknown Device"
        let date = lastSeen?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
        return "\(name) (Last seen: \(date))"
    }
    
    /// Calculates the time interval since this device was last seen
    public var timeSinceLastSeen: TimeInterval? {
        guard let lastSeen = lastSeen else { return nil }
        return Date().timeIntervalSince(lastSeen)
    }
    
    /// Checks if the device was seen recently (within the last hour)
    public var isRecentlyActive: Bool {
        guard let interval = timeSinceLastSeen else { return false }
        return interval < 3600 // 1 hour in seconds
    }
    
    /// Returns a signal strength indicator based on stored advertisement data
    public var signalStrengthIndicator: Int {
        // A simple placeholder implementation
        // In a real implementation, this would parse RSSI from advertisement data
        return 3 // Medium signal strength (range 0-5)
    }
    
    /// Parses service UUIDs from advertisement data
    public var serviceUUIDs: [CBUUID]? {
        guard let advertisementData = self.advertisementData else { return nil }
        
        do {
            if let uuidStrings = try JSONSerialization.jsonObject(with: advertisementData) as? [String] {
                return uuidStrings.map { CBUUID(string: $0) }
            }
        } catch {
            print("Error parsing service UUIDs: \(error)")
        }
        
        return nil
    }
    
    /// Checks if the device supports our 12x synchronization service
    public var supports12xSync: Bool {
        guard let serviceUUIDs = serviceUUIDs else { return false }
        return serviceUUIDs.contains(BluetoothDiscoveryManager.serviceUUID)
    }
    
    /// Updates the device with information from a peripheral and advertisement data
    public func update(from peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        // Update basic information
        if peripheral.name != nil && peripheral.name?.isEmpty == false {
            self.deviceName = peripheral.name
        } else if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, 
                  !localName.isEmpty {
            self.deviceName = localName
        }
        
        // Update last seen timestamp
        self.lastSeen = Date()
        
        // Update manufacturer data if available
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            self.manufacturerData = manufacturerData
        }
        
        // Update service UUIDs if available
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            let uuidStrings = serviceUUIDs.map { $0.uuidString }
            self.advertisementData = try? JSONSerialization.data(withJSONObject: uuidStrings)
        }
    }
}