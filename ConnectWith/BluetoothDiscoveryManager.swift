import Foundation
import CoreBluetooth
import OSLog
import CoreMotion

// MARK: - Bluetooth Scanning Profile
enum BluetoothScanningProfile: String, CaseIterable {
    case aggressive  // High frequency scanning for active usage
    case normal      // Standard scanning for regular operation
    case conservative // Reduced scanning frequency for battery saving
    
    var scanDuration: TimeInterval {
        switch self {
        case .aggressive: return 10.0
        case .normal: return 5.0
        case .conservative: return 3.0
        }
    }
    
    var scanInterval: TimeInterval {
        switch self {
        case .aggressive: return 30.0
        case .normal: return 120.0
        case .conservative: return 300.0
        }
    }
    
    var allowDuplicates: Bool {
        switch self {
        case .aggressive: return true
        case .normal, .conservative: return false
        }
    }
}

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
    
    // Motion manager for adaptive scanning
    private let motionManager = CMMotionActivityManager()
    private var isMotionActive = false
    
    // Scanning cycles
    private var scanTimer: Timer?
    private var scanCycleTimer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // MARK: - Bluetooth State Properties
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var permissionGranted = false
    @Published var showPermissionAlert = false
    @Published var isScanning = false
    @Published var isAdvertising = false
    @Published var scanningProgress: Double = 0.0
    @Published var currentScanningProfile: BluetoothScanningProfile = .normal {
        didSet {
            UserDefaults.standard.set(currentScanningProfile.rawValue, forKey: "CurrentScanningProfile")
            // If we change profiles, restart scanning with new parameters
            if isScanning {
                stopScanning()
                startAdaptiveScanning()
            }
            Logger.bluetooth.info("Scanning profile changed to \(self.currentScanningProfile.rawValue)")
        }
    }
    
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
        loadScanningProfile()
        startMotionDetection()
    }
    
    deinit {
        scanTimer?.invalidate()
        scanCycleTimer?.invalidate()
        motionManager.stopActivityUpdates()
    }
    
    // MARK: - Setup Methods
    
    private func setupBluetooth() {
        // Initialize the central manager (for discovering other devices)
        centralManager = CBCentralManager(delegate: self, queue: nil)
        
        // Initialize the peripheral manager (for being discovered)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        // Log initialization
        Logger.bluetooth.info("BluetoothDiscoveryManager initialized")
        
        // Register for app lifecycle notifications
        NotificationCenter.default.addObserver(self, 
                                              selector: #selector(handleApplicationWillResignActive), 
                                              name: UIApplication.willResignActiveNotification, 
                                              object: nil)
        
        NotificationCenter.default.addObserver(self, 
                                              selector: #selector(handleApplicationDidBecomeActive), 
                                              name: UIApplication.didBecomeActiveNotification, 
                                              object: nil)
        
        NotificationCenter.default.addObserver(self, 
                                              selector: #selector(handleApplicationDidEnterBackground), 
                                              name: UIApplication.didEnterBackgroundNotification, 
                                              object: nil)
    }
    
    private func loadScanningProfile() {
        // Load the last used scanning profile from UserDefaults
        if let profileValue = UserDefaults.standard.string(forKey: "CurrentScanningProfile"),
           let profile = BluetoothScanningProfile(rawValue: profileValue) {
            currentScanningProfile = profile
        } else {
            // Default to normal profile
            currentScanningProfile = .normal
        }
    }
    
    private func startMotionDetection() {
        // Check if motion activity is available
        if CMMotionActivityManager.isActivityAvailable() {
            let queue = OperationQueue()
            motionManager.startActivityUpdates(to: queue) { [weak self] activity in
                guard let activity = activity, let self = self else { return }
                
                // Determine if the device is actively moving
                let isMoving = activity.walking || activity.running || activity.automotive
                
                // Only update if the state has changed
                if isMoving != self.isMotionActive {
                    self.isMotionActive = isMoving
                    
                    // If moving, increase scanning frequency
                    DispatchQueue.main.async {
                        if isMoving && self.currentScanningProfile == .conservative {
                            self.currentScanningProfile = .normal
                            Logger.bluetooth.info("Motion detected, increased scanning frequency")
                        } else if !isMoving && self.currentScanningProfile == .aggressive {
                            self.currentScanningProfile = .normal
                            Logger.bluetooth.info("Device stationary, normalized scanning frequency")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Application Lifecycle Methods
    
    @objc private func handleApplicationWillResignActive() {
        // App is about to go into background or be interrupted
        stopScanning()
        
        // Ensure we keep advertising in background
        if !isAdvertising {
            startAdvertising()
        }
    }
    
    @objc private func handleApplicationDidBecomeActive() {
        // App came to foreground
        if permissionGranted {
            // Start scanning when app becomes active
            startAdaptiveScanning()
        }
    }
    
    @objc private func handleApplicationDidEnterBackground() {
        // App is now in background
        // Start background task to ensure we complete current operations
        startBackgroundTask()
        
        // If Bluetooth is permitted, set up adaptive background scanning
        if permissionGranted {
            // Stop any current scanning
            stopScanning()
            
            // Schedule periodic background scanning with battery optimization
            schedulePeriodicBackgroundScanning()
            
            // Start an immediate scan
            startBackgroundScanning()
            
            Logger.bluetooth.info("Background mode: started adaptive Bluetooth scanning")
        }
    }
    
    private func startBackgroundTask() {
        // End any existing background task
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        
        // Start a new background task
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // Clean up if the background task expires
            guard let self = self else { return }
            
            // Stop scanning to conserve battery
            self.stopScanning()
            
            // End the task
            if self.backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
    }
    
    // MARK: - Scanning Methods
    
    /// Starts a continuous adaptive scanning cycle based on the current profile
    func startAdaptiveScanning() {
        guard permissionGranted else {
            showPermissionAlert = true
            return
        }
        
        Logger.bluetooth.info("Starting adaptive scanning with profile: \(currentScanningProfile.rawValue)")
        
        // Stop any existing scanning
        stopScanning()
        
        // Start the first scan
        startScan()
        
        // Schedule future scans based on profile
        scanCycleTimer = Timer.scheduledTimer(withTimeInterval: currentScanningProfile.scanInterval, repeats: true) { [weak self] _ in
            self?.startScan()
        }
    }
    
    /// Starts a single scan operation with the current profile settings
    private func startScan() {
        guard permissionGranted, !isScanning, 
              centralManager?.state == .poweredOn else { return }
        
        Logger.bluetooth.info("Starting Bluetooth scan with profile: \(currentScanningProfile.rawValue)")
        
        // Clear previous scan results if this is not a continuous scan
        if !isScanning {
            nearbyDevices.removeAll()
        }
        
        isScanning = true
        scanningProgress = 0.0
        
        // Start the scanning progress animation
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            let duration = self.currentScanningProfile.scanDuration
            let increment = 0.1 / duration // Adjust progress based on scan duration
            
            if self.scanningProgress < 1.0 {
                self.scanningProgress += increment
            } else {
                timer.invalidate()
            }
        }
        
        // Scan options based on profile
        let scanOptions: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: currentScanningProfile.allowDuplicates
        ]
        
        // First scan without service UUID filter to get all nearby Bluetooth devices
        centralManager?.scanForPeripherals(withServices: nil, options: scanOptions)
        
        // Also scan for our specific service UUID
        centralManager?.scanForPeripherals(withServices: [BluetoothDiscoveryManager.serviceUUID], options: scanOptions)
        
        // Auto-stop scanning after the profile-specified duration
        scanTimer = Timer.scheduledTimer(withTimeInterval: currentScanningProfile.scanDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            self.centralManager?.stopScan()
            self.isScanning = false
            self.scanningProgress = 1.0
            timer.invalidate()
            
            Logger.bluetooth.info("Bluetooth scan completed")
        }
    }
    
    /// Starts low-power background scanning for nearby devices with battery optimization
    private func startBackgroundScanning() {
        guard permissionGranted, centralManager?.state == .poweredOn else { return }
        
        // Optimize scanning parameters based on device state
        optimizeScanningForBatteryAndContext()
        
        Logger.bluetooth.info("Starting background scanning with \(currentScanningProfile.rawValue) profile")
        
        // In background mode, we only scan for our specific service to save battery
        let scanOptions: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ]
        
        // Only scan for our specific service in background
        centralManager?.scanForPeripherals(withServices: [BluetoothDiscoveryManager.serviceUUID], options: scanOptions)
        isScanning = true
        
        // Use scan duration based on the current profile
        let scanDuration: TimeInterval
        
        switch currentScanningProfile {
        case .aggressive:
            scanDuration = 5.0
        case .normal:
            scanDuration = 3.0
        case .conservative:
            scanDuration = 2.0
        }
        
        // End scan after the determined duration
        DispatchQueue.main.asyncAfter(deadline: .now() + scanDuration) { [weak self] in
            guard let self = self else { return }
            
            self.centralManager?.stopScan()
            self.isScanning = false
            
            // Log scan completion
            Logger.bluetooth.info("Background scan completed")
            
            // If we discover any devices, update their database entries
            if !self.nearbyDevices.isEmpty {
                Logger.bluetooth.info("Found \(self.nearbyDevices.count) devices during background scan")
                
                // Get the last seen devices
                let recentDevices = self.nearbyDevices.suffix(min(self.nearbyDevices.count, 5))
                
                // Log the most recently seen devices
                for device in recentDevices {
                    let name = device.peripheral.name ?? "Unknown"
                    let id = device.peripheral.identifier.uuidString
                    Logger.bluetooth.info("Recent device: \(name) (\(id))")
                }
            }
            
            // Continue with the scheduled scanning cycle
            // The schedulePeriodicBackgroundScanning method handles when to run the next scan
        }
    }
    
    /// Stops an active Bluetooth scan
    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
        
        scanCycleTimer?.invalidate()
        scanCycleTimer = nil
        
        centralManager?.stopScan()
        isScanning = false
        Logger.bluetooth.info("Bluetooth scan stopped")
    }
    
    /// Changes the scanning profile
    func changeScanningProfile(to profile: BluetoothScanningProfile) {
        currentScanningProfile = profile
    }
    
    // MARK: - Advertising Methods
    
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
    
    // MARK: - Connection Methods
    
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
    
    // MARK: - Battery Optimization Methods
    
    /// Returns the appropriate scanning profile based on time of day and battery level
    func determineOptimalScanningProfile() -> BluetoothScanningProfile {
        // Check battery level first
        let batteryLevel = UIDevice.current.batteryLevel
        if batteryLevel < 0.2 { // Below 20%
            return .conservative
        }
        
        // Check time of day
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        
        // Night-time hours (10pm - 6am), reduce scanning
        if hour < 6 || hour >= 22 {
            return .conservative
        }
        
        // Active hours but device not moving, use normal
        if !isMotionActive {
            return .normal
        }
        
        // Active hours and device is moving, use aggressive scanning
        return .aggressive
    }
    
    /// Adjusts the scanning profile based on device state and environment
    func adaptScanningProfile() {
        let newProfile = determineOptimalScanningProfile()
        
        // Only update if it's different
        if newProfile != currentScanningProfile {
            Logger.bluetooth.info("Adapting scanning profile from \(currentScanningProfile.rawValue) to \(newProfile.rawValue)")
            currentScanningProfile = newProfile
        }
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
    
    /// Saves a discovered device to the database using FamilyDeviceRepository
    private func saveDeviceToDatabase(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        // Use DataManager to handle the persistence
        let dataManager = DataManager.shared
        let deviceId = peripheral.identifier.uuidString
        let deviceName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        
        // Check if this device has our service UUID
        let hasCalendarService = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.contains(BluetoothDiscoveryManager.serviceUUID) ?? false
        
        // Perform operations in background to avoid UI blocking
        PersistenceController.shared.performBackgroundTask { context in
            let familyDeviceRepository = FamilyDeviceRepository(context: context)
            
            // Check if device already exists
            if let existingDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: deviceId) {
                // Update last seen timestamp
                existingDevice.lastSyncTimestamp = Date()
                
                // Update name if it has changed
                if let name = deviceName, existingDevice.customName == nil || existingDevice.customName?.isEmpty == true {
                    existingDevice.customName = name
                }
                
                Logger.bluetooth.info("Updated existing device in database: \(existingDevice.customName ?? "Unknown") (\(deviceId))")
            } else {
                // Only store devices that have our service or have a name (potential family devices)
                if hasCalendarService || deviceName != nil {
                    // Create a new family device
                    let newDevice = FamilyDevice.create(
                        in: context,
                        bluetoothIdentifier: deviceId,
                        customName: deviceName,
                        isLocalDevice: false
                    )
                    Logger.bluetooth.info("Saved new device to database: \(newDevice.customName ?? "Unknown") (\(deviceId))")
                }
            }
            
            // Save the changes
            try? context.save()
            
            // If this device has our service, also create a BluetoothDevice entry for direct access
            if hasCalendarService {
                self.saveBluetoothDeviceInfo(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi, context: context)
            }
        }
    }
    
    /// Save detailed Bluetooth device information
    private func saveBluetoothDeviceInfo(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber, context: NSManagedObjectContext) {
        let deviceId = peripheral.identifier.uuidString
        
        // Create fetch request
        let fetchRequest = BluetoothDevice.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "identifier == %@", deviceId)
        
        do {
            // Try to fetch existing device
            let results = try context.fetch(fetchRequest)
            let device: BluetoothDevice
            
            if let existingDevice = results.first {
                // Update existing device
                device = existingDevice
            } else {
                // Create new device
                device = BluetoothDevice(context: context)
                device.identifier = deviceId
            }
            
            // Update device details
            device.update(from: peripheral, advertisementData: advertisementData, rssi: rssi)
            
            // Save changes
            try context.save()
            
            Logger.bluetooth.info("BluetoothDevice saved to database: \(device.deviceName ?? "Unknown") (\(deviceId))")
        } catch {
            Logger.bluetooth.error("Failed to save BluetoothDevice to database: \(error.localizedDescription)")
        }
    }
    
    /// Retrieves family devices from database that support 12x sync
    func getFamilyDevicesFromDatabase() -> [FamilyDevice] {
        // Use DataManager to handle the persistence
        let dataManager = DataManager.shared
        return dataManager.getAllDevices()
    }
    
    /// Retrieves detailed Bluetooth devices from database that support 12x sync
    func getBluetoothDevicesFromDatabase() -> [BluetoothDevice] {
        let persistenceController = PersistenceController.shared
        let context = persistenceController.container.viewContext
        
        // Create fetch request
        let fetchRequest = BluetoothDevice.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "lastSeen", ascending: false)]
        
        do {
            let devices = try context.fetch(fetchRequest)
            // Filter for devices that support our service
            return devices.filter { $0.supports12xSync }
        } catch {
            Logger.bluetooth.error("Failed to fetch bluetooth devices from database: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Purges old devices from the database that haven't been seen in a long time
    func purgeOldDevices(olderThan days: Int = 30) {
        // Perform operations in background to avoid UI blocking
        PersistenceController.shared.performBackgroundTask { context in
            // Calculate cutoff date
            let calendar = Calendar.current
            guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
                return
            }
            
            // First, purge old BluetoothDevice entries
            let fetchRequest = BluetoothDevice.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "lastSeen < %@", cutoffDate as NSDate)
            
            do {
                let oldDevices = try context.fetch(fetchRequest)
                
                // Delete old devices
                for device in oldDevices {
                    context.delete(device)
                    Logger.bluetooth.info("Purged old BluetoothDevice: \(device.deviceName ?? "Unknown") (\(device.identifier))")
                }
                
                // Save changes
                if !oldDevices.isEmpty {
                    try context.save()
                    Logger.bluetooth.info("Purged \(oldDevices.count) old BluetoothDevice entries from database")
                }
            } catch {
                Logger.bluetooth.error("Failed to purge old BluetoothDevice entries: \(error.localizedDescription)")
            }
            
            // Next, purge old FamilyDevice entries that haven't been synced recently
            let familyDeviceRepository = FamilyDeviceRepository(context: context)
            let familyDevicePredicate = NSPredicate(format: "lastSyncTimestamp < %@ AND isLocalDevice == NO", cutoffDate as NSDate)
            let oldFamilyDevices = familyDeviceRepository.fetch(predicate: familyDevicePredicate)
            
            // Only delete family devices that haven't been seen for a long time and aren't local
            for device in oldFamilyDevices {
                Logger.bluetooth.info("Purging old FamilyDevice: \(device.customName ?? "Unknown") (\(device.bluetoothIdentifier))")
                try? familyDeviceRepository.delete(device)
            }
            
            Logger.bluetooth.info("Database maintenance completed: purged old devices not seen since \(cutoffDate)")
        }
    }
    
    /// Optimizes the scanning profile based on current battery level, time of day, and motion status
    func optimizeScanningForBatteryAndContext() {
        // Check battery level
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        
        // Determine optimal profile
        var newProfile = currentScanningProfile
        
        // If battery is critically low, or device is charging, adjust accordingly
        if batteryLevel < 0.15 && batteryState != .charging {
            // Very low battery, use conservative mode
            newProfile = .conservative
            Logger.bluetooth.info("Battery level critical (\(batteryLevel * 100)%), switching to conservative scanning")
        } else if batteryState == .charging {
            // Device is charging, can use more power
            newProfile = .normal
            Logger.bluetooth.info("Device is charging, using normal scanning")
        } else {
            // Consider time of day
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: Date())
            
            // Late night/early morning (11PM - 7AM)
            if hour >= 23 || hour < 7 {
                newProfile = .conservative
                Logger.bluetooth.info("Night time hours, using conservative scanning")
            } else {
                // Business hours - base on motion and battery
                if isMotionActive {
                    // Device is moving, likely in use
                    newProfile = batteryLevel > 0.3 ? .aggressive : .normal
                    Logger.bluetooth.info("Device in motion, using \(newProfile.rawValue) scanning")
                } else {
                    // Device is stationary
                    newProfile = .normal
                    Logger.bluetooth.info("Device stationary, using normal scanning")
                }
            }
        }
        
        // Apply the new profile if it's different
        if newProfile != currentScanningProfile {
            Logger.bluetooth.info("Scanning profile changed from \(currentScanningProfile.rawValue) to \(newProfile.rawValue)")
            currentScanningProfile = newProfile
        }
    }
    
    /// Schedule periodic background scanning based on adaptive intervals
    func schedulePeriodicBackgroundScanning() {
        // Cancel any existing background task
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        
        // Start a new background task
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // End task when time expires
            guard let self = self else { return }
            if self.backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
        
        // Optimize scanning parameters
        optimizeScanningForBatteryAndContext()
        
        // Use adaptive scanning intervals based on the current profile
        let scanInterval: TimeInterval
        
        switch currentScanningProfile {
        case .aggressive:
            scanInterval = 60 // 1 minute
        case .normal:
            scanInterval = 300 // 5 minutes
        case .conservative:
            scanInterval = 900 // 15 minutes
        }
        
        // Schedule the next scan
        DispatchQueue.main.asyncAfter(deadline: .now() + scanInterval) { [weak self] in
            guard let self = self else { return }
            
            // Only continue if app is in background
            if UIApplication.shared.applicationState == .background {
                // Start a scan
                self.startBackgroundScanning()
                
                // Schedule the next scan
                self.schedulePeriodicBackgroundScanning()
            }
            
            // End the current background task
            if self.backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
        }
        
        // Perform database maintenance occasionally (every ~24 hours)
        // We use a UserDefaults flag to track when we last did maintenance
        let lastMaintenanceDate = UserDefaults.standard.object(forKey: "LastDatabaseMaintenanceDate") as? Date ?? Date(timeIntervalSince1970: 0)
        
        if Date().timeIntervalSince(lastMaintenanceDate) > 86400 { // 24 hours
            // Perform database maintenance
            purgeOldDevices()
            
            // Update the last maintenance date
            UserDefaults.standard.set(Date(), forKey: "LastDatabaseMaintenanceDate")
            
            Logger.bluetooth.info("Performed scheduled database maintenance")
        }
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
                
                // Start scanning if app is in foreground
                if UIApplication.shared.applicationState == .active {
                    startAdaptiveScanning()
                }
            }
            
        case .poweredOff:
            Logger.bluetooth.info("Bluetooth powered OFF")
            permissionGranted = false
            stopScanning()
            isAdvertising = false
            
        case .unauthorized:
            Logger.bluetooth.error("Bluetooth unauthorized")
            permissionGranted = false
            showPermissionAlert = true
            stopScanning()
            isAdvertising = false
            
        case .unsupported:
            Logger.bluetooth.error("Bluetooth unsupported on this device")
            permissionGranted = false
            stopScanning()
            isAdvertising = false
            
        case .resetting:
            Logger.bluetooth.info("Bluetooth resetting")
            permissionGranted = false
            stopScanning()
            isAdvertising = false
            
        case .unknown:
            Logger.bluetooth.info("Bluetooth state unknown")
            permissionGranted = false
            stopScanning()
            isAdvertising = false
            
        @unknown default:
            Logger.bluetooth.error("Unknown Bluetooth state")
            permissionGranted = false
            stopScanning()
            isAdvertising = false
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
            
            // Store device information in Core Data
            saveDeviceToDatabase(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
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
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Error reading characteristic value: \(error.localizedDescription)")
            return
        }
        
        if characteristic.uuid == BluetoothDiscoveryManager.calendarCharacteristicUUID, let value = characteristic.value {
            Logger.bluetooth.info("Received data from peripheral: \(value.count) bytes")
            
            // Process received data here (to be implemented in next subtask)
            // This would handle the calendar data synchronization
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Error writing to characteristic: \(error.localizedDescription)")
        } else {
            Logger.bluetooth.info("Successfully wrote to characteristic: \(characteristic.uuid)")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Error changing notification state: \(error.localizedDescription)")
            return
        }
        
        if characteristic.isNotifying {
            Logger.bluetooth.info("Subscribed to notifications for: \(characteristic.uuid)")
        } else {
            Logger.bluetooth.info("Unsubscribed from notifications for: \(characteristic.uuid)")
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
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        // Handle read requests for our characteristic
        if request.characteristic.uuid == BluetoothDiscoveryManager.calendarCharacteristicUUID {
            // In the future, this would return calendar data
            // For now, just respond with a placeholder value
            request.value = "12x Calendar".data(using: .utf8)
            peripheral.respond(to: request, withResult: .success)
            Logger.bluetooth.info("Responded to read request")
        } else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // Handle write requests for our characteristic
        for request in requests {
            if request.characteristic.uuid == BluetoothDiscoveryManager.calendarCharacteristicUUID,
               let value = request.value {
                
                Logger.bluetooth.info("Received write request with \(value.count) bytes")
                
                // Process the received data here (to be implemented in next subtask)
                // This would handle updates to the calendar data
                
                peripheral.respond(to: request, withResult: .success)
            } else {
                peripheral.respond(to: request, withResult: .attributeNotFound)
            }
        }
    }
}

// MARK: - Device Store
class DeviceStore {
    static let shared = DeviceStore()
    
    private var devices: [String: (name: String, manufacturerData: Data?, advertisementData: Data?)] = [:]
    
    private init() {}
    
    func saveDevice(identifier: String, name: String, manufacturerData: Data? = nil, advertisementData: Data? = nil) {
        devices[identifier] = (name: name, manufacturerData: manufacturerData, advertisementData: advertisementData)
    }
    
    func getDevice(identifier: String) -> (name: String, manufacturerData: Data?, advertisementData: Data?)? {
        return devices[identifier]
    }
    
    func getAllDevices() -> [String: (name: String, manufacturerData: Data?, advertisementData: Data?)] {
        return devices
    }
}

// MARK: - Logger Extension
extension Logger {
    static let bluetooth = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.connectwith", category: "Bluetooth")
}