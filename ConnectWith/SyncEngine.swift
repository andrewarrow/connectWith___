import Foundation
import CoreData
import Combine
import OSLog

/// SyncEngine orchestrates incremental data synchronization between devices with 
/// error handling, retry logic, and comprehensive logging
class SyncEngine: ObservableObject {
    // Singleton instance
    static let shared = SyncEngine()
    
    // Managers
    private let connectionManager = ConnectionManager.shared
    private let syncHistoryManager = SyncHistoryManager.shared
    private let deviceManager = DeviceManager.shared
    
    // Core Data
    private let persistenceController = PersistenceController.shared
    
    // Published properties for UI updates
    @Published var syncInProgress: [String: Bool] = [:]
    @Published var syncProgress: [String: Double] = [:]
    @Published var lastSyncResults: [String: SyncResult] = [:]
    
    // Retry parameters
    private let maxRetryAttempts = 3
    private let initialRetryDelay: TimeInterval = 2.0
    
    // Sync queue for managing multiple concurrent operations
    private let syncQueue = DispatchQueue(label: "com.connectwith.syncQueue", qos: .userInitiated, attributes: .concurrent)
    private var syncOperations: [String: AnyCancellable] = [:]
    
    // MARK: - SyncResult Structure
    
    /// Represents the result of a sync operation
    struct SyncResult {
        let timestamp: Date
        let deviceId: String
        let deviceName: String?
        let success: Bool
        let eventsReceived: Int
        let eventsSent: Int
        let conflicts: Int
        let duration: TimeInterval
        let error: Error?
        let retryCount: Int
        
        init(
            deviceId: String,
            deviceName: String? = nil,
            success: Bool = false,
            eventsReceived: Int = 0,
            eventsSent: Int = 0,
            conflicts: Int = 0,
            duration: TimeInterval = 0,
            error: Error? = nil,
            retryCount: Int = 0
        ) {
            self.timestamp = Date()
            self.deviceId = deviceId
            self.deviceName = deviceName
            self.success = success
            self.eventsReceived = eventsReceived
            self.eventsSent = eventsSent
            self.conflicts = conflicts
            self.duration = duration
            self.error = error
            self.retryCount = retryCount
        }
    }
    
    // MARK: - SyncError Types
    
    /// Errors that can occur during sync operations
    enum SyncError: Error {
        case connectionError(Error)
        case transferError(Error)
        case dataFormatError(String)
        case conflictError(String)
        case deviceNotFound
        case syncInProgress
        case syncCancelled
        case maxRetriesExceeded
        case deviceNotConnected
        case timeoutError
        case unknownError
        
        var localizedDescription: String {
            switch self {
            case .connectionError(let error):
                return "Connection error: \(error.localizedDescription)"
            case .transferError(let error):
                return "Transfer error: \(error.localizedDescription)"
            case .dataFormatError(let message):
                return "Data format error: \(message)"
            case .conflictError(let message):
                return "Conflict error: \(message)"
            case .deviceNotFound:
                return "Device not found"
            case .syncInProgress:
                return "Sync already in progress"
            case .syncCancelled:
                return "Sync operation cancelled"
            case .maxRetriesExceeded:
                return "Maximum retry attempts exceeded"
            case .deviceNotConnected:
                return "Device not connected"
            case .timeoutError:
                return "Sync operation timed out"
            case .unknownError:
                return "Unknown error occurred"
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Sync Methods
    
    /// Syncs with a device using incremental updates
    /// - Parameters:
    ///   - deviceId: The Bluetooth identifier of the device
    ///   - mode: The sync mode (incremental by default)
    /// - Returns: A publisher that emits sync results or errors
    func syncWithDevice(deviceId: String, mode: DataExchangeProtocol.SyncMode = .incremental) -> AnyPublisher<SyncResult, Error> {
        let resultSubject = PassthroughSubject<SyncResult, Error>()
        
        // Check if sync is already in progress
        if syncInProgress[deviceId] == true {
            resultSubject.send(completion: .failure(SyncError.syncInProgress))
            return resultSubject.eraseToAnyPublisher()
        }
        
        // Set sync in progress and reset progress
        syncInProgress[deviceId] = true
        syncProgress[deviceId] = 0.0
        
        // Get device name for better logging
        var deviceName: String?
        if let device = deviceManager.getDevice(byBluetoothIdentifier: deviceId) {
            deviceName = device.customName
        }
        
        // Start tracking time
        let startTime = Date()
        
        Logger.sync.info("Starting sync with device: \(deviceId) (\(deviceName ?? "Unknown")) using \(mode.rawValue) mode")
        
        // Record the sync operation for potential cancellation
        let syncOperation = performSync(deviceId: deviceId, mode: mode, retryCount: 0)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self = self else { return }
                
                // Calculate sync duration
                let duration = Date().timeInterval(since: startTime)
                
                // Update sync state
                self.syncInProgress[deviceId] = false
                self.syncProgress[deviceId] = 1.0
                
                switch completion {
                case .finished:
                    // This is handled in receiveValue
                    break
                    
                case .failure(let error):
                    // Log the error
                    Logger.sync.error("Sync with device \(deviceId) failed: \(error.localizedDescription)")
                    
                    // Create error result
                    let result = SyncResult(
                        deviceId: deviceId,
                        deviceName: deviceName,
                        success: false,
                        duration: duration,
                        error: error,
                        retryCount: 0
                    )
                    
                    // Update last sync result
                    self.lastSyncResults[deviceId] = result
                    
                    // Send result to caller
                    resultSubject.send(result)
                    resultSubject.send(completion: .failure(error))
                }
                
                // Remove operation from tracking
                self.syncOperations.removeValue(forKey: deviceId)
            }, receiveValue: { [weak self] result in
                guard let self = self else { return }
                
                // Log success
                Logger.sync.info("Sync with device \(deviceId) completed successfully: \(result.eventsReceived) received, \(result.eventsSent) sent, \(result.conflicts) conflicts")
                
                // Update last sync result
                self.lastSyncResults[deviceId] = result
                
                // Send result to caller
                resultSubject.send(result)
                resultSubject.send(completion: .finished)
            })
        
        // Store operation for tracking
        syncOperations[deviceId] = syncOperation
        
        return resultSubject.eraseToAnyPublisher()
    }
    
    /// Cancels an ongoing sync operation
    /// - Parameter deviceId: The device ID to cancel sync for
    /// - Returns: True if sync was cancelled, false if no sync was in progress
    func cancelSync(deviceId: String) -> Bool {
        guard let operation = syncOperations[deviceId] else {
            return false
        }
        
        // Cancel the operation
        operation.cancel()
        
        // Update state
        syncInProgress[deviceId] = false
        syncProgress[deviceId] = 0.0
        syncOperations.removeValue(forKey: deviceId)
        
        // Log cancellation
        Logger.sync.info("Sync with device \(deviceId) cancelled")
        
        return true
    }
    
    /// Gets the last sync time for a device
    /// - Parameter deviceId: The device ID
    /// - Returns: The last sync time, or nil if device has never synced
    func getLastSyncTime(deviceId: String) -> Date? {
        return syncHistoryManager.getLastSyncTime(bluetoothIdentifier: deviceId)
    }
    
    /// Gets sync history for a device
    /// - Parameters:
    ///   - deviceId: The device ID
    ///   - limit: Maximum number of records to return
    /// - Returns: Array of sync logs
    func getSyncHistory(deviceId: String, limit: Int = 10) -> [SyncLog] {
        return syncHistoryManager.getRecentSyncLogs(bluetoothIdentifier: deviceId, limit: limit)
    }
    
    // MARK: - Private Sync Implementation
    
    /// Performs the actual sync operation with retry logic
    /// - Parameters:
    ///   - deviceId: The device ID to sync with
    ///   - mode: The sync mode
    ///   - retryCount: The current retry attempt
    /// - Returns: A publisher with sync results
    private func performSync(deviceId: String, mode: DataExchangeProtocol.SyncMode, retryCount: Int) -> AnyPublisher<SyncResult, Error> {
        // Check device connection status
        if connectionManager.getConnectionStatus(identifier: deviceId) != .connected {
            // Try to establish connection first
            return connectToDevice(deviceId: deviceId)
                .flatMap { [weak self] connected -> AnyPublisher<SyncResult, Error> in
                    guard let self = self else {
                        return Fail(error: SyncError.unknownError).eraseToAnyPublisher()
                    }
                    
                    if connected {
                        // Proceed with sync now that we're connected
                        return self.executeSyncProcess(deviceId: deviceId, mode: mode, retryCount: retryCount)
                    } else {
                        return Fail(error: SyncError.deviceNotConnected).eraseToAnyPublisher()
                    }
                }
                .eraseToAnyPublisher()
        } else {
            // Already connected, proceed with sync
            return executeSyncProcess(deviceId: deviceId, mode: mode, retryCount: retryCount)
        }
    }
    
    /// Connects to a device
    /// - Parameter deviceId: The device ID to connect to
    /// - Returns: A publisher that emits connection success or failure
    private func connectToDevice(deviceId: String) -> AnyPublisher<Bool, Error> {
        return connectionManager.connectToDevice(identifier: deviceId)
            .handleEvents(receiveSubscription: { [weak self] _ in
                self?.updateSyncProgress(deviceId: deviceId, progress: 0.1)
            }, receiveOutput: { [weak self] _ in
                self?.updateSyncProgress(deviceId: deviceId, progress: 0.2)
            })
            .mapError { error -> Error in
                return SyncError.connectionError(error)
            }
            .eraseToAnyPublisher()
    }
    
    /// Executes the full sync process with a connected device
    /// - Parameters:
    ///   - deviceId: The device ID to sync with
    ///   - mode: The sync mode
    ///   - retryCount: The current retry attempt
    /// - Returns: A publisher with sync results
    private func executeSyncProcess(deviceId: String, mode: DataExchangeProtocol.SyncMode, retryCount: Int) -> AnyPublisher<SyncResult, Error> {
        let startTime = Date()
        
        // Get device name and last sync time
        var deviceName: String?
        var lastSyncTime: Date? = nil
        
        if let device = deviceManager.getDevice(byBluetoothIdentifier: deviceId) {
            deviceName = device.customName
            if mode == .incremental {
                lastSyncTime = device.lastSyncTimestamp
            }
        }
        
        // Create a sync request
        let syncRequest = createSyncRequest(deviceId: deviceId, mode: mode, lastSyncTime: lastSyncTime)
        
        // Start by sending the sync request
        return sendSyncRequest(deviceId: deviceId, request: syncRequest)
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.updateSyncProgress(deviceId: deviceId, progress: 0.3)
            })
            .flatMap { [weak self] _ -> AnyPublisher<(Data, Data), Error> in
                guard let self = self else {
                    return Fail(error: SyncError.unknownError).eraseToAnyPublisher()
                }
                
                // Serialize our local data for sending
                return self.prepareOutgoingData(deviceId: deviceId, mode: mode, lastSyncTime: lastSyncTime)
                    .handleEvents(receiveOutput: { [weak self] _ in
                        self?.updateSyncProgress(deviceId: deviceId, progress: 0.4)
                    })
                    .eraseToAnyPublisher()
            }
            .flatMap { [weak self] (eventsData, historyData) -> AnyPublisher<Bool, Error> in
                guard let self = self else {
                    return Fail(error: SyncError.unknownError).eraseToAnyPublisher()
                }
                
                // Send our data to the remote device
                return self.sendLocalData(deviceId: deviceId, eventsData: eventsData, historyData: historyData)
                    .handleEvents(receiveOutput: { [weak self] _ in
                        self?.updateSyncProgress(deviceId: deviceId, progress: 0.6)
                    })
                    .eraseToAnyPublisher()
            }
            .flatMap { [weak self] _ -> AnyPublisher<(Data, Data), Error> in
                guard let self = self else {
                    return Fail(error: SyncError.unknownError).eraseToAnyPublisher()
                }
                
                // Request data from the remote device
                return self.requestRemoteData(deviceId: deviceId)
                    .handleEvents(receiveOutput: { [weak self] _ in
                        self?.updateSyncProgress(deviceId: deviceId, progress: 0.8)
                    })
                    .eraseToAnyPublisher()
            }
            .flatMap { [weak self] (remoteEventsData, remoteHistoryData) -> AnyPublisher<SyncResult, Error> in
                guard let self = self else {
                    return Fail(error: SyncError.unknownError).eraseToAnyPublisher()
                }
                
                // Process received data
                return self.processReceivedData(deviceId: deviceId, eventsData: remoteEventsData, historyData: remoteHistoryData)
                    .handleEvents(receiveOutput: { [weak self] _ in
                        self?.updateSyncProgress(deviceId: deviceId, progress: 0.9)
                    })
                    .eraseToAnyPublisher()
            }
            .mapError { [weak self] error -> Error in
                guard let self = self else { return error }
                
                // Log error
                Logger.sync.error("Sync error: \(error.localizedDescription)")
                
                // Check if we should retry
                if retryCount < self.maxRetryAttempts {
                    // Calculate delay with exponential backoff
                    let delay = self.initialRetryDelay * pow(2.0, Double(retryCount))
                    
                    Logger.sync.info("Retrying sync (attempt \(retryCount + 1)/\(self.maxRetryAttempts)) after \(delay) seconds")
                    
                    // Retry after delay
                    return Delay.delay(for: .seconds(delay), scheduler: self.syncQueue)
                        .flatMap { [weak self] _ -> AnyPublisher<SyncResult, Error> in
                            guard let self = self else {
                                return Fail(error: SyncError.unknownError).eraseToAnyPublisher()
                            }
                            
                            return self.performSync(deviceId: deviceId, mode: mode, retryCount: retryCount + 1)
                        }
                        .mapError { $0 }
                        .eraseToAnyPublisher()
                }
                
                return SyncError.maxRetriesExceeded
            }
            .map { result -> SyncResult in
                // Calculate final duration
                let duration = Date().timeInterval(since: startTime)
                
                // Create a new result with the correct duration and retry count
                return SyncResult(
                    deviceId: deviceId,
                    deviceName: deviceName,
                    success: result.success,
                    eventsReceived: result.eventsReceived,
                    eventsSent: result.eventsSent,
                    conflicts: result.conflicts,
                    duration: duration,
                    error: result.error,
                    retryCount: retryCount
                )
            }
            .handleEvents(receiveOutput: { [weak self] result in
                guard let self = self else { return }
                
                // Log sync statistics
                self.syncHistoryManager.createSyncLog(
                    deviceId: deviceId,
                    deviceName: deviceName,
                    eventsReceived: result.eventsReceived,
                    eventsSent: result.eventsSent,
                    conflicts: result.conflicts,
                    resolutionMethod: result.conflicts > 0 ? "merge" : "none"
                )
                
                // Update last sync timestamp in FamilyDevice
                if result.success {
                    self.updateDeviceLastSync(deviceId: deviceId)
                }
            })
            .eraseToAnyPublisher()
    }
    
    /// Creates a sync request message
    /// - Parameters:
    ///   - deviceId: The device ID to sync with
    ///   - mode: The sync mode
    ///   - lastSyncTime: The last sync time for incremental sync
    /// - Returns: The sync request message
    private func createSyncRequest(deviceId: String, mode: DataExchangeProtocol.SyncMode, lastSyncTime: Date?) -> DataExchangeProtocol.SyncRequestMessage {
        // Create sync request with appropriate entity types
        return DataExchangeProtocol.SyncRequestMessage(
            deviceId: deviceId,
            syncMode: mode,
            lastSyncTimestamp: lastSyncTime,
            entityTypes: [.event, .editHistory, .deviceInfo]
        )
    }
    
    /// Sends a sync request to the remote device
    /// - Parameters:
    ///   - deviceId: The device ID to send to
    ///   - request: The sync request
    /// - Returns: A publisher with sync response or error
    private func sendSyncRequest(deviceId: String, request: DataExchangeProtocol.SyncRequestMessage) -> AnyPublisher<DataExchangeProtocol.SyncResponseMessage, Error> {
        let requestData = DataExchangeProtocol.serialize(request)
        
        // If serialization failed, return error
        guard let requestData = requestData else {
            return Fail(error: SyncError.dataFormatError("Failed to serialize sync request")).eraseToAnyPublisher()
        }
        
        // Send request data
        return connectionManager.sendData(requestData, to: deviceId)
            .flatMap { _ -> AnyPublisher<Data, Error> in
                // After sending request, wait for response
                return self.connectionManager.requestDataFromDevice(identifier: deviceId)
            }
            .map { responseData -> DataExchangeProtocol.SyncResponseMessage in
                // Deserialize response
                guard let response = DataExchangeProtocol.deserialize(responseData, to: DataExchangeProtocol.SyncResponseMessage.self) else {
                    throw SyncError.dataFormatError("Failed to deserialize sync response")
                }
                
                // Validate response
                if !response.accepted {
                    let errorMessage = response.errorMessage ?? "Unknown reason"
                    throw SyncError.dataFormatError("Sync request rejected: \(errorMessage)")
                }
                
                return response
            }
            .eraseToAnyPublisher()
    }
    
    /// Prepares local data to be sent to the remote device
    /// - Parameters:
    ///   - deviceId: The device ID to send to
    ///   - mode: The sync mode
    ///   - lastSyncTime: The last sync time for incremental sync
    /// - Returns: A publisher with prepared events and history data
    private func prepareOutgoingData(deviceId: String, mode: DataExchangeProtocol.SyncMode, lastSyncTime: Date?) -> AnyPublisher<(Data, Data), Error> {
        return Future<(Data, Data), Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(SyncError.unknownError))
                return
            }
            
            // Use a background context for serialization
            self.persistenceController.performBackgroundTask { context in
                // Serialize events
                let eventsData = DataExchangeProtocol.serializeEvents(
                    context: context,
                    deviceId: self.getLocalDeviceId(),
                    lastSyncTime: mode == .incremental ? lastSyncTime : nil
                )
                
                // Serialize edit history
                let historyData = DataExchangeProtocol.serializeEditHistory(
                    context: context,
                    deviceId: self.getLocalDeviceId(),
                    lastSyncTime: mode == .incremental ? lastSyncTime : nil
                )
                
                // Check for serialization errors
                guard let events = eventsData, let history = historyData else {
                    promise(.failure(SyncError.dataFormatError("Failed to serialize outgoing data")))
                    return
                }
                
                Logger.sync.info("Prepared outgoing data: \(events.count) bytes of events, \(history.count) bytes of history")
                promise(.success((events, history)))
            }
        }.eraseToAnyPublisher()
    }
    
    /// Sends local data to the remote device
    /// - Parameters:
    ///   - deviceId: The device ID to send to
    ///   - eventsData: The events data to send
    ///   - historyData: The history data to send
    /// - Returns: A publisher with success or error
    private func sendLocalData(deviceId: String, eventsData: Data, historyData: Data) -> AnyPublisher<Bool, Error> {
        // Split events into chunks for transmission
        let eventChunks = DataExchangeProtocol.splitDataIntoChunks(
            eventsData,
            deviceId: getLocalDeviceId(),
            entityType: .event
        )
        
        // Split history into chunks for transmission
        let historyChunks = DataExchangeProtocol.splitDataIntoChunks(
            historyData,
            deviceId: getLocalDeviceId(),
            entityType: .editHistory
        )
        
        // Track progress for UI updates
        let totalChunks = eventChunks.count + historyChunks.count
        var sentChunks = 0
        
        // Combine the publishers for sending each chunk
        let sendEventsPublisher = Publishers.Sequence<[DataExchangeProtocol.DataChunkMessage], Error>(sequence: eventChunks)
            .flatMap { chunk -> AnyPublisher<Bool, Error> in
                let chunkData = DataExchangeProtocol.serialize(chunk)
                guard let chunkData = chunkData else {
                    return Fail(error: SyncError.dataFormatError("Failed to serialize event chunk")).eraseToAnyPublisher()
                }
                
                return self.connectionManager.sendData(chunkData, to: deviceId)
                    .map { _ -> Bool in
                        sentChunks += 1
                        let progress = Double(sentChunks) / Double(totalChunks) * 0.5 + 0.4
                        self.updateSyncProgress(deviceId: deviceId, progress: progress)
                        return true
                    }
                    .eraseToAnyPublisher()
            }
            .collect()
            .map { _ in true }
            .eraseToAnyPublisher()
        
        let sendHistoryPublisher = Publishers.Sequence<[DataExchangeProtocol.DataChunkMessage], Error>(sequence: historyChunks)
            .flatMap { chunk -> AnyPublisher<Bool, Error> in
                let chunkData = DataExchangeProtocol.serialize(chunk)
                guard let chunkData = chunkData else {
                    return Fail(error: SyncError.dataFormatError("Failed to serialize history chunk")).eraseToAnyPublisher()
                }
                
                return self.connectionManager.sendData(chunkData, to: deviceId)
                    .map { _ -> Bool in
                        sentChunks += 1
                        let progress = Double(sentChunks) / Double(totalChunks) * 0.5 + 0.4
                        self.updateSyncProgress(deviceId: deviceId, progress: progress)
                        return true
                    }
                    .eraseToAnyPublisher()
            }
            .collect()
            .map { _ in true }
            .eraseToAnyPublisher()
        
        // Execute both send operations in sequence
        return sendEventsPublisher
            .flatMap { _ in sendHistoryPublisher }
            .eraseToAnyPublisher()
    }
    
    /// Requests data from the remote device
    /// - Parameter deviceId: The device ID to request from
    /// - Returns: A publisher with received events and history data
    private func requestRemoteData(deviceId: String) -> AnyPublisher<(Data, Data), Error> {
        return connectionManager.requestDataFromDevice(identifier: deviceId)
            .map { data -> (Data, Data) in
                // In a more complete implementation, this would parse received data into events
                // and history portions. For now, we'll use a placeholder implementation.
                return (data, Data())
            }
            .eraseToAnyPublisher()
    }
    
    /// Processes data received from the remote device
    /// - Parameters:
    ///   - deviceId: The device ID the data came from
    ///   - eventsData: The events data received
    ///   - historyData: The history data received
    /// - Returns: A publisher with sync results
    private func processReceivedData(deviceId: String, eventsData: Data, historyData: Data) -> AnyPublisher<SyncResult, Error> {
        return Future<SyncResult, Error> { [weak self] promise in
            guard let self = self else {
                promise(.failure(SyncError.unknownError))
                return
            }
            
            // Process data in a background context
            self.persistenceController.performBackgroundTask { context in
                var eventsReceived = 0
                var historyReceived = 0
                var conflicts = 0
                
                // Get local and base events for conflict detection
                var localEvents: [EventDTO] = []
                var baseEvents: [EventDTO] = []
                
                // First, get local events that might conflict
                do {
                    let eventRepository = EventRepository(context: context)
                    let events = eventRepository.fetch(predicate: nil, sortDescriptors: nil)
                    
                    // Convert events to DTOs for conflict detection
                    localEvents = events.map { EventDTO.from(event: $0) }
                    
                    // Get last sync time for base events
                    let lastSyncTime = self.syncHistoryManager.getLastSyncTime(bluetoothIdentifier: deviceId)
                    
                    if let syncTime = lastSyncTime {
                        // Query for events as they were at last sync time (base version)
                        // This is simplified - in a real implementation, we would need to restore events
                        // to their state at the last sync time using edit history
                        let baseEventsFetch = eventRepository.fetch(
                            predicate: NSPredicate(format: "lastModifiedAt <= %@", syncTime as NSDate),
                            sortDescriptors: nil
                        )
                        baseEvents = baseEventsFetch.map { EventDTO.from(event: $0) }
                    }
                } catch {
                    Logger.sync.error("Error fetching local events for conflict detection: \(error.localizedDescription)")
                }
                
                // Deserialize remote events for processing
                var remoteEvents: [EventDTO] = []
                var detectableConflicts = false
                
                if eventsData.count > 0 {
                    // Parse the events data into DTOs
                    if let eventBatch: DataExchangeProtocol.EventBatch = DataExchangeProtocol.deserialize(eventsData, to: DataExchangeProtocol.EventBatch.self) {
                        remoteEvents = eventBatch.events
                        detectableConflicts = !remoteEvents.isEmpty && !localEvents.isEmpty
                        
                        // Process conflicts if we have potential conflicts
                        if detectableConflicts {
                            // Detect conflicts between local and remote events
                            let detectedConflicts = ConflictDetector.detectEventConflicts(
                                localEvents: localEvents,
                                remoteEvents: remoteEvents,
                                baseEvents: baseEvents.isEmpty ? nil : baseEvents
                            )
                            
                            conflicts = detectedConflicts.count
                            
                            if conflicts > 0 {
                                Logger.sync.info("Detected \(conflicts) event conflicts with device \(deviceId)")
                                
                                // Use the conflict resolution engine to resolve the conflicts
                                let resolutionEngine = ConflictResolutionEngine.shared
                                for conflict in detectedConflicts {
                                    let resolution = resolutionEngine.resolveEventConflict(
                                        baseEvent: conflict.base,
                                        localEvent: conflict.local,
                                        remoteEvent: conflict.remote,
                                        context: context
                                    )
                                    
                                    Logger.sync.info("Resolved conflict for event \(resolution.entityId): \(resolution.resolution.rawValue)")
                                }
                                
                                // After resolving conflicts, save the context
                                do {
                                    try context.save()
                                } catch {
                                    Logger.sync.error("Error saving context after conflict resolution: \(error.localizedDescription)")
                                }
                            }
                        }
                        
                        // Import remaining non-conflicting remote events
                        DataExchangeProtocol.deserializeAndImportEvents(data: eventsData, context: context) { result in
                            switch result {
                            case .success(let count):
                                eventsReceived = count
                                
                            case .failure(let error):
                                promise(.failure(SyncError.dataFormatError("Failed to import events: \(error.localizedDescription)")))
                                return
                            }
                        }
                    } else {
                        Logger.sync.error("Failed to deserialize remote events batch")
                        promise(.failure(SyncError.dataFormatError("Failed to deserialize events batch")))
                        return
                    }
                }
                
                // Import history if we have any
                if historyData.count > 0 {
                    DataExchangeProtocol.deserializeAndImportEditHistory(data: historyData, context: context) { result in
                        switch result {
                        case .success(let count):
                            historyReceived = count
                            
                        case .failure(let error):
                            promise(.failure(SyncError.dataFormatError("Failed to import history: \(error.localizedDescription)")))
                            return
                        }
                    }
                }
                
                // Get device name
                var deviceName: String?
                let fetchRequest = FamilyDevice.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "bluetoothIdentifier == %@", deviceId)
                
                do {
                    let results = try context.fetch(fetchRequest)
                    deviceName = results.first?.customName
                } catch {
                    Logger.sync.error("Error fetching device name: \(error.localizedDescription)")
                }
                
                // Create success result
                let result = SyncResult(
                    deviceId: deviceId,
                    deviceName: deviceName,
                    success: true,
                    eventsReceived: eventsReceived,
                    eventsSent: eventsData.count > 0 ? 1 : 0,
                    conflicts: conflicts
                )
                
                promise(.success(result))
            }
        }.eraseToAnyPublisher()
    }
    
    /// Updates the sync progress for UI updates
    /// - Parameters:
    ///   - deviceId: The device ID
    ///   - progress: The progress value (0.0 - 1.0)
    private func updateSyncProgress(deviceId: String, progress: Double) {
        DispatchQueue.main.async {
            self.syncProgress[deviceId] = min(1.0, max(0.0, progress))
        }
    }
    
    /// Updates the last sync timestamp for a device
    /// - Parameter deviceId: The device ID
    private func updateDeviceLastSync(deviceId: String) {
        persistenceController.performBackgroundTask { context in
            let fetchRequest = FamilyDevice.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "bluetoothIdentifier == %@", deviceId)
            
            do {
                let results = try context.fetch(fetchRequest)
                if let device = results.first {
                    device.lastSyncTimestamp = Date()
                }
            } catch {
                Logger.sync.error("Error updating last sync timestamp: \(error.localizedDescription)")
            }
        }
    }
    
    /// Gets the ID of the local device
    /// - Returns: The local device ID
    private func getLocalDeviceId() -> String {
        let localDevice = deviceManager.getLocalDevice()
        return localDevice.bluetoothIdentifier
    }
}

// MARK: - Logger Extension
extension Logger {
    static let sync = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.connectwith", category: "Sync")
}

// MARK: - Delay Helper
struct Delay {
    static func delay<T>(for duration: DispatchQueue.SchedulerTimeType.Stride, scheduler: DispatchQueue) -> AnyPublisher<T, Never> {
        return Just<T>(T.self as! T)
            .delay(for: duration, scheduler: scheduler)
            .eraseToAnyPublisher()
    }
}