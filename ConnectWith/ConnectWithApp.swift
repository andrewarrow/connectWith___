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

// MARK: - Calendar Event Store & Sync Manager
class CalendarStore: ObservableObject {
    static let shared = CalendarStore()
    
    // Event Sync Status Structure
    struct EventSyncInfo {
        let eventId: UUID
        var syncedWithDevices: [String] // List of device identifiers that have this event
        var lastModifiedBy: String // Device identifier of last modifier
        var lastModifiedDate: Date
        var createdBy: String // Original creator device identifier
        var createdDate: Date
        var changeHistory: [EventChange]
    }
    
    // Change tracking for history and conflict resolution
    struct EventChange: Codable {
        let deviceId: String
        let deviceName: String
        let timestamp: Date
        let changeType: ChangeType
        let fieldChanged: String?
        let oldValue: String?
        let newValue: String?
        
        enum ChangeType: String, Codable {
            case created
            case updated
            case deleted
            case synced
        }
    }
    
    // Main event storage
    @Published private var events: [UUID: CalendarEvent] = [:]
    @Published private var syncInfo: [UUID: EventSyncInfo] = [:]
    
    // This device's identifier
    private var currentDeviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    private var currentDeviceName: String {
        UserDefaults.standard.string(forKey: "DeviceCustomName") ?? UIDevice.current.name
    }
    
    init() {
        // Add some sample events for testing
        loadSampleEvents()
    }
    
    private func loadSampleEvents() {
        // Only load if we have no events yet
        if events.isEmpty {
            let event1 = CalendarEvent(
                id: UUID(),
                title: "Family Picnic",
                date: Date().addingTimeInterval(86400 * 15),
                location: "City Park"
            )
            
            let event2 = CalendarEvent(
                id: UUID(),
                title: "Zoo Trip",
                date: Date().addingTimeInterval(86400 * 45),
                location: "City Zoo"
            )
            
            // Add events to store
            addEvent(event1)
            addEvent(event2)
            
            // Simulate that one event has been synced with 2 family members
            if var syncInfo = self.syncInfo[event1.id] {
                syncInfo.syncedWithDevices = ["device-1", "device-2"]
                syncInfo.changeHistory.append(
                    EventChange(
                        deviceId: "device-1",
                        deviceName: "Mom's iPhone",
                        timestamp: Date().addingTimeInterval(-3600),
                        changeType: .synced,
                        fieldChanged: nil,
                        oldValue: nil,
                        newValue: nil
                    )
                )
                syncInfo.changeHistory.append(
                    EventChange(
                        deviceId: "device-2",
                        deviceName: "Dad's iPhone",
                        timestamp: Date().addingTimeInterval(-1800),
                        changeType: .synced,
                        fieldChanged: nil,
                        oldValue: nil,
                        newValue: nil
                    )
                )
                self.syncInfo[event1.id] = syncInfo
            }
        }
    }
    
    // MARK: - Event Management
    
    func addEvent(_ event: CalendarEvent) {
        events[event.id] = event
        
        // Create sync info for new event
        let newSyncInfo = EventSyncInfo(
            eventId: event.id,
            syncedWithDevices: [], // No other devices have this yet
            lastModifiedBy: currentDeviceId,
            lastModifiedDate: Date(),
            createdBy: currentDeviceId,
            createdDate: Date(),
            changeHistory: [
                EventChange(
                    deviceId: currentDeviceId,
                    deviceName: currentDeviceName,
                    timestamp: Date(),
                    changeType: .created,
                    fieldChanged: nil,
                    oldValue: nil,
                    newValue: nil
                )
            ]
        )
        
        syncInfo[event.id] = newSyncInfo
    }
    
    func updateEvent(_ event: CalendarEvent, changedField: String, oldValue: String, newValue: String) {
        events[event.id] = event
        
        // Update sync info
        if var info = syncInfo[event.id] {
            info.lastModifiedBy = currentDeviceId
            info.lastModifiedDate = Date()
            
            // Add to change history
            info.changeHistory.append(
                EventChange(
                    deviceId: currentDeviceId,
                    deviceName: currentDeviceName,
                    timestamp: Date(),
                    changeType: .updated,
                    fieldChanged: changedField,
                    oldValue: oldValue,
                    newValue: newValue
                )
            )
            
            syncInfo[event.id] = info
        }
    }
    
    func removeEvent(id: UUID) {
        events.removeValue(forKey: id)
        
        // Update sync info for deletion tracking
        if var info = syncInfo[id] {
            info.lastModifiedBy = currentDeviceId
            info.lastModifiedDate = Date()
            
            // Add to change history
            info.changeHistory.append(
                EventChange(
                    deviceId: currentDeviceId,
                    deviceName: currentDeviceName,
                    timestamp: Date(),
                    changeType: .deleted,
                    fieldChanged: nil,
                    oldValue: nil,
                    newValue: nil
                )
            )
            
            // Keep the sync info for deleted events to track deletion across devices
            syncInfo[id] = info
        }
    }
    
    func getAllEvents() -> [CalendarEvent] {
        return Array(events.values).sorted { $0.date < $1.date }
    }
    
    func getEvent(id: UUID) -> CalendarEvent? {
        return events[id]
    }
    
    // MARK: - Sync Management
    
    func getSyncCountForEvent(id: UUID) -> Int {
        return syncInfo[id]?.syncedWithDevices.count ?? 0
    }
    
    func getChangeHistoryForEvent(id: UUID) -> [EventChange] {
        return syncInfo[id]?.changeHistory ?? []
    }
    
    // Methods for Bluetooth sync
    func prepareEventsForSync() -> Data? {
        // Convert events and their sync info to Data for transmission
        let syncPackage = SyncPackage(
            deviceId: currentDeviceId,
            deviceName: currentDeviceName,
            events: Array(events.values),
            syncInfo: syncInfo
        )
        
        return try? JSONEncoder().encode(syncPackage)
    }
    
    func processSyncedEvents(data: Data) -> Int {
        guard let receivedPackage = try? JSONDecoder().decode(SyncPackage.self, from: data) else {
            return 0
        }
        
        var syncedCount = 0
        
        // Process each received event
        for receivedEvent in receivedPackage.events {
            if let existingEvent = events[receivedEvent.id] {
                // Event exists - check which is newer based on sync info
                if let existingInfo = syncInfo[receivedEvent.id],
                   let receivedInfo = receivedPackage.syncInfo[receivedEvent.id] {
                    
                    if receivedInfo.lastModifiedDate > existingInfo.lastModifiedDate {
                        // Received event is newer, update our copy
                        events[receivedEvent.id] = receivedEvent
                        
                        // Merge histories and update sync info
                        var updatedInfo = receivedInfo
                        updatedInfo.syncedWithDevices = Array(Set(existingInfo.syncedWithDevices + receivedInfo.syncedWithDevices + [currentDeviceId, receivedPackage.deviceId]))
                        
                        // Add this sync to change history
                        updatedInfo.changeHistory.append(contentsOf: existingInfo.changeHistory.filter { change in
                            !receivedInfo.changeHistory.contains(where: { $0.deviceId == change.deviceId && $0.timestamp == change.timestamp })
                        })
                        
                        updatedInfo.changeHistory.append(
                            EventChange(
                                deviceId: currentDeviceId,
                                deviceName: currentDeviceName,
                                timestamp: Date(),
                                changeType: .synced,
                                fieldChanged: nil,
                                oldValue: nil,
                                newValue: nil
                            )
                        )
                        
                        syncInfo[receivedEvent.id] = updatedInfo
                        syncedCount += 1
                    } else {
                        // Our event is newer, but still update the sync info
                        var updatedInfo = existingInfo
                        updatedInfo.syncedWithDevices = Array(Set(existingInfo.syncedWithDevices + receivedInfo.syncedWithDevices + [currentDeviceId, receivedPackage.deviceId]))
                        
                        // Add histories from the other device that we don't have
                        updatedInfo.changeHistory.append(contentsOf: receivedInfo.changeHistory.filter { change in
                            !existingInfo.changeHistory.contains(where: { $0.deviceId == change.deviceId && $0.timestamp == change.timestamp })
                        })
                        
                        syncInfo[receivedEvent.id] = updatedInfo
                        syncedCount += 1
                    }
                }
            } else {
                // New event - add it
                events[receivedEvent.id] = receivedEvent
                
                if var receivedInfo = receivedPackage.syncInfo[receivedEvent.id] {
                    // Add this device to the synced devices list
                    receivedInfo.syncedWithDevices = Array(Set(receivedInfo.syncedWithDevices + [currentDeviceId]))
                    
                    // Add a sync record to the history
                    receivedInfo.changeHistory.append(
                        EventChange(
                            deviceId: currentDeviceId,
                            deviceName: currentDeviceName,
                            timestamp: Date(),
                            changeType: .synced,
                            fieldChanged: nil,
                            oldValue: nil,
                            newValue: nil
                        )
                    )
                    
                    syncInfo[receivedEvent.id] = receivedInfo
                    syncedCount += 1
                }
            }
        }
        
        // Process deleted events from the other device
        for (eventId, receivedInfo) in receivedPackage.syncInfo {
            // Check if this is a deletion event that we don't have
            let isDeletedOnOtherDevice = receivedInfo.changeHistory.contains(where: { $0.changeType == .deleted })
            let eventExistsLocally = events[eventId] != nil
            
            if isDeletedOnOtherDevice && eventExistsLocally {
                // Event was deleted on other device but we still have it
                // Apply deletion based on last modified timestamp
                if let localInfo = syncInfo[eventId], 
                   receivedInfo.lastModifiedDate > localInfo.lastModifiedDate {
                    events.removeValue(forKey: eventId)
                    
                    // Update our sync info to reflect deletion
                    var updatedInfo = receivedInfo
                    updatedInfo.syncedWithDevices = Array(Set(localInfo.syncedWithDevices + receivedInfo.syncedWithDevices + [currentDeviceId]))
                    
                    updatedInfo.changeHistory.append(contentsOf: localInfo.changeHistory.filter { change in
                        !receivedInfo.changeHistory.contains(where: { $0.deviceId == change.deviceId && $0.timestamp == change.timestamp })
                    })
                    
                    syncInfo[eventId] = updatedInfo
                    syncedCount += 1
                }
            }
        }
        
        return syncedCount
    }
    
    // Structure for sending sync data
    struct SyncPackage: Codable {
        let deviceId: String
        let deviceName: String
        let events: [CalendarEvent]
        let syncInfo: [UUID: EventSyncInfo]
    }
}

// Make EventSyncInfo Codable for sync
extension CalendarStore.EventSyncInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case eventId, syncedWithDevices, lastModifiedBy, lastModifiedDate, createdBy, createdDate, changeHistory
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @Binding var isComplete: Bool
    @State private var selectedDevice: (peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)? = nil
    @State private var customName: String = ""
    @State private var isNamingDevice = false
    @State private var hasStartedScanning = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            OnboardingHeaderView()
            
            Spacer()
            
            // Scanning animation/state
            ScanningStateView(
                isScanning: bluetoothManager.isScanning,
                scanningProgress: bluetoothManager.scanningProgress,
                hasSelectedDevice: selectedDevice != nil,
                deviceCount: bluetoothManager.nearbyDevices.count,
                hasStartedScanning: hasStartedScanning,
                onTapAction: {
                    if !bluetoothManager.isScanning && selectedDevice == nil {
                        bluetoothManager.startScanning()
                        hasStartedScanning = true
                    }
                }
            )
            
            // List of found devices
            if !bluetoothManager.nearbyDevices.isEmpty && selectedDevice == nil {
                OnboardingDeviceListView(
                    devices: bluetoothManager.nearbyDevices,
                    onSelectDevice: { device in
                        selectedDevice = device
                        
                        // Pre-fill the custom name field
                        setInitialCustomName(for: device)
                        
                        // Show the naming sheet
                        isNamingDevice = true
                    }
                )
            }
            
            // Action button
            if !bluetoothManager.isScanning && !bluetoothManager.nearbyDevices.isEmpty && selectedDevice == nil {
                ScanAgainButton {
                    bluetoothManager.startScanning()
                }
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
    
    private func setInitialCustomName(for device: (peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)) {
        if let localName = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            customName = localName
        } else if let name = device.peripheral.name, !name.isEmpty {
            customName = name
        } else {
            customName = "Family Member"
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

// MARK: - Extracted Components for OnboardingView

struct OnboardingHeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
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
        }
    }
}

struct ScanningStateView: View {
    let isScanning: Bool
    let scanningProgress: Double
    let hasSelectedDevice: Bool
    let deviceCount: Int
    let hasStartedScanning: Bool
    let onTapAction: () -> Void
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 15)
                .frame(width: 250, height: 250)
            
            if isScanning {
                // Animated scanning effect
                Circle()
                    .trim(from: 0, to: scanningProgress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                    .frame(width: 250, height: 250)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear, value: scanningProgress)
                
                Text("Scanning...")
                    .font(.title2)
                    .foregroundColor(.blue)
            } else if hasSelectedDevice {
                // Device selected
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text("Device Found!")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            } else if deviceCount == 0 && hasStartedScanning {
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
        .onTapGesture(perform: onTapAction)
    }
}

struct OnboardingDeviceListView: View {
    let devices: [(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)]
    let onSelectDevice: ((peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Devices Found:")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(devices.enumerated()), id: \.offset) { (_, device) in
                        OnboardingDeviceRow(device: device) {
                            onSelectDevice(device)
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
}

struct ScanAgainButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
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
}

struct OnboardingDeviceRow: View {
    let device: (peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)
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
struct FamilyCalendarApp: App {
    @State private var isShowingSplash = true
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var calendarStore = CalendarStore.shared
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
            .environmentObject(calendarStore)
        }
    }
}

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate, CBPeripheralDelegate {
    static let serviceUUID = CBUUID(string: "4514d666-d6c9-49cb-bc31-dc6dfa28bd58")
    static let calendarCharacteristicUUID = CBUUID(string: "97d52a22-9292-48c6-a89f-8a71d89c5e9b")
    
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private let deviceStore = DeviceStore.shared
    private let calendarStore = CalendarStore.shared
    
    private var calendarService: CBMutableService?
    private var calendarCharacteristic: CBMutableCharacteristic?
    
    // Made accessible for debug view
    @Published var connectedPeripherals: [CBPeripheral] = []
    @Published var isScanning = false
    @Published var permissionGranted = false
    @Published var nearbyDevices: [(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)] = []
    @Published var scanningProgress: Double = 0.0
    @Published var showPermissionAlert = false
    @Published var syncInProgress = false
    @Published var lastSyncTime: Date?
    @Published var lastSyncDeviceName: String?
    @Published var syncedEventsCount = 0
    
    // Debug-specific properties
    @Published var isAdvertising = false
    var deviceName: String {
        UserDefaults.standard.string(forKey: "DeviceCustomName") ?? UIDevice.current.name
    }
    @Published var lastTransferredData: Data?
    @Published var lastTransferDirection: String = "None"
    @Published var lastTransferTimestamp: Date?
    
    // Sync logs for debugging
    struct SyncLogEntry {
        let timestamp: Date
        let deviceName: String
        let action: String
        let details: String
    }
    @Published var syncLog: [SyncLogEntry] = []
    
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
        
        // Create calendar characteristic
        calendarCharacteristic = CBMutableCharacteristic(
            type: BluetoothManager.calendarCharacteristicUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        
        // Create a service with our UUID
        calendarService = CBMutableService(type: BluetoothManager.serviceUUID, primary: true)
        
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
    
    // Helper method to start advertising after ensuring peripheral manager is ready
    private func startAdvertisingService() {
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
        // Remove the problematic CBAdvertisementDataIsConnectable key
        let advertisementData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BluetoothManager.serviceUUID],
            CBAdvertisementDataLocalNameKey: deviceName
        ]
        
        // Print what we're advertising
        print("Advertising data: \(advertisementData)")
        
        // Start advertising with enhanced data
        peripheralManager?.startAdvertising(advertisementData)
        
        // Update state for debug
        isAdvertising = true
        
        // Add to sync log
        addSyncLogEntry(
            deviceName: "This Device",
            action: "Started Advertising",
            details: "Service: \(BluetoothManager.serviceUUID.uuidString), Name: \(deviceName)"
        )
        
        // Confirm advertising started
        print("Advertising started with name: \(deviceName)")
    }
    
    // MARK: - Calendar Sync Methods
    
    func setupBackgroundSync() {
        // Schedule background scanning to periodically look for family members
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Only scan if we're not already scanning
            if !self.isScanning && self.permissionGranted {
                print("Starting background scan for family members...")
                self.scanAndSyncWithFamilyMembers()
            }
        }
    }
    
    func scanAndSyncWithFamilyMembers() {
        // Only start if we're not already scanning
        guard !isScanning && permissionGranted else { return }
        
        // Set scanning state
        isScanning = true
        syncInProgress = true
        
        // Start scanning for our specific service UUID
        let scanOptions: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ]
        
        centralManager?.scanForPeripherals(withServices: [BluetoothManager.serviceUUID], options: scanOptions)
        
        // Auto-stop scanning after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self else { return }
            self.centralManager?.stopScan()
            self.isScanning = false
            
            // If we found any devices, connect to them
            if !self.nearbyDevices.isEmpty {
                for device in self.nearbyDevices {
                    // Only connect to known family members
                    if DeviceStore.shared.getDevice(identifier: device.peripheral.identifier.uuidString) != nil {
                        self.connectToDevice(device.peripheral)
                    }
                }
            } else {
                // No devices found, end sync
                self.syncInProgress = false
            }
        }
    }
    
    func connectToDevice(_ peripheral: CBPeripheral) {
        peripheral.delegate = self
        centralManager?.connect(peripheral, options: nil)
    }
    
    // MARK: - Calendar Data Transfer
    
    private func sendCalendarData(to peripheral: CBPeripheral) {
        // Find the calendar characteristic
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == BluetoothManager.serviceUUID {
                peripheral.discoverCharacteristics([BluetoothManager.calendarCharacteristicUUID], for: service)
            }
        }
    }
    
    private func syncCalendarData() {
        // Get calendar data to send
        guard let calendarData = calendarStore.prepareEventsForSync() else { return }
        
        // Update the characteristic value
        calendarCharacteristic?.value = calendarData
        
        // Update debug properties
        lastTransferredData = calendarData
        lastTransferDirection = "Sent (as Peripheral)"
        lastTransferTimestamp = Date()
        
        // Add to sync log
        addSyncLogEntry(
            deviceName: "This Device",
            action: "Sent Calendar Data (Peripheral)",
            details: "Size: \(calendarData.count) bytes"
        )
        
        // Notify subscribers that the value has changed
        if let calendarCharacteristic = calendarCharacteristic {
            peripheralManager?.updateValue(calendarData, for: calendarCharacteristic, onSubscribedCentrals: nil)
        }
    }
    
    func stopAdvertising() {
        if isAdvertising {
            peripheralManager?.stopAdvertising()
            isAdvertising = false
            
            // Add to sync log
            addSyncLogEntry(
                deviceName: "This Device",
                action: "Stopped Advertising",
                details: ""
            )
        }
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
                setupBackgroundSync() // Setup background sync timer
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
        let alreadyDiscovered = nearbyDevices.contains { device in
            return device.peripheral.identifier == peripheral.identifier
        }
        
        if !alreadyDiscovered {
            // Print device info for debugging
            print("Discovered device: \(peripheral.identifier)")
            print("Advertisement data: \(advertisementData)")
            print("RSSI: \(RSSI)")
            
            // Look specifically for the device name
            if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
                print("Device name from advertisement: \(localName)")
            } else {
                print("No local name in advertisement data")
            }
            
            // Add to in-memory list for current session
            nearbyDevices.append((peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI))
            
            // Store in CoreData database (handles upserts internally)
            saveDeviceToDatabase(peripheral: peripheral, advertisementData: advertisementData)
            
            // Add to sync log for debug view
            let deviceName = getDeviceName(peripheral: peripheral, advertisementData: advertisementData)
            let servicesDesc = advertisementData[CBAdvertisementDataServiceUUIDsKey] != nil ? "Present" : "None"
            addSyncLogEntry(deviceName: deviceName, action: "Discovered", details: "RSSI: \(RSSI), Services: \(servicesDesc)")
        }
    }
    
    // Helper method to get device name for logs
    private func getDeviceName(peripheral: CBPeripheral, advertisementData: [String: Any]) -> String {
        if let storedDevice = deviceStore.getDevice(identifier: peripheral.identifier.uuidString) {
            return storedDevice.name
        } else if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
            return localName
        } else if let name = peripheral.name, !name.isEmpty {
            return name
        } else {
            return "Unknown Device (\(peripheral.identifier.uuidString.prefix(8)))"
        }
    }
    
    // Helper method to add sync log entries for debug view
    private func addSyncLogEntry(deviceName: String, action: String, details: String = "") {
        let entry = SyncLogEntry(
            timestamp: Date(),
            deviceName: deviceName,
            action: action,
            details: details
        )
        syncLog.append(entry)
        
        // Trim log if it gets too long
        if syncLog.count > 100 {
            syncLog.removeFirst()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.identifier)")
        
        // Add to connected peripherals list
        if !connectedPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            connectedPeripherals.append(peripheral)
        }
        
        // Discover services
        peripheral.discoverServices([BluetoothManager.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to peripheral: \(peripheral.identifier), error: \(error?.localizedDescription ?? "unknown")")
        
        // Check if we've connected to all peripherals, if so, end sync
        checkSyncComplete()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("Disconnected from peripheral: \(peripheral.identifier)")
        
        // Remove from connected peripherals
        connectedPeripherals.removeAll(where: { $0.identifier == peripheral.identifier })
        
        // Check if we've disconnected from all peripherals, if so, end sync
        checkSyncComplete()
    }
    
    private func checkSyncComplete() {
        if connectedPeripherals.isEmpty {
            syncInProgress = false
        }
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == BluetoothManager.serviceUUID {
                // Discover the calendar characteristic
                peripheral.discoverCharacteristics([BluetoothManager.calendarCharacteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == BluetoothManager.calendarCharacteristicUUID {
                // Subscribe to notifications for the characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                
                // Read the current value 
                peripheral.readValue(for: characteristic)
                
                // Also send our calendar data to the peripheral
                if let calendarData = calendarStore.prepareEventsForSync() {
                    peripheral.writeValue(calendarData, for: characteristic, type: .withResponse)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == BluetoothManager.calendarCharacteristicUUID {
            if let data = characteristic.value {
                // Process received calendar data
                let syncCount = calendarStore.processSyncedEvents(data: data)
                
                // Update sync status
                syncedEventsCount += syncCount
                lastSyncTime = Date()
                lastTransferTimestamp = Date()
                
                // For debug view
                lastTransferredData = data
                lastTransferDirection = "Received (as Central)"
                
                // Get the device name
                if let storedDevice = DeviceStore.shared.getDevice(identifier: peripheral.identifier.uuidString) {
                    lastSyncDeviceName = storedDevice.name
                } else if let name = peripheral.name {
                    lastSyncDeviceName = name
                } else {
                    lastSyncDeviceName = "Unknown Device"
                }
                
                print("Synced \(syncCount) events with \(lastSyncDeviceName ?? "Unknown Device")")
                
                // Add to sync log
                addSyncLogEntry(
                    deviceName: lastSyncDeviceName ?? "Unknown Device",
                    action: "Received Calendar Data",
                    details: "Size: \(data.count) bytes, Events: \(syncCount)"
                )
                
                // If there was an error, log it
                if let error = error {
                    addSyncLogEntry(
                        deviceName: lastSyncDeviceName ?? "Unknown Device",
                        action: "Error",
                        details: error.localizedDescription
                    )
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == BluetoothManager.calendarCharacteristicUUID {
            print("Calendar data sent to \(peripheral.identifier)")
            
            // Update debug info
            lastTransferDirection = "Sent (as Central)"
            lastTransferTimestamp = Date()
            
            // Get device name for debug
            let deviceName = getDeviceName(peripheral: peripheral, advertisementData: [:])
            
            // Add to sync log
            addSyncLogEntry(
                deviceName: deviceName,
                action: "Sent Calendar Data",
                details: "To peripheral: \(peripheral.identifier.uuidString)"
            )
            
            // If there was an error, log it
            if let error = error {
                addSyncLogEntry(
                    deviceName: deviceName,
                    action: "Error",
                    details: error.localizedDescription
                )
            }
            
            // Disconnect after successful write
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            permissionGranted = true
            
            // If we have services to advertise, add them now
            if let calendarService = calendarService, !isAdvertising {
                peripheralManager?.add(calendarService)
                // Start advertising now that Bluetooth is powered on
                startAdvertisingService()
            }
        case .unauthorized:
            permissionGranted = false
            showPermissionAlert = true
            isAdvertising = false
        default:
            permissionGranted = false
            isAdvertising = false
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == BluetoothManager.calendarCharacteristicUUID {
            // Prepare calendar data to send
            if let calendarData = calendarStore.prepareEventsForSync() {
                // Set the value on the request
                request.value = calendarData
                
                // Respond to the request
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .unlikelyError)
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == BluetoothManager.calendarCharacteristicUUID {
                if let data = request.value {
                    // Process received calendar data
                    let syncCount = calendarStore.processSyncedEvents(data: data)
                    
                    // Update sync status
                    syncedEventsCount += syncCount
                    lastSyncTime = Date()
                    lastTransferTimestamp = Date()
                    
                    // For debug view
                    lastTransferredData = data
                    lastTransferDirection = "Received"
                    
                    print("Processed \(syncCount) events from peripheral write")
                    
                    // Log for debug view
                    let centralIdentifier = request.central.identifier.uuidString
                    var deviceName = "Unknown Device"
                    if let storedDevice = deviceStore.getDevice(identifier: centralIdentifier) {
                        deviceName = storedDevice.name
                    }
                    
                    // Add to sync log
                    addSyncLogEntry(
                        deviceName: deviceName,
                        action: "Received Data",
                        details: "Size: \(data.count) bytes, Events: \(syncCount)"
                    )
                }
            }
        }
        
        // Respond to all requests with success
        peripheral.respond(to: requests[0], withResult: .success)
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Notify subscribers with updated calendar data
        syncCalendarData()
    }
}