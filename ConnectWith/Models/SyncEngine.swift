import Foundation
import CoreData
import Combine
import OSLog

/// SyncEngine orchestrates data synchronization between devices with error handling and retry logic
class SyncEngine: ObservableObject {
    // MARK: - Singleton and Properties
    
    /// Shared instance
    static let shared = SyncEngine()
    
    /// Dependencies
    private let connectionManager = ConnectionManager.shared
    private let syncHistoryManager = SyncHistoryManager.shared
    
    /// Published properties for UI updates
    @Published var syncInProgress: [String: Bool] = [:]
    @Published var syncProgress: [String: Double] = [:]
    @Published var syncResults: [String: SyncResult] = [:]
    
    /// Active sync cancellables
    private var syncCancellables: [String: AnyCancellable] = [:]
    
    /// Sync modes
    enum SyncMode {
        case incremental
        case full
        
        var protocolMode: DataExchangeProtocol.SyncMode {
            switch self {
            case .incremental:
                return .incremental
            case .full:
                return .full
            }
        }
    }
    
    /// Sync result structure
    struct SyncResult {
        let deviceId: String
        let deviceName: String?
        let timestamp: Date
        let eventsReceived: Int
        let eventsSent: Int
        let conflicts: Int
        let success: Bool
        let duration: TimeInterval
        let errorMessage: String?
    }
    
    // Retry settings
    private let maxRetryAttempts = 3
    private let initialRetryDelay: TimeInterval = 1.0 // seconds
    
    // Private initializer for singleton
    private init() {}
    
    // MARK: - Public Methods
    
    /// Synchronizes data with a specified device
    /// - Parameters:
    ///   - deviceId: The device's Bluetooth identifier
    ///   - mode: Sync mode (incremental or full)
    ///   - retryCount: Current retry attempt (used internally)
    /// - Returns: Publisher with sync result or error
    func syncWithDevice(
        deviceId: String,
        mode: SyncMode = .incremental,
        retryCount: Int = 0
    ) -> AnyPublisher<SyncResult, Error> {
        // Create result subject
        let resultSubject = PassthroughSubject<SyncResult, Error>()
        
        // Check if sync is already in progress
        guard syncInProgress[deviceId] != true else {
            return Fail(error: SyncError.syncAlreadyInProgress).eraseToAnyPublisher()
        }
        
        // Mark sync as in progress
        syncInProgress[deviceId] = true
        syncProgress[deviceId] = 0.0
        
        // Get device info for logging
        var deviceName: String?
        PersistenceController.shared.performBackgroundTask { context in
            let deviceRepository = FamilyDeviceRepository(context: context)
            if let device = deviceRepository.fetchDeviceByBluetoothIdentifier(identifier: deviceId) {
                deviceName = device.customName
            }
        }
        
        Logger.sync.info("Starting sync with device: \(deviceId) (\(deviceName ?? "Unknown"))")
        
        // Start sync timer
        let startTime = Date()
        
        // Create cancellable for the sync operation
        let syncCancellable = syncOperation(deviceId: deviceId, deviceName: deviceName, mode: mode, retryCount: retryCount, startTime: startTime)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self = self else { return }
                    
                    // Mark sync as completed
                    self.syncInProgress[deviceId] = false
                    
                    switch completion {
                    case .finished:
                        Logger.sync.info("Sync with device \(deviceId) completed successfully")
                    case .failure(let error):
                        // Handle retry logic if appropriate
                        if retryCount < self.maxRetryAttempts, self.shouldRetry(error) {
                            Logger.sync.warning("Sync with device \(deviceId) failed, retrying (\(retryCount + 1)/\(self.maxRetryAttempts)): \(error.localizedDescription)")
                            
                            // Calculate delay with exponential backoff
                            let delay = self.initialRetryDelay * pow(2.0, Double(retryCount))
                            
                            // Retry after delay
                            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                                let retryPublisher = self.syncWithDevice(
                                    deviceId: deviceId,
                                    mode: mode,
                                    retryCount: retryCount + 1
                                )
                                
                                self.syncCancellables[deviceId] = retryPublisher
                                    .sink(
                                        receiveCompletion: { retryCompletion in
                                            switch retryCompletion {
                                            case .finished:
                                                resultSubject.send(completion: .finished)
                                            case .failure(let retryError):
                                                resultSubject.send(completion: .failure(retryError))
                                            }
                                        },
                                        receiveValue: { result in
                                            resultSubject.send(result)
                                        }
                                    )
                            }
                        } else {
                            // Log failure and complete with error
                            Logger.sync.error("Sync with device \(deviceId) failed: \(error.localizedDescription)")
                            
                            // Create failure result
                            let duration = Date().timeInterval(since: startTime)
                            let failureResult = SyncResult(
                                deviceId: deviceId,
                                deviceName: deviceName,
                                timestamp: Date(),
                                eventsReceived: 0,
                                eventsSent: 0,
                                conflicts: 0,
                                success: false,
                                duration: duration,
                                errorMessage: error.localizedDescription
                            )
                            
                            // Update sync results
                            self.syncResults[deviceId] = failureResult
                            
                            // Send completion
                            resultSubject.send(completion: .failure(error))
                        }
                    }
                },
                receiveValue: { [weak self] result in
                    guard let self = self else { return }
                    
                    // Update sync results
                    self.syncResults[deviceId] = result
                    self.syncProgress[deviceId] = 1.0
                    
                    // Send result
                    resultSubject.send(result)
                }
            )
        
        // Store cancellable
        syncCancellables[deviceId] = syncCancellable
        
        return resultSubject.eraseToAnyPublisher()
    }
    
    /// Cancels an ongoing sync operation
    /// - Parameter deviceId: The device's Bluetooth identifier
    /// - Returns: True if sync was canceled, false if no sync was in progress
    @discardableResult
    func cancelSync(deviceId: String) -> Bool {
        guard syncInProgress[deviceId] == true, let cancellable = syncCancellables[deviceId] else {
            return false
        }
        
        // Cancel the operation
        cancellable.cancel()
        
        // Update status
        syncInProgress[deviceId] = false
        syncCancellables.removeValue(forKey: deviceId)
        
        Logger.sync.info("Sync with device \(deviceId) canceled")
        return true
    }
    
    /// Gets sync history for a device
    /// - Parameters:
    ///   - deviceId: The device's Bluetooth identifier
    ///   - limit: Maximum number of history items to return
    /// - Returns: Array of sync logs
    func getSyncHistory(deviceId: String, limit: Int = 10) -> [SyncLog] {
        return syncHistoryManager.getRecentSyncLogs(bluetoothIdentifier: deviceId, limit: limit)
    }
    
    /// Gets the last sync time for a device
    /// - Parameter deviceId: The device's Bluetooth identifier
    /// - Returns: The last sync time, or nil if the device has never synced
    func getLastSyncTime(deviceId: String) -> Date? {
        return syncHistoryManager.getLastSyncTime(bluetoothIdentifier: deviceId)
    }
    
    // MARK: - Private Methods
    
    /// Main sync operation sequence
    /// - Parameters:
    ///   - deviceId: The device's Bluetooth identifier
    ///   - deviceName: The device's name (if known)
    ///   - mode: Sync mode
    ///   - retryCount: Current retry attempt
    ///   - startTime: Start time for duration calculation
    /// - Returns: Publisher with sync result or error
    private func syncOperation(
        deviceId: String,
        deviceName: String?,
        mode: SyncMode,
        retryCount: Int,
        startTime: Date
    ) -> AnyPublisher<SyncResult, Error> {
        return Deferred {
            // Initialize result variables
            var eventsSent = 0
            var eventsReceived = 0
            var conflicts = 0
            var errorMessage: String? = nil
            
            // Step 1: Connect to device if not already connected
            return self.ensureDeviceConnection(deviceId: deviceId)
                .handleEvents(receiveOutput: { _ in
                    // Update progress after connection established
                    self.syncProgress[deviceId] = 0.1
                })
                
                // Step 2: Prepare data for sending
                .flatMap { _ -> AnyPublisher<(Data, Data), Error> in
                    // Get last sync time for incremental sync
                    var lastSyncTime: Date? = nil
                    if mode == .incremental {
                        lastSyncTime = self.syncHistoryManager.getLastSyncTime(bluetoothIdentifier: deviceId)
                    }
                    
                    return self.prepareDataForSync(deviceId: deviceId, lastSyncTime: lastSyncTime)
                        .handleEvents(receiveOutput: { _ in
                            // Update progress after data preparation
                            self.syncProgress[deviceId] = 0.2
                        })
                        .eraseToAnyPublisher()
                }
                
                // Step 3: Send data to device
                .flatMap { eventData, historyData -> AnyPublisher<Void, Error> in
                    // Only attempt to send if we have data
                    if eventData.count > 0 || historyData.count > 0 {
                        return self.sendDataToDevice(deviceId: deviceId, eventData: eventData, historyData: historyData)
                            .handleEvents(receiveOutput: { _ in
                                // Track events sent
                                if eventData.count > 0 {
                                    // Approximate count - in a real implementation we would get the exact count
                                    eventsSent = 1
                                }
                                
                                // Update progress after sending data
                                self.syncProgress[deviceId] = 0.5
                            })
                            .eraseToAnyPublisher()
                    } else {
                        // No data to send, continue
                        return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
                    }
                }
                
                // Step 4: Request data from device
                .flatMap { _ -> AnyPublisher<(Data, Data), Error> in
                    return self.requestDataFromDevice(deviceId: deviceId)
                        .handleEvents(receiveOutput: { _ in
                            // Update progress after receiving data
                            self.syncProgress[deviceId] = 0.7
                        })
                        .eraseToAnyPublisher()
                }
                
                // Step 5: Process received data
                .flatMap { receivedEventData, receivedHistoryData -> AnyPublisher<(Int, Int), Error> in
                    return self.processReceivedData(deviceId: deviceId, eventData: receivedEventData, historyData: receivedHistoryData)
                        .handleEvents(receiveOutput: { receivedCount, conflictCount in
                            // Track events received and conflicts
                            eventsReceived = receivedCount
                            conflicts = conflictCount
                            
                            // Update progress after processing data
                            self.syncProgress[deviceId] = 0.9
                        })
                        .eraseToAnyPublisher()
                }
                
                // Step 6: Create sync log and result
                .map { _, _ -> SyncResult in
                    // Calculate sync duration
                    let duration = Date().timeInterval(since: startTime)
                    
                    // Create sync log
                    self.syncHistoryManager.createSyncLog(
                        deviceId: deviceId,
                        deviceName: deviceName,
                        eventsReceived: eventsReceived,
                        eventsSent: eventsSent,
                        conflicts: conflicts,
                        resolutionMethod: conflicts > 0 ? "merge" : "none"
                    )
                    
                    // Update device last sync time
                    self.syncHistoryManager.updateDeviceLastSync(deviceId: deviceId)
                    
                    // Log success
                    Logger.sync.info("Sync with device \(deviceId) completed successfully: Sent \(eventsSent) events, received \(eventsReceived) events, resolved \(conflicts) conflicts, duration: \(String(format: "%.2f", duration))s")
                    
                    // Return sync result
                    return SyncResult(
                        deviceId: deviceId,
                        deviceName: deviceName,
                        timestamp: Date(),
                        eventsReceived: eventsReceived,
                        eventsSent: eventsSent,
                        conflicts: conflicts,
                        success: true,
                        duration: duration,
                        errorMessage: nil
                    )
                }
                .handleEvents(receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        errorMessage = error.localizedDescription
                    }
                })
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }
    
    /// Ensures device is connected before sync
    /// - Parameter deviceId: The device's Bluetooth identifier
    /// - Returns: Publisher that emits when connection is established
    private func ensureDeviceConnection(deviceId: String) -> AnyPublisher<Void, Error> {
        // Check if already connected
        if connectionManager.getConnectionStatus(identifier: deviceId) == .connected {
            return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        
        // Connect to device
        return connectionManager.connectToDevice(identifier: deviceId)
            .map { _ in () }
            .mapError { error -> Error in
                return SyncError.connectionFailed(error)
            }
            .eraseToAnyPublisher()
    }
    
    /// Prepares local data for sync
    /// - Parameters:
    ///   - deviceId: The device's Bluetooth identifier
    ///   - lastSyncTime: Time of last sync for incremental updates
    /// - Returns: Publisher with event and history data
    private func prepareDataForSync(deviceId: String, lastSyncTime: Date?) -> AnyPublisher<(Data, Data), Error> {
        return Future<(Data, Data), Error> { promise in
            PersistenceController.shared.performBackgroundTask { context in
                // Prepare event data
                let eventData = DataExchangeProtocol.serializeEvents(
                    context: context,
                    deviceId: deviceId,
                    lastSyncTime: lastSyncTime
                ) ?? Data()
                
                // Prepare edit history data
                let historyData = DataExchangeProtocol.serializeEditHistory(
                    context: context,
                    deviceId: deviceId,
                    lastSyncTime: lastSyncTime
                ) ?? Data()
                
                promise(.success((eventData, historyData)))
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Sends data to a device
    /// - Parameters:
    ///   - deviceId: The device's Bluetooth identifier
    ///   - eventData: Serialized event data
    ///   - historyData: Serialized edit history data
    /// - Returns: Publisher that emits when send is complete
    private func sendDataToDevice(deviceId: String, eventData: Data, historyData: Data) -> AnyPublisher<Void, Error> {
        // Send event data first, then history data
        var sendOperations = [AnyPublisher<Void, Error>]()
        
        // Add event data send operation if we have data
        if eventData.count > 0 {
            let eventSendOperation = connectionManager.sendData(eventData, to: deviceId)
                .map { _ in () }
                .mapError { error -> Error in
                    return SyncError.dataSendFailed(error)
                }
                .eraseToAnyPublisher()
            
            sendOperations.append(eventSendOperation)
        }
        
        // Add history data send operation if we have data
        if historyData.count > 0 {
            let historySendOperation = connectionManager.sendData(historyData, to: deviceId)
                .map { _ in () }
                .mapError { error -> Error in
                    return SyncError.dataSendFailed(error)
                }
                .eraseToAnyPublisher()
            
            sendOperations.append(historySendOperation)
        }
        
        // If no operations, return success
        if sendOperations.isEmpty {
            return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        
        // Execute all send operations in sequence
        return sendOperations
            .publisher
            .flatMap { $0 }
            .collect()
            .map { _ in () }
            .eraseToAnyPublisher()
    }
    
    /// Requests data from a device
    /// - Parameter deviceId: The device's Bluetooth identifier
    /// - Returns: Publisher with received event and history data
    private func requestDataFromDevice(deviceId: String) -> AnyPublisher<(Data, Data), Error> {
        // Request data from device
        return connectionManager.requestDataFromDevice(identifier: deviceId)
            .map { data -> (Data, Data) in
                // In a real implementation, we would receive properly structured data
                // with separate event and history data. For now, simulate this.
                return (data, Data())
            }
            .mapError { error -> Error in
                return SyncError.dataReceiveFailed(error)
            }
            .eraseToAnyPublisher()
    }
    
    /// Processes received data from a device
    /// - Parameters:
    ///   - deviceId: The device's Bluetooth identifier
    ///   - eventData: Received event data
    ///   - historyData: Received edit history data
    /// - Returns: Publisher with counts of events received and conflicts
    private func processReceivedData(deviceId: String, eventData: Data, historyData: Data) -> AnyPublisher<(Int, Int), Error> {
        return Future<(Int, Int), Error> { promise in
            var eventsReceived = 0
            var conflicts = 0
            
            // Process event data
            if eventData.count > 0 {
                DataExchangeProtocol.deserializeAndImportEvents(
                    data: eventData,
                    context: PersistenceController.shared.container.newBackgroundContext()
                ) { result in
                    switch result {
                    case .success(let count):
                        eventsReceived = count
                        
                        // Process history data if available
                        if historyData.count > 0 {
                            self.processHistoryData(historyData) { historyResult in
                                switch historyResult {
                                case .success(let conflictCount):
                                    conflicts = conflictCount
                                    promise(.success((eventsReceived, conflicts)))
                                case .failure(let error):
                                    promise(.failure(error))
                                }
                            }
                        } else {
                            promise(.success((eventsReceived, conflicts)))
                        }
                    case .failure(let error):
                        promise(.failure(SyncError.dataProcessingFailed(error)))
                    }
                }
            } else {
                // No event data, check for history data
                if historyData.count > 0 {
                    self.processHistoryData(historyData) { historyResult in
                        switch historyResult {
                        case .success(let conflictCount):
                            conflicts = conflictCount
                            promise(.success((eventsReceived, conflicts)))
                        case .failure(let error):
                            promise(.failure(error))
                        }
                    }
                } else {
                    // No data to process
                    promise(.success((0, 0)))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Processes edit history data
    /// - Parameters:
    ///   - historyData: The history data to process
    ///   - completion: Completion handler with conflict count or error
    private func processHistoryData(_ historyData: Data, completion: @escaping (Result<Int, Error>) -> Void) {
        DataExchangeProtocol.deserializeAndImportEditHistory(
            data: historyData,
            context: PersistenceController.shared.container.newBackgroundContext()
        ) { result in
            switch result {
            case .success(let count):
                // In a real implementation, we would detect and resolve conflicts here
                // For now, just return a simulated conflict count
                let conflictCount = 0
                completion(.success(conflictCount))
            case .failure(let error):
                completion(.failure(SyncError.dataProcessingFailed(error)))
            }
        }
    }
    
    /// Determines if a failed sync should be retried
    /// - Parameter error: The error that caused the failure
    /// - Returns: True if retry is appropriate, false otherwise
    private func shouldRetry(_ error: Error) -> Bool {
        // Don't retry if the error is not recoverable
        if let syncError = error as? SyncError {
            switch syncError {
            case .syncAlreadyInProgress, .invalidSyncMode, .dataProcessingFailed:
                return false
            case .connectionFailed, .dataSendFailed, .dataReceiveFailed, .unknown:
                return true
            }
        }
        
        // By default, assume the error is recoverable
        return true
    }
}

// MARK: - Sync Errors

/// Errors that can occur during sync operations
enum SyncError: Error {
    case syncAlreadyInProgress
    case connectionFailed(Error)
    case dataSendFailed(Error)
    case dataReceiveFailed(Error)
    case dataProcessingFailed(Error)
    case invalidSyncMode
    case unknown(String)
    
    var localizedDescription: String {
        switch self {
        case .syncAlreadyInProgress:
            return "Sync is already in progress with this device"
        case .connectionFailed(let error):
            return "Failed to connect to device: \(error.localizedDescription)"
        case .dataSendFailed(let error):
            return "Failed to send data: \(error.localizedDescription)"
        case .dataReceiveFailed(let error):
            return "Failed to receive data: \(error.localizedDescription)"
        case .dataProcessingFailed(let error):
            return "Failed to process received data: \(error.localizedDescription)"
        case .invalidSyncMode:
            return "Invalid sync mode specified"
        case .unknown(let message):
            return "Unknown sync error: \(message)"
        }
    }
}

// MARK: - Logger Extension

extension Logger {
    /// Logger for sync operations
    static let sync = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Sync")
}

// MARK: - Repository Support

/// Repository for FamilyDevice entities
class FamilyDeviceRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    /// Fetches a device by its Bluetooth identifier
    /// - Parameter identifier: The Bluetooth identifier
    /// - Returns: The FamilyDevice if found, nil otherwise
    func fetchDeviceByBluetoothIdentifier(identifier: String) -> FamilyDevice? {
        let fetchRequest: NSFetchRequest<FamilyDevice> = FamilyDevice.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "bluetoothIdentifier == %@", identifier)
        
        do {
            let results = try context.fetch(fetchRequest)
            return results.first
        } catch {
            Logger.sync.error("Failed to fetch device by identifier: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Fetches devices with optional predicate and sort descriptors
    /// - Parameters:
    ///   - predicate: Optional predicate to filter devices
    ///   - sortDescriptors: Optional sort descriptors for ordering
    /// - Returns: Array of matching FamilyDevice entities
    func fetch(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> [FamilyDevice] {
        let fetchRequest: NSFetchRequest<FamilyDevice> = FamilyDevice.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        
        do {
            return try context.fetch(fetchRequest)
        } catch {
            Logger.sync.error("Failed to fetch devices: \(error.localizedDescription)")
            return []
        }
    }
}

/// Repository for SyncLog entities
class SyncLogRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    /// Fetches logs for a specific device, ordered by timestamp (newest first)
    /// - Parameter deviceId: The device identifier
    /// - Returns: Array of matching SyncLog entities
    func fetchLogsByDevice(deviceId: String) -> [SyncLog] {
        let fetchRequest: NSFetchRequest<SyncLog> = SyncLog.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deviceId == %@", deviceId)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            return try context.fetch(fetchRequest)
        } catch {
            Logger.sync.error("Failed to fetch sync logs: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Creates a new SyncLog entity
    /// - Parameters:
    ///   - deviceId: The device identifier
    ///   - deviceName: Optional device name
    /// - Returns: The created SyncLog entity
    func createSyncLog(deviceId: String, deviceName: String?) -> SyncLog {
        let syncLog = SyncLog(context: context)
        syncLog.id = UUID()
        syncLog.deviceId = deviceId
        syncLog.deviceName = deviceName
        syncLog.timestamp = Date()
        syncLog.eventsReceived = 0
        syncLog.eventsSent = 0
        syncLog.conflicts = 0
        
        return syncLog
    }
    
    /// Deletes logs older than a specified date
    /// - Parameter date: Cut-off date
    /// - Returns: Number of logs deleted
    /// - Throws: Core Data errors
    func deleteLogsOlderThan(date: Date) throws -> Int {
        let fetchRequest: NSFetchRequest<SyncLog> = SyncLog.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "timestamp < %@", date as NSDate)
        
        let logs = try context.fetch(fetchRequest)
        let count = logs.count
        
        for log in logs {
            context.delete(log)
        }
        
        try context.save()
        return count
    }
}

/// Repository for Event entities
class EventRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    /// Fetches events with optional predicate and sort descriptors
    /// - Parameters:
    ///   - predicate: Optional predicate to filter events
    ///   - sortDescriptors: Optional sort descriptors for ordering
    /// - Returns: Array of matching Event entities
    func fetch(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> [Event] {
        let fetchRequest: NSFetchRequest<Event> = Event.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: "month", ascending: true)]
        
        do {
            return try context.fetch(fetchRequest)
        } catch {
            Logger.sync.error("Failed to fetch events: \(error.localizedDescription)")
            return []
        }
    }
}

/// Repository for EditHistory entities
class EditHistoryRepository {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    /// Fetches edit histories with optional predicate and sort descriptors
    /// - Parameters:
    ///   - predicate: Optional predicate to filter histories
    ///   - sortDescriptors: Optional sort descriptors for ordering
    /// - Returns: Array of matching EditHistory entities
    func fetch(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil) -> [EditHistory] {
        let fetchRequest: NSFetchRequest<EditHistory> = EditHistory.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors ?? [NSSortDescriptor(key: "timestamp", ascending: false)]
        
        do {
            return try context.fetch(fetchRequest)
        } catch {
            Logger.sync.error("Failed to fetch edit histories: \(error.localizedDescription)")
            return []
        }
    }
}

/// Helper for Core Data transactions
class TransactionCoordinator {
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }
    
    /// Performs a transaction asynchronously
    /// - Parameters:
    ///   - transaction: The transaction to perform
    ///   - completion: Completion handler with optional error
    func performAsyncTransaction(_ transaction: @escaping () -> Void, completion: @escaping (Error?) -> Void) {
        context.perform {
            transaction()
            
            do {
                try self.context.save()
                completion(nil)
            } catch {
                Logger.sync.error("Transaction failed: \(error.localizedDescription)")
                completion(error)
            }
        }
    }
}