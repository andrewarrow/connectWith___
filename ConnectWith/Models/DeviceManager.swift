import Foundation
import CoreData
import CoreBluetooth
import OSLog
import Combine

/// Manages all device-related operations in a centralized place
class DeviceManager: ObservableObject {
    // Singleton instance
    static let shared = DeviceManager()
    
    // Published properties
    @Published var familyDevices: [FamilyDevice] = []
    @Published var bluetoothDevices: [BluetoothDevice] = []
    @Published var isRefreshing: Bool = false
    
    // Reference to other managers
    private let bluetoothManager = BluetoothDiscoveryManager.shared
    private let connectionManager = ConnectionManager.shared
    private let syncHistoryManager = SyncHistoryManager.shared
    
    // Cancellables for subscribers
    private var cancellables = Set<AnyCancellable>()
    
    // Initialize with default values
    private init() {
        // Load devices on initialization
        loadDevices()
        
        // Set up notification observers to refresh devices when changes occur
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.loadDevices()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Device Loading
    
    /// Loads all devices from Core Data
    func loadDevices() {
        let context = PersistenceController.shared.container.viewContext
        
        // Load FamilyDevices
        let familyDeviceRepository = FamilyDeviceRepository(context: context)
        self.familyDevices = familyDeviceRepository.fetch(sortDescriptors: [
            NSSortDescriptor(key: "lastSyncTimestamp", ascending: false),
            NSSortDescriptor(key: "customName", ascending: true)
        ])
        
        // Load BluetoothDevices
        let fetchRequest = BluetoothDevice.fetchRequest()
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "lastSeen", ascending: false)
        ]
        
        do {
            self.bluetoothDevices = try context.fetch(fetchRequest)
        } catch {
            Logger.bluetooth.error("Failed to fetch bluetooth devices: \(error.localizedDescription)")
        }
        
        Logger.bluetooth.info("Loaded \(self.familyDevices.count) family devices and \(self.bluetoothDevices.count) bluetooth devices")
    }
    
    /// Refreshes the device list and scans for new devices
    func refreshDevices() {
        isRefreshing = true
        
        // First refresh our local data
        loadDevices()
        
        // Then trigger a Bluetooth scan
        bluetoothManager.startScan()
        
        // Set a timer to load devices again after scan completes
        DispatchQueue.main.asyncAfter(deadline: .now() + bluetoothManager.currentScanningProfile.scanDuration + 0.5) {
            self.loadDevices()
            self.isRefreshing = false
        }
    }
    
    // MARK: - Device Management
    
    /// Renames a device
    /// - Parameters:
    ///   - device: The device to rename
    ///   - name: The new name
    func renameDevice(device: FamilyDevice, name: String) {
        guard !name.isEmpty else {
            Logger.bluetooth.warning("Attempted to set empty name for device \(device.bluetoothIdentifier)")
            return
        }
        
        PersistenceController.shared.performBackgroundTask { context in
            let familyDeviceRepository = FamilyDeviceRepository(context: context)
            
            if let deviceToRename = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: device.bluetoothIdentifier) {
                deviceToRename.customName = name
                try? context.save()
                
                // Also update the BluetoothDevice if it exists
                let fetchRequest = BluetoothDevice.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "identifier == %@", device.bluetoothIdentifier)
                
                do {
                    let results = try context.fetch(fetchRequest)
                    if let bluetoothDevice = results.first {
                        bluetoothDevice.deviceName = name
                        try context.save()
                    }
                } catch {
                    Logger.bluetooth.error("Failed to update BluetoothDevice name: \(error.localizedDescription)")
                }
                
                Logger.bluetooth.info("Renamed device \(device.bluetoothIdentifier) to \(name)")
            }
        }
    }
    
    /// Deletes a device
    /// - Parameter device: The device to delete
    func deleteDevice(device: FamilyDevice) {
        PersistenceController.shared.performBackgroundTask { context in
            let familyDeviceRepository = FamilyDeviceRepository(context: context)
            
            if let deviceToDelete = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: device.bluetoothIdentifier) {
                // Delete the FamilyDevice
                try? familyDeviceRepository.delete(deviceToDelete)
                
                // Also delete the BluetoothDevice if it exists
                let fetchRequest = BluetoothDevice.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "identifier == %@", device.bluetoothIdentifier)
                
                do {
                    let results = try context.fetch(fetchRequest)
                    if let bluetoothDevice = results.first {
                        context.delete(bluetoothDevice)
                        try context.save()
                    }
                } catch {
                    Logger.bluetooth.error("Failed to delete BluetoothDevice: \(error.localizedDescription)")
                }
                
                Logger.bluetooth.info("Deleted device \(device.bluetoothIdentifier)")
            }
        }
    }
    
    /// Registers a new device
    /// - Parameters:
    ///   - bluetoothIdentifier: The device's Bluetooth identifier
    ///   - customName: The device's name
    ///   - isLocalDevice: Whether this is the local device
    /// - Returns: The created device
    func registerDevice(bluetoothIdentifier: String, customName: String?, isLocalDevice: Bool = false) -> FamilyDevice? {
        var createdDevice: FamilyDevice?
        
        let context = PersistenceController.shared.container.viewContext
        let familyDeviceRepository = FamilyDeviceRepository(context: context)
        
        // Check if device already exists
        if let existingDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: bluetoothIdentifier) {
            return existingDevice
        }
        
        // Create a new device
        createdDevice = familyDeviceRepository.registerDevice(
            bluetoothIdentifier: bluetoothIdentifier,
            customName: customName,
            isLocalDevice: isLocalDevice
        )
        
        // Save the context
        try? context.save()
        
        if let device = createdDevice {
            Logger.bluetooth.info("Registered new device: \(device.customName ?? "Unknown") (\(bluetoothIdentifier))")
        }
        
        return createdDevice
    }
    
    /// Gets the local device
    /// - Returns: The local device
    func getLocalDevice() -> FamilyDevice {
        let context = PersistenceController.shared.container.viewContext
        let familyDeviceRepository = FamilyDeviceRepository(context: context)
        return familyDeviceRepository.getOrCreateLocalDevice()
    }
    
    /// Finds a FamilyDevice matching a BluetoothDevice
    /// - Parameter bluetoothDevice: The BluetoothDevice to match
    /// - Returns: The matching FamilyDevice, if found
    func findFamilyDevice(for bluetoothDevice: BluetoothDevice) -> FamilyDevice? {
        return familyDevices.first { $0.bluetoothIdentifier == bluetoothDevice.identifier }
    }
    
    /// Finds a BluetoothDevice matching a FamilyDevice
    /// - Parameter familyDevice: The FamilyDevice to match
    /// - Returns: The matching BluetoothDevice, if found
    func findBluetoothDevice(for familyDevice: FamilyDevice) -> BluetoothDevice? {
        return bluetoothDevices.first { $0.identifier == familyDevice.bluetoothIdentifier }
    }
    
    // MARK: - Connection Management
    
    /// Connects to a device
    /// - Parameter device: The device to connect to
    /// - Returns: A publisher that emits when the connection succeeds or fails
    func connectToDevice(device: FamilyDevice) -> AnyPublisher<Bool, Error> {
        return connectionManager.connectToDevice(identifier: device.bluetoothIdentifier)
    }
    
    /// Gets the connection status for a device
    /// - Parameter device: The device to check
    /// - Returns: The connection status
    func getConnectionStatus(device: FamilyDevice) -> ConnectionManager.ConnectionStatus {
        return connectionManager.getConnectionStatus(identifier: device.bluetoothIdentifier)
    }
    
    /// Checks if a connection is in progress for a device
    /// - Parameter device: The device to check
    /// - Returns: True if a connection is in progress
    func isConnectionInProgress(device: FamilyDevice) -> Bool {
        return connectionManager.connectionInProgress[device.bluetoothIdentifier] == true
    }
    
    // MARK: - Data Maintenance
    
    /// Purges old devices that haven't been seen in a while
    /// - Parameter olderThan: The cutoff date
    func purgeOldDevices(olderThan days: Int = 30) {
        bluetoothManager.purgeOldDevices(olderThan: days)
    }
    
    /// Purges old sync logs
    /// - Parameter olderThan: The cutoff date
    func purgeOldSyncLogs(olderThan days: Int = 30) {
        let calendar = Calendar.current
        if let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) {
            syncHistoryManager.cleanupOldSyncLogs(olderThan: cutoffDate)
        }
    }
}