import SwiftUI
import CoreBluetooth
import CoreData
import OSLog

// MARK: - Simple In-Memory Device Store
// Using a simpler approach to avoid CoreData initialization issues
class DeviceStore {
    static let shared = DeviceStore()
    
    struct StoredDevice {
        let identifier: String
        let name: String
        let lastSeen: Date
        var manufacturerData: Data?
        var advertisementData: Data?
    }
    
    // Dictionary to store devices by identifier
    private var devices: [String: StoredDevice] = [:]
    
    // Save or update a device
    func saveDevice(identifier: String, name: String, manufacturerData: Data? = nil, advertisementData: Data? = nil) {
        let device = StoredDevice(
            identifier: identifier,
            name: name,
            lastSeen: Date(),
            manufacturerData: manufacturerData,
            advertisementData: advertisementData
        )
        devices[identifier] = device
    }
    
    // Get all devices
    func getAllDevices() -> [StoredDevice] {
        return Array(devices.values)
            .sorted { $0.lastSeen > $1.lastSeen } // Sort by lastSeen (newest first)
    }
    
    // Get device by identifier
    func getDevice(identifier: String) -> StoredDevice? {
        return devices[identifier]
    }
}

@main
struct ConnectWithApp: App {
    @State private var isShowingSplash = true
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingSplash {
                    SplashScreen(isShowingSplash: $isShowingSplash)
                } else {
                    MainMenuView()
                }
            }
            .environmentObject(bluetoothManager)
        }
    }
}

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate {
    static let serviceUUID = CBUUID(string: "4514d666-d6c9-49cb-bc31-dc6dfa28bd58")
    
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private let deviceStore = DeviceStore.shared
    
    @Published var isScanning = false
    @Published var permissionGranted = false
    @Published var nearbyDevices: [(peripheral: CBPeripheral, advertisementData: [String: Any])] = []
    @Published var scanningProgress: Double = 0.0
    @Published var showPermissionAlert = false
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    private func saveDeviceToDatabase(peripheral: CBPeripheral, advertisementData: [String: Any]) {
        // Determine device name
        let deviceName: String
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            deviceName = localName
        } else if let name = peripheral.name, !name.isEmpty {
            deviceName = name
        } else {
            deviceName = "Unknown Device"
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
        deviceStore.saveDevice(
            identifier: peripheral.identifier.uuidString,
            name: deviceName,
            manufacturerData: manufacturerData,
            advertisementData: serviceData
        )
    }
    
    func startScanning() {
        guard permissionGranted else {
            showPermissionAlert = true
            return
        }
        
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
        
        // Add scanning options to get the local name
        let scanOptions: [String: Any] = [
            // Don't filter duplicate peripherals
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ]
        
        print("Starting scan with options: \(scanOptions)")
        
        // First scan without service UUID filter to get all nearby Bluetooth devices with their names
        print("Starting wide scan to discover all devices")
        centralManager?.scanForPeripherals(withServices: nil, options: scanOptions)
        
        // Also scan for our specific service UUID
        print("Also scanning for our specific service")
        centralManager?.scanForPeripherals(withServices: [BluetoothManager.serviceUUID], options: scanOptions)
        
        // Auto-stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopScanning()
            timer.invalidate()
            self?.scanningProgress = 1.0
        }
    }
    
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
    }
    
    func startAdvertising() {
        guard permissionGranted else {
            showPermissionAlert = true
            return
        }
        
        // Create a service with our UUID
        let service = CBMutableService(type: BluetoothManager.serviceUUID, primary: true)
        
        // Add the service to the peripheral manager
        peripheralManager?.add(service)
        
        // Get personalized device name from settings bundle if available
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
        
        print("My device name: \(deviceName)")
        
        // Start advertising with device name and our service UUID
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BluetoothManager.serviceUUID],
            CBAdvertisementDataLocalNameKey: deviceName
            // Removed CBAdvertisementDataIsConnectable as it's causing a warning
        ]
        
        // Print what we're advertising
        print("Advertising data: \(advertisementData)")
        
        // Start advertising with enhanced data
        peripheralManager?.startAdvertising(advertisementData)
        
        // Confirm advertising started
        print("Advertising started with name: \(deviceName)")
    }
    
    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            permissionGranted = true
            startAdvertising() // Start advertising when BT is powered on
        case .unauthorized:
            permissionGranted = false
            showPermissionAlert = true
        default:
            permissionGranted = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check if we already discovered this device in the current scan
        if !nearbyDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            // Print device info for debugging
            print("Discovered device: \(peripheral.identifier)")
            print("Advertisement data: \(advertisementData)")
            
            // Look specifically for the device name
            if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
                print("Device name from advertisement: \(localName)")
            } else {
                print("No local name in advertisement data")
            }
            
            // Add to in-memory list for current session
            nearbyDevices.append((peripheral: peripheral, advertisementData: advertisementData))
            
            // Store in CoreData database (handles upserts internally)
            saveDeviceToDatabase(peripheral: peripheral, advertisementData: advertisementData)
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            permissionGranted = true
        case .unauthorized:
            permissionGranted = false
            showPermissionAlert = true
        default:
            permissionGranted = false
        }
    }
}