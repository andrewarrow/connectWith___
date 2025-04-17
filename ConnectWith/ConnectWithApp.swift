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
    
    // Delete all devices
    func deleteAllDevices() {
        devices.removeAll()
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @Binding var isComplete: Bool
    @State private var selectedDevice: (peripheral: CBPeripheral, advertisementData: [String: Any])? = nil
    @State private var customName: String = ""
    @State private var isNamingDevice = false
    @State private var hasStartedScanning = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            Text("Find Your First Family Member")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.blue)
                .padding(.top, 40)
                .multilineTextAlignment(.center)
            
            Text("To get started, you need to connect with at least one family member's device")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            // Scanning animation/state
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 15)
                    .frame(width: 250, height: 250)
                
                if bluetoothManager.isScanning {
                    // Animated scanning effect
                    Circle()
                        .trim(from: 0, to: bluetoothManager.scanningProgress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                        .frame(width: 250, height: 250)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: bluetoothManager.scanningProgress)
                    
                    Text("Scanning...")
                        .font(.title2)
                        .foregroundColor(.blue)
                } else if selectedDevice != nil {
                    // Device selected
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Device Found!")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                } else if bluetoothManager.nearbyDevices.isEmpty && hasStartedScanning {
                    // No devices found
                    VStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        
                        Text("No Devices Found")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                } else {
                    // Ready to scan
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Tap to Start Scanning")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
            }
            .onTapGesture {
                if !bluetoothManager.isScanning && selectedDevice == nil {
                    bluetoothManager.startScanning()
                    hasStartedScanning = true
                }
            }
            
            // List of found devices
            if !bluetoothManager.nearbyDevices.isEmpty && selectedDevice == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Devices Found:")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(bluetoothManager.nearbyDevices.indices, id: \.self) { index in
                                let device = bluetoothManager.nearbyDevices[index]
                                OnboardingDeviceRow(device: device) {
                                    selectedDevice = device
                                    
                                    // Pre-fill the custom name field
                                    if let localName = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String {
                                        customName = localName
                                    } else if let name = device.peripheral.name, !name.isEmpty {
                                        customName = name
                                    } else {
                                        customName = "Family Member"
                                    }
                                    
                                    // Show the naming sheet
                                    isNamingDevice = true
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 200)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)
            }
            
            // Action button
            if !bluetoothManager.isScanning && !bluetoothManager.nearbyDevices.isEmpty && selectedDevice == nil {
                Button(action: {
                    bluetoothManager.startScanning()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan Again")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $isNamingDevice) {
            NameDeviceView(
                deviceName: customName,
                onSave: { newName in
                    saveDeviceAndComplete(newName: newName)
                },
                onCancel: {
                    selectedDevice = nil
                    isNamingDevice = false
                }
            )
        }
        .alert("Bluetooth Permission Required", isPresented: $bluetoothManager.showPermissionAlert) {
            Button("Settings", role: .destructive) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("This app needs Bluetooth access to find your family members. Please enable Bluetooth permission in Settings.")
        }
        .onAppear {
            // Clear any previously discovered devices
            bluetoothManager.nearbyDevices.removeAll()
            
            // Start advertising this device
            if bluetoothManager.permissionGranted {
                bluetoothManager.startAdvertising()
            }
        }
    }
    
    private func saveDeviceAndComplete(newName: String) {
        guard let device = selectedDevice else { return }
        
        // Save with custom name
        DeviceStore.shared.saveDevice(
            identifier: device.peripheral.identifier.uuidString,
            name: newName,
            manufacturerData: device.advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            advertisementData: device.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? Data
        )
        
        // Mark onboarding as complete
        isComplete = true
    }
}

struct OnboardingDeviceRow: View {
    let device: (peripheral: CBPeripheral, advertisementData: [String: Any])
    let onSelect: () -> Void
    
    var deviceName: String {
        // First check if this device is already stored with a custom name
        if let storedDevice = DeviceStore.shared.getDevice(identifier: device.peripheral.identifier.uuidString),
           storedDevice.name != "Unknown Device" {
            return storedDevice.name
        }
        
        // Next try to get the name from advertisement data
        if let localName = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
            return localName
        }
        
        // Then try the peripheral name
        if let name = device.peripheral.name, !name.isEmpty {
            return name
        }
        
        // Finally, use a more friendly name with device type if possible
        let myDeviceName = UIDevice.current.name
        return "Nearby Device (\(myDeviceName.prefix(10))...)"
    }
    
    // Check if this device is already in our saved list
    var isSaved: Bool {
        return DeviceStore.shared.getDevice(identifier: device.peripheral.identifier.uuidString) != nil
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                // Device icon with better contrast
                ZStack {
                    Circle()
                        .fill(isSaved ? Color.green : Color.blue)
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "iphone")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                .padding(.trailing, 5)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // Use high-contrast colors for device name
                        Text(deviceName)
                            .font(.headline)
                            .foregroundColor(.black) // Always black for light mode
                        
                        if isSaved {
                            // Improved contrast for "Saved" badge
                            Text("Saved")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(red: 0, green: 0.6, blue: 0)) // Darker green
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    
                    // Always show the identifier as a secondary display item
                    Text(device.peripheral.identifier.uuidString.prefix(8) + "...")
                        .font(.caption)
                        .foregroundColor(Color.black.opacity(0.6)) // Darker gray for better contrast
                    
                    if !isSaved {
                        Text("Tap to rename and save")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.black.opacity(0.5)) // Darker for better contrast
            }
            .padding()
            .background(Color(red: 0.9, green: 0.9, blue: 0.9)) // Slightly darker gray background
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(isSaved ? 0.7 : 1)
    }
}

struct NameDeviceView: View {
    @Environment(\.presentationMode) var presentationMode
    @State var deviceName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Name This Device")
                    .font(.headline)
                    .padding(.top)
                
                Text("You can give this device a more personal name")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 70))
                    .foregroundColor(.blue)
                    .padding()
                
                TextField("Device Name", text: $deviceName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 40)
                    .autocapitalization(.words)
                
                Text("This name will help you identify this device in the future")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                Button(action: {
                    onSave(deviceName)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Save and Continue")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
                .disabled(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationBarItems(
                leading: Button("Cancel") {
                    onCancel()
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

@main
struct TwelveXApp: App {
    @State private var isShowingSplash = true
    @StateObject private var bluetoothManager = BluetoothManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingSplash {
                    SplashScreen(isShowingSplash: $isShowingSplash)
                } else if !hasCompletedOnboarding {
                    OnboardingView(isComplete: $hasCompletedOnboarding)
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
        // Check for reset flag in UserDefaults
        let wasReset = UserDefaults.standard.bool(forKey: "app_was_reset")
        
        switch central.state {
        case .poweredOn:
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