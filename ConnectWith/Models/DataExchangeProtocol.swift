import Foundation
import CoreData

/// DataExchangeProtocol handles serialization, deserialization, and the protocol
/// for exchanging calendar data between devices over Bluetooth
class DataExchangeProtocol {
    // MARK: - Protocol Constants
    
    /// Current protocol version - increment when making breaking changes
    static let protocolVersion = "1.0"
    
    /// Maximum size (in bytes) of a single data chunk
    static let maxChunkSize = 512
    
    /// Chunk data header size (used to calculate available payload size)
    static let chunkHeaderSize = 64
    
    /// Maximum payload size per chunk
    static let maxPayloadSize = maxChunkSize - chunkHeaderSize
    
    // MARK: - Message Types
    
    /// Types of messages in the data exchange protocol
    enum MessageType: String, Codable {
        case syncRequest = "sync_request"      // Request to start sync
        case syncResponse = "sync_response"    // Response to sync request
        case dataChunk = "data_chunk"          // A chunk of data
        case chunkAck = "chunk_ack"            // Acknowledgment of a chunk
        case syncComplete = "sync_complete"    // Sync operation complete
        case error = "error"                   // Error message
    }
    
    // MARK: - Sync Mode
    
    /// Modes for sync operations
    enum SyncMode: String, Codable {
        case full = "full"                // Full dataset exchange
        case incremental = "incremental"  // Only changes since last sync
        case pull = "pull"                // Request data from remote device
        case push = "push"                // Send data to remote device
    }
    
    // MARK: - Transfer Entity Types
    
    /// Entity types that can be transferred
    enum EntityType: String, Codable {
        case event = "event"
        case deviceInfo = "device_info"
        case editHistory = "edit_history"
        case syncLog = "sync_log"
    }
    
    // MARK: - Message Structures
    
    /// Base message structure that all protocol messages extend
    struct BaseMessage: Codable {
        let protocolVersion: String
        let messageType: MessageType
        let timestamp: Date
        let deviceId: String
        
        init(messageType: MessageType, deviceId: String) {
            self.protocolVersion = DataExchangeProtocol.protocolVersion
            self.messageType = messageType
            self.timestamp = Date()
            self.deviceId = deviceId
        }
    }
    
    /// Request to start a sync operation
    struct SyncRequestMessage: Codable {
        let base: BaseMessage
        let syncMode: SyncMode
        let lastSyncTimestamp: Date?
        let entityTypes: [EntityType]
        
        init(deviceId: String, syncMode: SyncMode, lastSyncTimestamp: Date? = nil, entityTypes: [EntityType]) {
            self.base = BaseMessage(messageType: .syncRequest, deviceId: deviceId)
            self.syncMode = syncMode
            self.lastSyncTimestamp = lastSyncTimestamp
            self.entityTypes = entityTypes
        }
    }
    
    /// Response to a sync request
    struct SyncResponseMessage: Codable {
        let base: BaseMessage
        let accepted: Bool
        let totalChunks: Int?
        let estimatedSize: Int?
        let errorMessage: String?
        
        init(deviceId: String, accepted: Bool, totalChunks: Int? = nil, estimatedSize: Int? = nil, errorMessage: String? = nil) {
            self.base = BaseMessage(messageType: .syncResponse, deviceId: deviceId)
            self.accepted = accepted
            self.totalChunks = totalChunks
            self.estimatedSize = estimatedSize
            self.errorMessage = errorMessage
        }
    }
    
    /// A chunk of data in a sync operation
    struct DataChunkMessage: Codable {
        let base: BaseMessage
        let chunkIndex: Int
        let totalChunks: Int
        let entityType: EntityType
        let compressed: Bool
        let payload: Data
        let checksum: String // Base64-encoded SHA-256 hash of the payload
        
        init(deviceId: String, chunkIndex: Int, totalChunks: Int, entityType: EntityType, payload: Data, compressed: Bool = true) {
            self.base = BaseMessage(messageType: .dataChunk, deviceId: deviceId)
            self.chunkIndex = chunkIndex
            self.totalChunks = totalChunks
            self.entityType = entityType
            self.compressed = compressed
            
            // If compression is enabled, compress the payload
            if compressed {
                self.payload = DataExchangeProtocol.compressData(payload)
            } else {
                self.payload = payload
            }
            
            // Calculate checksum
            self.checksum = DataExchangeProtocol.calculateChecksum(for: self.payload)
        }
    }
    
    /// Acknowledgment of a received chunk
    struct ChunkAckMessage: Codable {
        let base: BaseMessage
        let chunkIndex: Int
        let received: Bool
        let errorMessage: String?
        
        init(deviceId: String, chunkIndex: Int, received: Bool, errorMessage: String? = nil) {
            self.base = BaseMessage(messageType: .chunkAck, deviceId: deviceId)
            self.chunkIndex = chunkIndex
            self.received = received
            self.errorMessage = errorMessage
        }
    }
    
    /// Indication that a sync operation is complete
    struct SyncCompleteMessage: Codable {
        let base: BaseMessage
        let successful: Bool
        let chunksReceived: Int
        let entitiesProcessed: Int
        let conflicts: Int
        let syncTimestamp: Date
        
        init(deviceId: String, successful: Bool, chunksReceived: Int, entitiesProcessed: Int, conflicts: Int) {
            self.base = BaseMessage(messageType: .syncComplete, deviceId: deviceId)
            self.successful = successful
            self.chunksReceived = chunksReceived
            self.entitiesProcessed = entitiesProcessed
            self.conflicts = conflicts
            self.syncTimestamp = Date()
        }
    }
    
    /// Error message
    struct ErrorMessage: Codable {
        let base: BaseMessage
        let errorCode: Int
        let errorMessage: String
        
        init(deviceId: String, errorCode: Int, errorMessage: String) {
            self.base = BaseMessage(messageType: .error, deviceId: deviceId)
            self.errorCode = errorCode
            self.errorMessage = errorMessage
        }
    }
    
    // MARK: - Data Transfer Objects
    
    /// DTO for Event entity
    struct EventDTO: Codable {
        let id: UUID
        let title: String
        let location: String?
        let day: Int
        let month: Int
        let createdAt: Date
        let lastModifiedAt: Date
        let lastModifiedBy: String
        let color: String?
        
        /// Create DTO from Core Data Event entity
        static func from(event: Event) -> EventDTO {
            return EventDTO(
                id: event.id,
                title: event.title,
                location: event.location,
                day: Int(event.day),
                month: Int(event.month),
                createdAt: event.createdAt,
                lastModifiedAt: event.lastModifiedAt,
                lastModifiedBy: event.lastModifiedBy,
                color: event.color
            )
        }
        
        /// Convert DTO to Core Data Event entity
        func toEntity(context: NSManagedObjectContext) -> Event {
            // Check if event already exists
            let fetchRequest = Event.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            do {
                let results = try context.fetch(fetchRequest)
                if let existingEvent = results.first {
                    // Update existing event
                    existingEvent.title = title
                    existingEvent.location = location
                    existingEvent.day = Int16(day)
                    existingEvent.month = Int16(month)
                    existingEvent.lastModifiedAt = lastModifiedAt
                    existingEvent.lastModifiedBy = lastModifiedBy
                    existingEvent.color = color
                    
                    return existingEvent
                }
            } catch {
                print("Error fetching existing event: \(error)")
            }
            
            // Create new event
            let event = Event(context: context)
            event.id = id
            event.title = title
            event.location = location
            event.day = Int16(day)
            event.month = Int16(month)
            event.createdAt = createdAt
            event.lastModifiedAt = lastModifiedAt
            event.lastModifiedBy = lastModifiedBy
            event.color = color
            
            return event
        }
    }
    
    /// DTO for EditHistory entity with enhanced support for chronological merging
    struct EditHistoryDTO: Codable {
        let id: UUID
        let deviceId: String
        let deviceName: String?
        let previousTitle: String?
        let newTitle: String?
        let previousLocation: String?
        let newLocation: String?
        let previousDay: Int?
        let newDay: Int?
        let timestamp: Date
        let eventId: UUID
        
        // Enhanced fields for history merging
        let sourceVersion: String?  // Protocol version that created this record
        let isConflictResolution: Bool? // Whether this record was created as part of conflict resolution
        let mergeId: UUID? // ID linking related merge records
        let parentHistoryIds: [UUID]? // IDs of parent history records
        
        /// Create DTO from Core Data EditHistory entity
        static func from(history: EditHistory) -> EditHistoryDTO? {
            guard let event = history.event else { return nil }
            
            return EditHistoryDTO(
                id: history.id,
                deviceId: history.deviceId,
                deviceName: history.deviceName,
                previousTitle: history.previousTitle,
                newTitle: history.newTitle,
                previousLocation: history.previousLocation,
                newLocation: history.newLocation,
                previousDay: history.previousDay > 0 ? Int(history.previousDay) : nil,
                newDay: history.newDay > 0 ? Int(history.newDay) : nil,
                timestamp: history.timestamp,
                eventId: event.id,
                sourceVersion: protocolVersion, // Current protocol version
                isConflictResolution: false, // Will be set to true in conflict resolution
                mergeId: nil, // Set during conflict merging
                parentHistoryIds: nil // Set during conflict merging
            )
        }
        
        /// Create a special conflict resolution history
        static func createConflictResolution(
            localHistory: EditHistoryDTO,
            remoteHistory: EditHistoryDTO,
            resolvedValues: [String: Any],
            timestamp: Date = Date()
        ) -> EditHistoryDTO {
            // Create a unique merge ID to link the records
            let mergeId = UUID()
            
            // Extract fields from resolved values
            let newTitle = resolvedValues["title"] as? String
            let newLocation = resolvedValues["location"] as? String
            let newDay = resolvedValues["day"] as? Int
            
            return EditHistoryDTO(
                id: UUID(), // New record
                deviceId: "conflict_resolution",
                deviceName: "Conflict Resolution",
                previousTitle: "CONFLICT: \(localHistory.newTitle ?? "") vs \(remoteHistory.newTitle ?? "")",
                newTitle: newTitle,
                previousLocation: "CONFLICT: \(localHistory.newLocation ?? "") vs \(remoteHistory.newLocation ?? "")",
                newLocation: newLocation,
                previousDay: localHistory.newDay ?? remoteHistory.newDay,
                newDay: newDay,
                timestamp: timestamp,
                eventId: localHistory.eventId,
                sourceVersion: protocolVersion,
                isConflictResolution: true,
                mergeId: mergeId,
                parentHistoryIds: [localHistory.id, remoteHistory.id]
            )
        }
        
        /// Convert DTO to Core Data EditHistory entity
        func toEntity(context: NSManagedObjectContext) -> EditHistory? {
            // First, find the associated event
            let eventFetchRequest = Event.fetchRequest()
            eventFetchRequest.predicate = NSPredicate(format: "id == %@", eventId as CVarArg)
            
            do {
                let eventResults = try context.fetch(eventFetchRequest)
                guard let event = eventResults.first else { return nil }
                
                // Check if history already exists
                let historyFetchRequest = EditHistory.fetchRequest()
                historyFetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                
                let historyResults = try context.fetch(historyFetchRequest)
                if let existingHistory = historyResults.first {
                    // Update existing history
                    existingHistory.deviceId = deviceId
                    existingHistory.deviceName = deviceName
                    existingHistory.previousTitle = previousTitle
                    existingHistory.newTitle = newTitle
                    existingHistory.previousLocation = previousLocation
                    existingHistory.newLocation = newLocation
                    
                    if let prevDay = previousDay {
                        existingHistory.previousDay = Int16(prevDay)
                    }
                    
                    if let nDay = newDay {
                        existingHistory.newDay = Int16(nDay)
                    }
                    
                    existingHistory.timestamp = timestamp
                    existingHistory.event = event
                    
                    return existingHistory
                }
                
                // Create new history
                let history = EditHistory(context: context)
                history.id = id
                history.deviceId = deviceId
                history.deviceName = deviceName
                history.previousTitle = previousTitle
                history.newTitle = newTitle
                history.previousLocation = previousLocation
                history.newLocation = newLocation
                
                if let prevDay = previousDay {
                    history.previousDay = Int16(prevDay)
                }
                
                if let nDay = newDay {
                    history.newDay = Int16(nDay)
                }
                
                history.timestamp = timestamp
                history.event = event
                
                return history
                
            } catch {
                print("Error creating edit history entity: \(error)")
                return nil
            }
        }
    }
    
    /// DTO for FamilyDevice entity
    struct FamilyDeviceDTO: Codable {
        let id: UUID
        let bluetoothIdentifier: String
        let customName: String?
        let lastSyncTimestamp: Date?
        let isLocalDevice: Bool
        
        /// Create DTO from Core Data FamilyDevice entity
        static func from(device: FamilyDevice) -> FamilyDeviceDTO {
            return FamilyDeviceDTO(
                id: device.id,
                bluetoothIdentifier: device.bluetoothIdentifier,
                customName: device.customName,
                lastSyncTimestamp: device.lastSyncTimestamp,
                isLocalDevice: device.isLocalDevice
            )
        }
        
        /// Convert DTO to Core Data FamilyDevice entity
        func toEntity(context: NSManagedObjectContext) -> FamilyDevice {
            // Check if device already exists
            let fetchRequest = FamilyDevice.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "bluetoothIdentifier == %@", bluetoothIdentifier)
            
            do {
                let results = try context.fetch(fetchRequest)
                if let existingDevice = results.first {
                    // Update existing device
                    existingDevice.id = id
                    existingDevice.customName = customName
                    existingDevice.lastSyncTimestamp = lastSyncTimestamp
                    
                    // Don't override local device status
                    if !existingDevice.isLocalDevice {
                        existingDevice.isLocalDevice = isLocalDevice
                    }
                    
                    return existingDevice
                }
            } catch {
                print("Error fetching existing device: \(error)")
            }
            
            // Create new device
            let device = FamilyDevice(context: context)
            device.id = id
            device.bluetoothIdentifier = bluetoothIdentifier
            device.customName = customName
            device.lastSyncTimestamp = lastSyncTimestamp
            device.isLocalDevice = isLocalDevice
            
            return device
        }
    }
    
    // MARK: - Batch Transfer Containers
    
    /// Container for a batch of events
    struct EventBatch: Codable {
        let events: [EventDTO]
        let sourceDeviceId: String
        let batchTimestamp: Date
    }
    
    /// Container for a batch of edit histories
    struct EditHistoryBatch: Codable {
        let histories: [EditHistoryDTO]
        let sourceDeviceId: String
        let batchTimestamp: Date
        let version: String
        let sortedChronologically: Bool
        
        init(
            histories: [EditHistoryDTO],
            sourceDeviceId: String,
            batchTimestamp: Date = Date(),
            version: String = "1.1",
            sortedChronologically: Bool = true
        ) {
            self.histories = histories
            self.sourceDeviceId = sourceDeviceId
            self.batchTimestamp = batchTimestamp
            self.version = version
            self.sortedChronologically = sortedChronologically
        }
    }
    
    /// Container for a batch of family devices
    struct FamilyDeviceBatch: Codable {
        let devices: [FamilyDeviceDTO]
        let sourceDeviceId: String
        let batchTimestamp: Date
    }
    
    // MARK: - Serialization/Deserialization Methods
    
    /// Serializes a message to JSON data
    /// - Parameter message: The message to serialize
    /// - Returns: JSON data or nil if serialization fails
    static func serialize<T: Encodable>(_ message: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            return try encoder.encode(message)
        } catch {
            print("Error serializing message: \(error)")
            return nil
        }
    }
    
    /// Deserializes JSON data to a message
    /// - Parameters:
    ///   - data: The JSON data to deserialize
    ///   - type: The type to deserialize to
    /// - Returns: The deserialized message or nil if deserialization fails
    static func deserialize<T: Decodable>(_ data: Data, to type: T.Type) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode(type, from: data)
        } catch {
            print("Error deserializing data: \(error)")
            return nil
        }
    }
    
    /// Splits data into chunks for transmission
    /// - Parameters:
    ///   - data: The data to split
    ///   - deviceId: The source device ID
    ///   - entityType: The type of entity being transferred
    /// - Returns: Array of DataChunkMessages
    static func splitDataIntoChunks(_ data: Data, deviceId: String, entityType: EntityType) -> [DataChunkMessage] {
        var chunks = [DataChunkMessage]()
        var offset = 0
        
        let totalChunks = Int(ceil(Double(data.count) / Double(maxPayloadSize)))
        
        var chunkIndex = 0
        while offset < data.count {
            let chunkSize = min(maxPayloadSize, data.count - offset)
            let chunkData = data.subdata(in: offset..<(offset + chunkSize))
            
            let chunk = DataChunkMessage(
                deviceId: deviceId,
                chunkIndex: chunkIndex,
                totalChunks: totalChunks,
                entityType: entityType,
                payload: chunkData,
                compressed: true
            )
            
            chunks.append(chunk)
            offset += chunkSize
            chunkIndex += 1
        }
        
        return chunks
    }
    
    /// Reassembles data chunks back into complete data
    /// - Parameter chunks: Array of DataChunkMessages in order
    /// - Returns: The reassembled data or nil if reassembly fails
    static func reassembleChunks(_ chunks: [DataChunkMessage]) -> Data? {
        // Verify we have all chunks
        guard !chunks.isEmpty, 
              chunks.count == chunks[0].totalChunks,
              chunks.map({ $0.chunkIndex }).sorted() == Array(0..<chunks.count) else {
            print("Invalid chunks for reassembly")
            return nil
        }
        
        // Sort chunks by index to ensure correct order
        let sortedChunks = chunks.sorted { $0.chunkIndex < $1.chunkIndex }
        
        // Create a new data object to hold the reassembled data
        var reassembledData = Data()
        
        // Decompress and add each chunk
        for chunk in sortedChunks {
            // Verify checksum first
            let calculatedChecksum = calculateChecksum(for: chunk.payload)
            guard calculatedChecksum == chunk.checksum else {
                print("Checksum mismatch for chunk \(chunk.chunkIndex)")
                return nil
            }
            
            // Add payload (decompress if needed)
            if chunk.compressed {
                if let decompressedData = decompressData(chunk.payload) {
                    reassembledData.append(decompressedData)
                } else {
                    print("Failed to decompress chunk \(chunk.chunkIndex)")
                    return nil
                }
            } else {
                reassembledData.append(chunk.payload)
            }
        }
        
        return reassembledData
    }
    
    // MARK: - Validation Methods
    
    /// Validates the protocol version of a message
    /// - Parameter version: The protocol version to validate
    /// - Returns: True if the version is compatible
    static func validateProtocolVersion(_ version: String) -> Bool {
        // For now, just check if the major version matches
        let currentMajor = protocolVersion.split(separator: ".").first ?? ""
        let versionMajor = version.split(separator: ".").first ?? ""
        
        return currentMajor == versionMajor
    }
    
    /// Calculates a checksum for data validation
    /// - Parameter data: The data to calculate a checksum for
    /// - Returns: Base64-encoded SHA-256 hash of the data
    static func calculateChecksum(for data: Data) -> String {
        // Use Crypto library for SHA-256 hash
        var hashData = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        
        _ = hashData.withUnsafeMutableBytes { hashBytes in
            data.withUnsafeBytes { dataBytes in
                CC_SHA256(dataBytes.baseAddress, CC_LONG(data.count), hashBytes.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        
        return hashData.base64EncodedString()
    }
    
    // MARK: - Compression Methods
    
    /// Compresses data using zlib
    /// - Parameter data: The data to compress
    /// - Returns: Compressed data
    static func compressData(_ data: Data) -> Data {
        // Simplified implementation - in a real app, use a proper compression algorithm
        // For now, we'll just return the original data
        return data
    }
    
    /// Decompresses data using zlib
    /// - Parameter data: The compressed data
    /// - Returns: Decompressed data or nil if decompression fails
    static func decompressData(_ data: Data) -> Data? {
        // Simplified implementation - in a real app, use a proper decompression algorithm
        // For now, we'll just return the original data
        return data
    }
    
    // MARK: - Core Data Serialization
    
    /// Serializes events from Core Data to transfer format
    /// - Parameters:
    ///   - context: The managed object context
    ///   - deviceId: The source device ID
    ///   - lastSyncTime: The last sync time (for incremental sync)
    /// - Returns: Serialized data for transfer
    static func serializeEvents(context: NSManagedObjectContext, deviceId: String, lastSyncTime: Date? = nil) -> Data? {
        let eventRepository = EventRepository(context: context)
        
        // Create fetch predicate based on sync mode
        var predicate: NSPredicate?
        if let lastSync = lastSyncTime {
            // Incremental sync - only get events modified since last sync
            predicate = NSPredicate(format: "lastModifiedAt > %@", lastSync as NSDate)
        }
        
        // Fetch events
        let events = eventRepository.fetch(predicate: predicate, sortDescriptors: nil)
        
        // Convert to DTOs
        let eventDTOs = events.map { EventDTO.from(event: $0) }
        
        // Create batch
        let batch = EventBatch(
            events: eventDTOs,
            sourceDeviceId: deviceId,
            batchTimestamp: Date()
        )
        
        // Serialize
        return serialize(batch)
    }
    
    /// Deserializes and imports events to Core Data
    /// - Parameters:
    ///   - data: The serialized event data
    ///   - context: The managed object context
    ///   - completion: Completion handler with result
    static func deserializeAndImportEvents(data: Data, context: NSManagedObjectContext, completion: @escaping (Result<Int, Error>) -> Void) {
        // Deserialize
        guard let batch: EventBatch = deserialize(data, to: EventBatch.self) else {
            completion(.failure(NSError(domain: "DataExchangeProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to deserialize event batch"])))
            return
        }
        
        // Import events
        var importedCount = 0
        let transactionCoordinator = TransactionCoordinator(context: context)
        
        transactionCoordinator.performAsyncTransaction({
            for eventDTO in batch.events {
                let _ = eventDTO.toEntity(context: context)
                importedCount += 1
            }
        }) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(importedCount))
            }
        }
    }
    
    /// Serializes edit history from Core Data to transfer format
    /// - Parameters:
    ///   - context: The managed object context
    ///   - deviceId: The source device ID
    ///   - lastSyncTime: The last sync time (for incremental sync)
    /// - Returns: Serialized data for transfer
    static func serializeEditHistory(context: NSManagedObjectContext, deviceId: String, lastSyncTime: Date? = nil) -> Data? {
        let historyRepository = EditHistoryRepository(context: context)
        
        // Create fetch predicate based on sync mode
        var predicate: NSPredicate?
        if let lastSync = lastSyncTime {
            // Incremental sync - only get history entries created since last sync
            predicate = NSPredicate(format: "timestamp > %@", lastSync as NSDate)
        }
        
        // Fetch history entries with timestamp sorting for chronological order
        let sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        let histories = historyRepository.fetch(predicate: predicate, sortDescriptors: sortDescriptors)
        
        // Convert to DTOs (filtering out any with missing events)
        let historyDTOs = histories.compactMap { EditHistoryDTO.from(history: $0) }
        
        // Create batch with enhanced version information
        let batch = EditHistoryBatch(
            histories: historyDTOs,
            sourceDeviceId: deviceId,
            batchTimestamp: Date(),
            version: "1.1",  // Enhanced version with support for chronological merging
            sortedChronologically: true
        )
        
        // Serialize
        return serialize(batch)
    }
    
    /// Deserializes and imports edit history to Core Data
    /// - Parameters:
    ///   - data: The serialized history data
    ///   - context: The managed object context
    ///   - completion: Completion handler with result
    static func deserializeAndImportEditHistory(data: Data, context: NSManagedObjectContext, completion: @escaping (Result<Int, Error>) -> Void) {
        // Deserialize
        guard let batch: EditHistoryBatch = deserialize(data, to: EditHistoryBatch.self) else {
            completion(.failure(NSError(domain: "DataExchangeProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to deserialize edit history batch"])))
            return
        }
        
        // Check for enhanced version support
        let isEnhancedVersion = batch.version == "1.1"
        
        if isEnhancedVersion {
            // Use the enhanced SyncHistoryMerger for chronological merging
            let mergeResult = SyncHistoryMerger.shared.mergeEditHistories(remoteHistories: batch.histories, context: context)
            
            completion(.success(mergeResult.added))
            return
        }
        
        // Legacy import for backward compatibility
        var importedCount = 0
        let transactionCoordinator = TransactionCoordinator(context: context)
        
        transactionCoordinator.performAsyncTransaction({
            for historyDTO in batch.histories {
                if historyDTO.toEntity(context: context) != nil {
                    importedCount += 1
                }
            }
        }) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(importedCount))
            }
        }
    }
    
    /// Serializes family devices from Core Data to transfer format
    /// - Parameters:
    ///   - context: The managed object context
    ///   - deviceId: The source device ID
    /// - Returns: Serialized data for transfer
    static func serializeFamilyDevices(context: NSManagedObjectContext, deviceId: String) -> Data? {
        let deviceRepository = FamilyDeviceRepository(context: context)
        
        // Fetch all family devices
        let devices = deviceRepository.fetch(predicate: nil, sortDescriptors: nil)
        
        // Convert to DTOs
        let deviceDTOs = devices.map { FamilyDeviceDTO.from(device: $0) }
        
        // Create batch
        let batch = FamilyDeviceBatch(
            devices: deviceDTOs,
            sourceDeviceId: deviceId,
            batchTimestamp: Date()
        )
        
        // Serialize
        return serialize(batch)
    }
    
    /// Deserializes and imports family devices to Core Data
    /// - Parameters:
    ///   - data: The serialized device data
    ///   - context: The managed object context
    ///   - completion: Completion handler with result
    static func deserializeAndImportFamilyDevices(data: Data, context: NSManagedObjectContext, completion: @escaping (Result<Int, Error>) -> Void) {
        // Deserialize
        guard let batch: FamilyDeviceBatch = deserialize(data, to: FamilyDeviceBatch.self) else {
            completion(.failure(NSError(domain: "DataExchangeProtocol", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to deserialize family device batch"])))
            return
        }
        
        // Import devices
        var importedCount = 0
        let transactionCoordinator = TransactionCoordinator(context: context)
        
        transactionCoordinator.performAsyncTransaction({
            for deviceDTO in batch.devices {
                let _ = deviceDTO.toEntity(context: context)
                importedCount += 1
            }
        }) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(importedCount))
            }
        }
    }
}

// MARK: - Import for SHA-256 hash calculation
import CommonCrypto