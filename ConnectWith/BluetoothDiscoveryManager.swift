import Foundation
import CoreBluetooth
import OSLog

// MARK: - Bluetooth Discovery Manager
class BluetoothDiscoveryManager: NSObject, ObservableObject {
    // Singleton instance
    static let shared = BluetoothDiscoveryManager()
    
    // Service UUID for our app - used for discovery
    static let serviceUUID = CBUUID(string: "4514d666-d6c9-49cb-bc31-dc6dfa28bd58")
    static let calendarCharacteristicUUID = CBUUID(string: "97d52a22-9292-48c6-a89f-8a71d89c5e9b")
    
    // MARK: - Core Bluetooth Components
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    
    // Service and characteristic for peripheral mode
    private var calendarService: CBMutableService?
    private var calendarCharacteristic: CBMutableCharacteristic?
    
    // MARK: - Bluetooth State Properties
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var permissionGranted = false
    @Published var showPermissionAlert = false
    @Published var isScanning = false
    @Published var isAdvertising = false
    @Published var scanningProgress: Double = 0.0
    
    // MARK: - Device Discovery Properties
    @Published var nearbyDevices: [(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)] = []
    @Published var connectedPeripherals: [CBPeripheral] = []
    
    // Device name for this device
    var deviceName: String {
        UserDefaults.standard.string(forKey: "DeviceCustomName") ?? UIDevice.current.name
    }
    
    // Private initializer for singleton
    override private init() {
        super.init()
        setupBluetooth()
    }
    
    // MARK: - Setup Methods
    
    private func setupBluetooth() {
        // Initialize the central manager (for discovering other devices)
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // Initialize the peripheral manager (for being discovered)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        // Log initialization
        Logger.bluetooth.info("BluetoothDiscoveryManager initialized")
    }
    
    // MARK: - Public Methods
    
    /// Starts scanning for nearby devices
    func startScanning() {
        guard permissionGranted else {
            showPermissionAlert = true
            return
        }
        
        Logger.bluetooth.info("Starting Bluetooth scan")
        
        // Clear previous scan results
        nearbyDevices.removeAll()
        isScanning = true
        scanningProgress = 0.0
        
        // Start the scanning progress animation
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            if self.scanningProgress < 1.0 {
                self.scanningProgress += 0.01
            } else {
                timer.invalidate()
            }
        }
        
        // Scan options to get the local name and allow duplicate peripheral discoveries
        let scanOptions: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ]
        
        // First scan without service UUID filter to get all nearby Bluetooth devices with their names
        centralManager?.scanForPeripherals(withServices: nil, options: scanOptions)
        
        // Also scan for our specific service UUID
        centralManager?.scanForPeripherals(withServices: [BluetoothDiscoveryManager.serviceUUID], options: scanOptions)
        
        // Auto-stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopScanning()
            timer.invalidate()
            self?.scanningProgress = 1.0
        }
    }
    
    /// Stops an active Bluetooth scan
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
        Logger.bluetooth.info("Bluetooth scan stopped")
    }
    
    /// Starts advertising this device to be discovered by others
    func startAdvertising() {
        guard permissionGranted else {
            showPermissionAlert = true
            return
        }
        
        // Create calendar characteristic
        calendarCharacteristic = CBMutableCharacteristic(
            type: BluetoothDiscoveryManager.calendarCharacteristicUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        // Create a service with our UUID
        calendarService = CBMutableService(type: BluetoothDiscoveryManager.serviceUUID, primary: true)
        
        // Add the calendar characteristic to the service
        if let calendarCharacteristic = calendarCharacteristic {
            calendarService?.characteristics = [calendarCharacteristic]
        }
        
        // Only add the service if the peripheral manager is powered on
        if let peripheralManager = peripheralManager, peripheralManager.state == .poweredOn, 
           let calendarService = calendarService {
            peripheralManager.add(calendarService)
            // Start advertising now
            startAdvertisingService()
        }
        // Otherwise we'll wait for peripheralManagerDidUpdateState to be called
    }
    
    /// Stops advertising this device
    func stopAdvertising() {
        if isAdvertising {
            peripheralManager?.stopAdvertising()
            isAdvertising = false
            Logger.bluetooth.info("Stopped advertising device")
        }
    }
    
    /// Connects to a discovered device
    func connectToDevice(_ peripheral: CBPeripheral) {
        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
        Logger.bluetooth.info("Connecting to device: \(peripheral.identifier.uuidString)")
    }
    
    /// Disconnects from a connected device
    func disconnectFromDevice(_ peripheral: CBPeripheral) {
        centralManager?.cancelPeripheralConnection(peripheral)
        Logger.bluetooth.info("Disconnecting from device: \(peripheral.identifier.uuidString)")
    }
    
    // MARK: - Private Helper Methods
    
    /// Starts advertising this device after the peripheral manager is ready
    private func startAdvertisingService() {
        // Get personalized device name from settings
        var deviceName = UIDevice.current.name
        
        // Try to get the personalized name from UserDefaults
        if let customName = UserDefaults.standard.string(forKey: "DeviceCustomName") {
            deviceName = customName
        } else {
            // Use host name which often includes personalized name ("Bob's-iPhone.local" format)
            let hostName = ProcessInfo.processInfo.hostName
            let cleanedName = hostName.replacingOccurrences(of: ".local", with: "")
                                      .replacingOccurrences(of: "-", with: " ")
            deviceName = cleanedName
        }
        
        Logger.bluetooth.info("Advertising device with name: \(deviceName)")
        
        // Start advertising with device name and our service UUID
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BluetoothDiscoveryManager.serviceUUID],
            CBAdvertisementDataLocalNameKey: deviceName
        ]
        
        // Start advertising with enhanced data
        peripheralManager?.startAdvertising(advertisementData)
        
        // Update state
        isAdvertising = true
    }
    
    /// Saves a discovered device to the database
    private func saveDeviceToDatabase(peripheral: CBPeripheral, advertisementData: [String: Any]) {
        // Determine device name
        let deviceName: String
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
            deviceName = localName
        } else if let name = peripheral.name, !name.isEmpty {
            deviceName = name
        } else {
            // Check if we already have a name for this device in the store
            if let existingDevice = DeviceStore.shared.getDevice(identifier: peripheral.identifier.uuidString),
               existingDevice.name != "Unknown Device" {
                deviceName = existingDevice.name
            } else {
                // Use host name if available which often includes personalized name
                let myDeviceName = UIDevice.current.name
                deviceName = "Nearby Device (\(myDeviceName.prefix(10))...)"
            }
        }
        
        // Get manufacturer data if available
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        
        // Create a serialized version of service UUIDs if available
        var serviceData: Data? = nil
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            let uuidStrings = serviceUUIDs.map { $0.uuidString }
            serviceData = try? JSONSerialization.data(withJSONObject: uuidStrings)
        }
        
        // Save to our in-memory store
        DeviceStore.shared.saveDevice(
            identifier: peripheral.identifier.uuidString,
            name: deviceName,
            manufacturerData: manufacturerData,
            advertisementData: serviceData
        )
        
        Logger.bluetooth.info("Saved device to database: \(deviceName) (\(peripheral.identifier.uuidString))")
    }
}

// MARK: - Central Manager Delegate
extension BluetoothDiscoveryManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // Store the Bluetooth state
        bluetoothState = central.state
        
        // Check for reset flag in UserDefaults
        let wasReset = UserDefaults.standard.bool(forKey: "app_was_reset")
        
        switch central.state {
        case .poweredOn:
            Logger.bluetooth.info("Bluetooth powered ON")
            
            if wasReset {
                // If app was reset, we need to force permission request again
                permissionGranted = false
                showPermissionAlert = true
                // Clear the reset flag
                UserDefaults.standard.removeObject(forKey: "app_was_reset")
            } else {
                permissionGranted = true
                startAdvertising() // Start advertising when BT is powered on
            }
            
        case .poweredOff:
            Logger.bluetooth.info("Bluetooth powered OFF")
            permissionGranted = false
            
        case .unauthorized:
            Logger.bluetooth.error("Bluetooth unauthorized")
            permissionGranted = false
            showPermissionAlert = true
            
        case .unsupported:
            Logger.bluetooth.error("Bluetooth unsupported on this device")
            permissionGranted = false
            
        case .resetting:
            Logger.bluetooth.info("Bluetooth resetting")
            permissionGranted = false
            
        case .unknown:
            Logger.bluetooth.info("Bluetooth state unknown")
            permissionGranted = false
            
        @unknown default:
            Logger.bluetooth.error("Unknown Bluetooth state")
            permissionGranted = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Check if we already discovered this device in the current scan
        let alreadyDiscovered = nearbyDevices.contains { device in
            return device.peripheral.identifier == peripheral.identifier
        }
        
        if !alreadyDiscovered {
            // Log discovery
            Logger.bluetooth.info("Discovered device: \(peripheral.identifier)")
            
            // Add to in-memory list for current session
            nearbyDevices.append((peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI))
            
            // Store device information
            saveDeviceToDatabase(peripheral: peripheral, advertisementData: advertisementData)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.bluetooth.info("Connected to peripheral: \(peripheral.identifier)")
        
        // Add to connected peripherals list if not already there
        if !connectedPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            connectedPeripherals.append(peripheral)
        }
        
        // Discover services
        peripheral.discoverServices([BluetoothDiscoveryManager.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Failed to connect to peripheral: \(peripheral.identifier), error: \(error.localizedDescription)")
        } else {
            Logger.bluetooth.error("Failed to connect to peripheral: \(peripheral.identifier), no error provided")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Logger.bluetooth.info("Disconnected from peripheral: \(peripheral.identifier)")
        
        // Remove from connected peripherals
        connectedPeripherals.removeAll(where: { $0.identifier == peripheral.identifier })
        
        // If error, log it
        if let error = error {
            Logger.bluetooth.error("Disconnect error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Peripheral Delegate
extension BluetoothDiscoveryManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Error discovering services: \(error.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == BluetoothDiscoveryManager.serviceUUID {
                Logger.bluetooth.info("Discovered service: \(service.uuid)")
                
                // Discover the calendar characteristic
                peripheral.discoverCharacteristics([BluetoothDiscoveryManager.calendarCharacteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Error discovering characteristics: \(error.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == BluetoothDiscoveryManager.calendarCharacteristicUUID {
                Logger.bluetooth.info("Discovered characteristic: \(characteristic.uuid)")
                
                // Subscribe to notifications for the characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
}

// MARK: - Peripheral Manager Delegate
extension BluetoothDiscoveryManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            Logger.bluetooth.info("Peripheral manager powered ON")
            permissionGranted = true
            
            // If we have services to advertise, add them now
            if let calendarService = calendarService, !isAdvertising {
                peripheralManager?.add(calendarService)
                // Start advertising now that Bluetooth is powered on
                startAdvertisingService()
            }
            
        case .poweredOff:
            Logger.bluetooth.info("Peripheral manager powered OFF")
            permissionGranted = false
            isAdvertising = false
            
        case .unauthorized:
            Logger.bluetooth.error("Peripheral manager unauthorized")
            permissionGranted = false
            showPermissionAlert = true
            isAdvertising = false
            
        case .unsupported:
            Logger.bluetooth.error("Peripheral manager unsupported")
            permissionGranted = false
            isAdvertising = false
            
        case .resetting:
            Logger.bluetooth.info("Peripheral manager resetting")
            isAdvertising = false
            
        case .unknown:
            Logger.bluetooth.info("Peripheral manager state unknown")
            isAdvertising = false
            
        @unknown default:
            Logger.bluetooth.error("Unknown peripheral manager state")
            isAdvertising = false
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Error adding service: \(error.localizedDescription)")
        } else {
            Logger.bluetooth.info("Service added successfully")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Error starting advertising: \(error.localizedDescription)")
            isAdvertising = false
        } else {
            Logger.bluetooth.info("Advertising started successfully")
            isAdvertising = true
        }
    }
}

// MARK: - Logger Extension
extension Logger {
    static let bluetooth = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.connectwith", category: "Bluetooth")
}