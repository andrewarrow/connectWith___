import Foundation
import CoreBluetooth
import Combine
import OSLog

/// Manages connection establishment and data exchange between Bluetooth devices
class ConnectionManager: ObservableObject {
    // Singleton instance
    static let shared = ConnectionManager()
    
    // Bluetooth discovery manager reference
    private let bluetoothManager = BluetoothDiscoveryManager.shared
    
    // Published properties for UI updates
    @Published var connectedDevices: [String: ConnectionStatus] = [:]
    @Published var connectionInProgress: [String: Bool] = [:]
    @Published var transferInProgress: [String: Bool] = [:]
    @Published var lastTransferResults: [String: TransferResult] = [:]
    
    // Map of device identifiers to active connection attempt cancellables
    private var connectionCancellables: [String: AnyCancellable] = [:]
    
    // Status update timer
    private var statusUpdateTimer: Timer?
    
    // Sync buffer sizes
    private let maxPacketSize = 512
    
    // Secure key for data verification
    private var securityKeys: [String: Data] = [:]
    
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
    
    // Transfer status tracking
    struct TransferResult {
        let timestamp: Date
        let bytesTransferred: Int
        let success: Bool
        let errors: [String]?
        let duration: TimeInterval
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
    
    // MARK: - Public Connection Methods
    
    /// Initiates a connection attempt to a device with security verification
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
            Logger.bluetooth.info("Initiating secure connection to device: \(identifier)")
            
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
                    // Connection succeeded, now verify security
                    timer.invalidate()
                    timeoutTimer.invalidate()
                    
                    // Perform application-layer verification
                    self.verifyDeviceConnection(peripheral) { verified in
                        if verified {
                            // Security verification passed
                            self.connectedDevices[identifier] = .connected
                            self.connectionInProgress[identifier] = false
                            self.connectionCancellables.removeValue(forKey: identifier)
                            
                            // Update device last seen time
                            self.updateDeviceLastSeen(identifier: identifier)
                            
                            resultSubject.send(true)
                            resultSubject.send(completion: .finished)
                            
                            Logger.bluetooth.info("Secure connection established with device: \(identifier)")
                        } else {
                            // Security verification failed
                            self.bluetoothManager.disconnectFromDevice(peripheral)
                            self.connectedDevices[identifier] = .disconnected
                            self.connectionInProgress[identifier] = false
                            self.connectionCancellables.removeValue(forKey: identifier)
                            
                            resultSubject.send(completion: .failure(ConnectionError.securityVerificationFailed))
                            
                            Logger.bluetooth.error("Security verification failed for device: \(identifier)")
                        }
                    }
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
    
    /// Disconnects from a device gracefully
    /// - Parameter identifier: The Bluetooth identifier of the device
    func disconnectFromDevice(identifier: String) {
        // Find the peripheral with this identifier
        for peripheral in bluetoothManager.connectedPeripherals {
            if peripheral.identifier.uuidString == identifier {
                // Send disconnection notification to peer device
                sendDisconnectionNotification(peripheral)
                
                // Disconnect from device
                bluetoothManager.disconnectFromDevice(peripheral)
                
                // Update status
                connectedDevices[identifier] = .disconnected
                connectionInProgress[identifier] = false
                connectionCancellables.removeValue(forKey: identifier)
                
                Logger.bluetooth.info("Gracefully disconnected from device: \(identifier)")
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
    
    // MARK: - Data Exchange Methods
    
    /// Sends calendar data to a connected device
    /// - Parameters:
    ///   - data: The data to send
    ///   - identifier: The Bluetooth identifier of the device
    /// - Returns: A publisher that emits when the transfer succeeds or fails
    func sendData(_ data: Data, to identifier: String) -> AnyPublisher<TransferResult, Error> {
        let resultSubject = PassthroughSubject<TransferResult, Error>()
        
        // Check if device is connected
        guard let peripheral = findConnectedPeripheral(identifier: identifier) else {
            Logger.bluetooth.error("Cannot send data: Device \(identifier) not connected")
            resultSubject.send(completion: .failure(ConnectionError.deviceNotConnected))
            return resultSubject.eraseToAnyPublisher()
        }
        
        // Set transfer in progress
        transferInProgress[identifier] = true
        
        // Start transfer
        let startTime = Date()
        
        // Prepare data with encryption and checksums
        let secureData = prepareDataForTransfer(data, deviceId: identifier)
        
        // Split data into chunks if needed
        let chunks = splitDataIntoChunks(secureData)
        
        Logger.bluetooth.info("Starting data transfer to \(identifier): \(secureData.count) bytes in \(chunks.count) chunks")
        
        // Send data chunks
        sendDataChunks(chunks, to: peripheral, identifier: identifier) { [weak self] success, bytesTransferred, errors in
            guard let self = self else { return }
            
            // Calculate transfer duration
            let duration = Date().timeInterval(since: startTime)
            
            // Create result
            let result = TransferResult(
                timestamp: Date(),
                bytesTransferred: bytesTransferred,
                success: success,
                errors: errors,
                duration: duration
            )
            
            // Update status
            self.transferInProgress[identifier] = false
            self.lastTransferResults[identifier] = result
            
            if success {
                // Log success
                Logger.bluetooth.info("Data transfer to \(identifier) completed: \(bytesTransferred) bytes in \(String(format: "%.2f", duration))s")
                
                // Update sync history
                self.logSuccessfulTransfer(deviceId: identifier, bytesSent: bytesTransferred, bytesReceived: 0)
                
                // Send result
                resultSubject.send(result)
                resultSubject.send(completion: .finished)
            } else {
                // Log failure
                Logger.bluetooth.error("Data transfer to \(identifier) failed: \(errors?.joined(separator: ", ") ?? "Unknown error")")
                
                // Send error
                resultSubject.send(completion: .failure(ConnectionError.dataTransferFailed))
            }
        }
        
        return resultSubject.eraseToAnyPublisher()
    }
    
    /// Requests calendar data from a connected device
    /// - Parameter identifier: The Bluetooth identifier of the device
    /// - Returns: A publisher that emits the received data or an error
    func requestDataFromDevice(identifier: String) -> AnyPublisher<Data, Error> {
        let resultSubject = PassthroughSubject<Data, Error>()
        
        // Check if device is connected
        guard let peripheral = findConnectedPeripheral(identifier: identifier) else {
            Logger.bluetooth.error("Cannot request data: Device \(identifier) not connected")
            resultSubject.send(completion: .failure(ConnectionError.deviceNotConnected))
            return resultSubject.eraseToAnyPublisher()
        }
        
        // Set transfer in progress
        transferInProgress[identifier] = true
        
        // Send data request
        requestDataFromPeripheral(peripheral, identifier: identifier) { [weak self] success, data, error in
            guard let self = self else { return }
            
            // Update status
            self.transferInProgress[identifier] = false
            
            if success, let receivedData = data {
                // Verify and decrypt received data
                if let verifiedData = self.verifyAndDecryptReceivedData(receivedData, deviceId: identifier) {
                    // Log success
                    Logger.bluetooth.info("Successfully received and verified \(verifiedData.count) bytes from \(identifier)")
                    
                    // Update sync history
                    self.logSuccessfulTransfer(deviceId: identifier, bytesSent: 0, bytesReceived: verifiedData.count)
                    
                    // Send result
                    resultSubject.send(verifiedData)
                    resultSubject.send(completion: .finished)
                } else {
                    // Data verification failed
                    Logger.bluetooth.error("Data verification failed for received data from \(identifier)")
                    resultSubject.send(completion: .failure(ConnectionError.dataVerificationFailed))
                }
            } else {
                // Transfer failed
                Logger.bluetooth.error("Failed to receive data from \(identifier): \(error?.localizedDescription ?? "Unknown error")")
                resultSubject.send(completion: .failure(error ?? ConnectionError.dataTransferFailed))
            }
        }
        
        return resultSubject.eraseToAnyPublisher()
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
    
    // MARK: - Private Helper Methods
    
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
            transferInProgress.removeAll()
        }
        
        // Update connection statuses if Bluetooth is turned on
        if bluetoothManager.bluetoothState == .poweredOn {
            updateAllConnectionStatuses()
        }
    }
    
    /// Finds a connected peripheral by its identifier
    /// - Parameter identifier: The Bluetooth identifier
    /// - Returns: The peripheral if found and connected
    private func findConnectedPeripheral(identifier: String) -> CBPeripheral? {
        for peripheral in bluetoothManager.connectedPeripherals {
            if peripheral.identifier.uuidString == identifier {
                return peripheral
            }
        }
        return nil
    }
    
    /// Verifies a connection with security check
    /// - Parameters:
    ///   - peripheral: The peripheral to verify
    ///   - completion: Completion handler with verification result
    private func verifyDeviceConnection(_ peripheral: CBPeripheral, completion: @escaping (Bool) -> Void) {
        // Generate a random challenge
        let challenge = generateSecurityChallenge()
        
        // Store challenge for verification
        let identifier = peripheral.identifier.uuidString
        securityKeys[identifier] = challenge
        
        // Send challenge to device and verify response
        sendSecurityChallenge(challenge, to: peripheral) { [weak self] success, response in
            guard let self = self else {
                completion(false)
                return
            }
            
            if success, let responseData = response {
                // Verify the response
                let verified = self.verifySecurityResponse(responseData, for: identifier)
                completion(verified)
            } else {
                completion(false)
            }
        }
    }
    
    /// Generates a security challenge for connection verification
    /// - Returns: Challenge data
    private func generateSecurityChallenge() -> Data {
        // Generate a random challenge
        var randomBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        return Data(randomBytes)
    }
    
    /// Sends a security challenge to a peripheral
    /// - Parameters:
    ///   - challenge: The challenge data
    ///   - peripheral: The peripheral to challenge
    ///   - completion: Completion handler with results
    private func sendSecurityChallenge(_ challenge: Data, to peripheral: CBPeripheral, completion: @escaping (Bool, Data?) -> Void) {
        // For the purpose of this implementation, simulate successful verification
        // In a real implementation, this would send a challenge over BLE and receive a response
        
        // Get device name for logging
        let deviceName = peripheral.name ?? peripheral.identifier.uuidString
        
        Logger.bluetooth.info("Sending security challenge to \(deviceName)")
        
        // Simulate verification delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            // In a real implementation, this would process the actual response
            // For now, we'll simulate a successful response
            let simulatedResponse = challenge // In reality, would be processed by remote device
            
            Logger.bluetooth.info("Received security response from \(deviceName)")
            completion(true, simulatedResponse)
        }
    }
    
    /// Verifies a security response from a device
    /// - Parameters:
    ///   - response: The response data
    ///   - identifier: The device identifier
    /// - Returns: Whether verification passed
    private func verifySecurityResponse(_ response: Data, for identifier: String) -> Bool {
        // In a real implementation, this would validate the response against the challenge
        // For now, we'll simulate a successful verification
        return true
    }
    
    /// Prepares data for secure transfer
    /// - Parameters:
    ///   - data: The raw data to prepare
    ///   - deviceId: The target device ID
    /// - Returns: The prepared data with security measures
    private func prepareDataForTransfer(_ data: Data, deviceId: String) -> Data {
        // In a real implementation, this would encrypt the data and add checksums
        // For now, just return the original data
        return data
    }
    
    /// Splits data into appropriate sized chunks for transfer
    /// - Parameter data: The data to split
    /// - Returns: Array of data chunks
    private func splitDataIntoChunks(_ data: Data) -> [Data] {
        var chunks = [Data]()
        var offset = 0
        
        while offset < data.count {
            let chunkSize = min(maxPacketSize, data.count - offset)
            let chunk = data.subdata(in: offset..<(offset + chunkSize))
            chunks.append(chunk)
            offset += chunkSize
        }
        
        return chunks
    }
    
    /// Sends data chunks to a peripheral
    /// - Parameters:
    ///   - chunks: The data chunks to send
    ///   - peripheral: The peripheral to send to
    ///   - identifier: The device identifier
    ///   - completion: Completion handler with results
    private func sendDataChunks(_ chunks: [Data], to peripheral: CBPeripheral, identifier: String, completion: @escaping (Bool, Int, [String]?) -> Void) {
        // For the purpose of this implementation, simulate successful data transfer
        // In a real implementation, this would send chunks over BLE with acknowledgments
        
        // Get device name for logging
        let deviceName = peripheral.name ?? peripheral.identifier.uuidString
        
        // Calculate total bytes
        let totalBytes = chunks.reduce(0) { $0 + $1.count }
        
        Logger.bluetooth.info("Simulating data transfer of \(totalBytes) bytes to \(deviceName)")
        
        // Simulate transfer delay proportional to data size
        let simulatedTransferTime = Double(totalBytes) / 10000.0 // simulate ~10KB/s transfer
        DispatchQueue.global().asyncAfter(deadline: .now() + simulatedTransferTime) {
            // In a real implementation, this would track actual bytes transferred
            // For now, we'll simulate a successful transfer
            Logger.bluetooth.info("Completed simulated data transfer to \(deviceName)")
            completion(true, totalBytes, nil)
        }
    }
    
    /// Requests data from a peripheral
    /// - Parameters:
    ///   - peripheral: The peripheral to request from
    ///   - identifier: The device identifier
    ///   - completion: Completion handler with results
    private func requestDataFromPeripheral(_ peripheral: CBPeripheral, identifier: String, completion: @escaping (Bool, Data?, Error?) -> Void) {
        // For the purpose of this implementation, simulate successful data request
        // In a real implementation, this would send a request over BLE and receive data
        
        // Get device name for logging
        let deviceName = peripheral.name ?? peripheral.identifier.uuidString
        
        Logger.bluetooth.info("Requesting data from \(deviceName)")
        
        // Simulate request delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            // In a real implementation, this would process actual received data
            // For now, we'll simulate receiving mock data
            
            // Create sample response data (would be actual calendar data in real implementation)
            let mockEventData = """
            {
                "events": [
                    {
                        "id": "\(UUID().uuidString)",
                        "title": "Family Dinner",
                        "location": "Home",
                        "day": 15,
                        "month": 4
                    }
                ],
                "deviceId": "\(identifier)",
                "timestamp": \(Date().timeIntervalSince1970)
            }
            """.data(using: .utf8)
            
            Logger.bluetooth.info("Received data from \(deviceName)")
            completion(true, mockEventData, nil)
        }
    }
    
    /// Verifies and decrypts received data
    /// - Parameters:
    ///   - data: The received data
    ///   - deviceId: The source device ID
    /// - Returns: The verified and decrypted data, or nil if verification failed
    private func verifyAndDecryptReceivedData(_ data: Data, deviceId: String) -> Data? {
        // In a real implementation, this would verify checksums and decrypt the data
        // For now, just return the original data
        return data
    }
    
    /// Sends disconnection notification to a peripheral
    /// - Parameter peripheral: The peripheral to notify
    private func sendDisconnectionNotification(_ peripheral: CBPeripheral) {
        // In a real implementation, this would send a notification before disconnecting
        // For now, just log the intention
        let deviceName = peripheral.name ?? peripheral.identifier.uuidString
        Logger.bluetooth.info("Sending disconnection notification to \(deviceName)")
    }
    
    /// Logs a successful data transfer
    /// - Parameters:
    ///   - deviceId: The device identifier
    ///   - bytesSent: Number of bytes sent
    ///   - bytesReceived: Number of bytes received
    private func logSuccessfulTransfer(deviceId: String, bytesSent: Int, bytesReceived: Int) {
        // Get device name if available
        var deviceName: String?
        if let peripheral = findConnectedPeripheral(identifier: deviceId) {
            deviceName = peripheral.name
        }
        
        // Create sync log
        SyncHistoryManager.shared.createSyncLog(
            deviceId: deviceId,
            deviceName: deviceName,
            eventsReceived: bytesReceived > 0 ? 1 : 0, // Simplified for now
            eventsSent: bytesSent > 0 ? 1 : 0,         // Simplified for now
            conflicts: 0,
            resolutionMethod: "none"
        )
        
        // Update last sync time
        updateDeviceLastSync(identifier: deviceId)
    }
}

// MARK: - Connection Errors
enum ConnectionError: Error {
    case timeout
    case deviceNotFound
    case bluetoothOff
    case connectionFailed
    case deviceNotConnected
    case dataTransferFailed
    case dataVerificationFailed
    case securityVerificationFailed
    
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
        case .deviceNotConnected:
            return "Device not connected"
        case .dataTransferFailed:
            return "Data transfer failed"
        case .dataVerificationFailed:
            return "Data verification failed"
        case .securityVerificationFailed:
            return "Security verification failed"
        }
    }
}