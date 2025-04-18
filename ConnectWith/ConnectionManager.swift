import Foundation
import CoreBluetooth
import Combine
import OSLog

/// Manages and monitors connections with Bluetooth devices
class ConnectionManager: ObservableObject {
    // Singleton instance
    static let shared = ConnectionManager()
    
    // Bluetooth discovery manager reference
    private let bluetoothManager = BluetoothDiscoveryManager.shared
    
    // Published properties for UI updates
    @Published var connectedDevices: [String: ConnectionStatus] = [:]
    @Published var connectionInProgress: [String: Bool] = [:]
    
    // Map of device identifiers to active connection attempt cancellables
    private var connectionCancellables: [String: AnyCancellable] = [:]
    
    // Status update timer
    private var statusUpdateTimer: Timer?
    
    // Connection status enum
    enum ConnectionStatus: String {
        case connected = "Connected"
        case disconnected = "Disconnected"
        case unknown = "Unknown"
        
        var color: String {
            switch self {
            case .connected: return "green"
            case .disconnected: return "red"
            case .unknown: return "gray"
            }
        }
    }
    
    // Private initializer for singleton
    private init() {
        // Start status update timer
        startStatusUpdateTimer()
        
        // Add notification observers for Bluetooth state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBluetoothStateChange),
            name: NSNotification.Name("BluetoothStateDidChange"),
            object: nil
        )
    }
    
    deinit {
        statusUpdateTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Initiates a connection attempt to a device
    /// - Parameter identifier: The Bluetooth identifier of the device
    /// - Returns: A publisher that emits when the connection succeeds or fails
    func connectToDevice(identifier: String) -> AnyPublisher<Bool, Error> {
        // Set connection in progress
        connectionInProgress[identifier] = true
        
        // Create a subject for the connection result
        let resultSubject = PassthroughSubject<Bool, Error>()
        
        // Find the peripheral with this identifier
        var foundPeripheral: CBPeripheral?
        for device in bluetoothManager.nearbyDevices {
            if device.peripheral.identifier.uuidString == identifier {
                foundPeripheral = device.peripheral
                break
            }
        }
        
        if let peripheral = foundPeripheral {
            Logger.bluetooth.info("Initiating connection to device: \(identifier)")
            
            // Create a timeout for the connection attempt
            let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                
                self.connectionInProgress[identifier] = false
                self.connectionCancellables.removeValue(forKey: identifier)
                resultSubject.send(completion: .failure(ConnectionError.timeout))
                
                Logger.bluetooth.error("Connection timeout for device: \(identifier)")
            }
            
            // Connect to the peripheral
            bluetoothManager.connectToDevice(peripheral)
            
            // Create a timer to check if the connection succeeded
            var checkCount = 0
            let checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                
                // Check if the peripheral is connected
                let isConnected = self.bluetoothManager.connectedPeripherals.contains { $0.identifier.uuidString == identifier }
                
                if isConnected {
                    // Connection succeeded
                    timer.invalidate()
                    timeoutTimer.invalidate()
                    
                    self.connectedDevices[identifier] = .connected
                    self.connectionInProgress[identifier] = false
                    self.connectionCancellables.removeValue(forKey: identifier)
                    
                    // Update device last seen time
                    self.updateDeviceLastSeen(identifier: identifier)
                    
                    resultSubject.send(true)
                    resultSubject.send(completion: .finished)
                    
                    Logger.bluetooth.info("Connection successful for device: \(identifier)")
                } else {
                    // Check if we've exceeded the max check count
                    checkCount += 1
                    if checkCount >= 10 {
                        // Give up and let the timeout handle it
                        timer.invalidate()
                    }
                }
            }
            
            // Create a cancellable for the connection attempt
            let cancellable = Cancellable {
                timeoutTimer.invalidate()
                checkTimer.invalidate()
                self.bluetoothManager.disconnectFromDevice(peripheral)
                self.connectionInProgress[identifier] = false
            }
            
            // Store the cancellable
            connectionCancellables[identifier] = AnyCancellable(cancellable)
        } else {
            // Could not find peripheral
            connectionInProgress[identifier] = false
            resultSubject.send(completion: .failure(ConnectionError.deviceNotFound))
            Logger.bluetooth.error("Device not found for connection: \(identifier)")
        }
        
        return resultSubject.eraseToAnyPublisher()
    }
    
    /// Disconnects from a device
    /// - Parameter identifier: The Bluetooth identifier of the device
    func disconnectFromDevice(identifier: String) {
        // Find the peripheral with this identifier
        for peripheral in bluetoothManager.connectedPeripherals {
            if peripheral.identifier.uuidString == identifier {
                bluetoothManager.disconnectFromDevice(peripheral)
                
                connectedDevices[identifier] = .disconnected
                connectionInProgress[identifier] = false
                connectionCancellables.removeValue(forKey: identifier)
                
                Logger.bluetooth.info("Disconnected from device: \(identifier)")
                return
            }
        }
        
        // Device not found or not connected
        Logger.bluetooth.warning("Device not found or not connected for disconnect: \(identifier)")
    }
    
    /// Gets the connection status for a device
    /// - Parameter identifier: The Bluetooth identifier of the device
    /// - Returns: The connection status
    func getConnectionStatus(identifier: String) -> ConnectionStatus {
        if connectionInProgress[identifier] == true {
            return .unknown
        }
        
        // Check if the device is in the connected peripherals list
        let isConnected = bluetoothManager.connectedPeripherals.contains { $0.identifier.uuidString == identifier }
        return isConnected ? .connected : .disconnected
    }
    
    /// Updates the last sync time for a device
    /// - Parameters:
    ///   - identifier: The Bluetooth identifier of the device
    ///   - syncTime: The sync time to set (defaults to now)
    func updateDeviceLastSync(identifier: String, syncTime: Date = Date()) {
        PersistenceController.shared.performBackgroundTask { context in
            let familyDeviceRepository = FamilyDeviceRepository(context: context)
            
            // Update FamilyDevice if it exists
            if let familyDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: identifier) {
                familyDevice.lastSyncTimestamp = syncTime
                try? context.save()
                Logger.bluetooth.info("Updated sync time for device: \(identifier)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Starts the timer that periodically updates connection statuses
    private func startStatusUpdateTimer() {
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateAllConnectionStatuses()
        }
        
        // Run an initial update
        updateAllConnectionStatuses()
    }
    
    /// Updates the connection status for all known devices
    private func updateAllConnectionStatuses() {
        // Get all device identifiers from Core Data
        PersistenceController.shared.performBackgroundTask { context in
            let fetchRequest = BluetoothDevice.fetchRequest()
            
            do {
                let devices = try context.fetch(fetchRequest)
                
                // Update each device's connection status
                for device in devices {
                    let isConnected = self.bluetoothManager.connectedPeripherals.contains { $0.identifier.uuidString == device.identifier }
                    
                    DispatchQueue.main.async {
                        self.connectedDevices[device.identifier] = isConnected ? .connected : .disconnected
                    }
                }
                
                Logger.bluetooth.debug("Updated connection statuses for \(devices.count) devices")
            } catch {
                Logger.bluetooth.error("Failed to fetch devices for status update: \(error.localizedDescription)")
            }
        }
    }
    
    /// Updates the last seen time for a device
    /// - Parameter identifier: The Bluetooth identifier of the device
    private func updateDeviceLastSeen(identifier: String) {
        PersistenceController.shared.performBackgroundTask { context in
            let fetchRequest = BluetoothDevice.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "identifier == %@", identifier)
            
            do {
                let results = try context.fetch(fetchRequest)
                if let device = results.first {
                    device.lastSeen = Date()
                    try context.save()
                    Logger.bluetooth.debug("Updated last seen time for device: \(identifier)")
                }
            } catch {
                Logger.bluetooth.error("Failed to update last seen time: \(error.localizedDescription)")
            }
        }
    }
    
    /// Handles Bluetooth state changes
    @objc private func handleBluetoothStateChange(_ notification: Notification) {
        // Clear connection statuses if Bluetooth is turned off
        if bluetoothManager.bluetoothState != .poweredOn {
            connectionInProgress.removeAll()
            connectedDevices.removeAll()
            connectionCancellables.removeAll()
        }
        
        // Update connection statuses if Bluetooth is turned on
        if bluetoothManager.bluetoothState == .poweredOn {
            updateAllConnectionStatuses()
        }
    }
}

// MARK: - Connection Errors
enum ConnectionError: Error {
    case timeout
    case deviceNotFound
    case bluetoothOff
    case connectionFailed
    
    var localizedDescription: String {
        switch self {
        case .timeout:
            return "Connection attempt timed out"
        case .deviceNotFound:
            return "Device not found"
        case .bluetoothOff:
            return "Bluetooth is turned off"
        case .connectionFailed:
            return "Connection failed"
        }
    }
}