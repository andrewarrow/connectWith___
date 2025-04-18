import Foundation
import CoreData
import Combine
import OSLog

/// ConflictResolutionEngine handles detection and resolution of sync conflicts
/// using a three-way merge algorithm that preserves all family members' edits
class ConflictResolutionEngine {
    // MARK: - Singleton
    
    /// Shared instance
    static let shared = ConflictResolutionEngine()
    
    // MARK: - Types
    
    /// Represents the result of a conflict resolution
    struct ResolutionResult {
        let entityType: String
        let entityId: String
        let wasConflict: Bool
        let resolution: ResolutionType
        let fieldsResolved: [String]
        let preservedValues: Bool
    }
    
    /// Types of conflict resolution strategies
    enum ResolutionType: String {
        case noConflict = "no_conflict"        // No conflict detected
        case autoResolved = "auto_resolved"    // Conflict automatically resolved
        case mergeResolved = "merge_resolved"  // Conflict resolved by merging values
        case timeResolved = "time_resolved"    // Conflict resolved using timestamps
        case manualResolved = "manual_resolved" // Conflict resolved manually by user
    }
    
    /// Field types that require different conflict resolution strategies
    enum FieldType {
        case text      // Text fields (title, name, description)
        case number    // Numeric fields (day, count, index)
        case date      // Date fields (timestamp, date)
        case boolean   // Boolean fields (isComplete, isLocal)
        case reference // Reference fields (relationshipId)
    }
    
    /// Defines a field's conflict resolution policy
    struct FieldPolicy {
        let fieldName: String
        let fieldType: FieldType
        let isRequired: Bool
        let mergeStrategy: MergeStrategy
        
        init(fieldName: String, fieldType: FieldType, isRequired: Bool = false, mergeStrategy: MergeStrategy = .latest) {
            self.fieldName = fieldName
            self.fieldType = fieldType
            self.isRequired = isRequired
            self.mergeStrategy = mergeStrategy
        }
    }
    
    /// Strategies for merging conflicting fields
    enum MergeStrategy {
        case latest        // Use the latest value based on timestamp
        case combine       // Combine both values (for text)
        case largest       // Use the largest value (for numbers)
        case earliest      // Use the earliest date
        case latest        // Use the latest date
        case logical       // Apply logical operator (OR for booleans)
        case preserveBoth  // Preserve both values with attribution
    }
    
    // MARK: - Constants
    
    // These policies define how conflicts should be resolved for each entity field
    private let eventFieldPolicies: [FieldPolicy] = [
        FieldPolicy(fieldName: "title", fieldType: .text, isRequired: true, mergeStrategy: .preserveBoth),
        FieldPolicy(fieldName: "location", fieldType: .text, mergeStrategy: .preserveBoth),
        FieldPolicy(fieldName: "day", fieldType: .number, isRequired: true, mergeStrategy: .latest),
        FieldPolicy(fieldName: "month", fieldType: .number, isRequired: true, mergeStrategy: .latest),
        FieldPolicy(fieldName: "lastModifiedAt", fieldType: .date, isRequired: true, mergeStrategy: .latest),
        FieldPolicy(fieldName: "lastModifiedBy", fieldType: .text, isRequired: true, mergeStrategy: .latest),
        FieldPolicy(fieldName: "color", fieldType: .text, mergeStrategy: .latest)
    ]
    
    // Logger for conflict resolution
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConflictResolution")
    
    // MARK: - Private Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Detects and resolves conflicts between local and remote event data
    /// - Parameters:
    ///   - baseEvent: The common ancestor version (last synced state)
    ///   - localEvent: The local version with local changes
    ///   - remoteEvent: The remote version with remote changes
    ///   - context: The managed object context
    /// - Returns: A conflict resolution result
    func resolveEventConflict(baseEvent: EventDTO?, localEvent: EventDTO, remoteEvent: EventDTO, context: NSManagedObjectContext) -> ResolutionResult {
        // Tracking for resolution result
        var wasConflict = false
        var resolvedFields: [String] = []
        var preservedValues = false
        var resolutionType: ResolutionType = .noConflict
        
        // If no base event (new event), use either local or remote as base
        let base = baseEvent ?? localEvent
        
        // Create a dictionary to track field resolutions
        var resolvedEvent: [String: Any] = [
            "id": localEvent.id,
            "createdAt": localEvent.createdAt
        ]
        
        // Track if we have created history entries
        var hasCreatedHistory = false
        
        // Check each field for conflicts
        for policy in eventFieldPolicies {
            let fieldName = policy.fieldName
            
            // Skip id and createdAt as they're already handled
            if fieldName == "id" || fieldName == "createdAt" {
                continue
            }
            
            // Get field values using reflection (simplified for this example)
            let baseValue = getValue(for: fieldName, from: base)
            let localValue = getValue(for: fieldName, from: localEvent)
            let remoteValue = getValue(for: fieldName, from: remoteEvent)
            
            // Detect conflict: both local and remote differ from base
            let localChanged = !isEqual(baseValue, localValue)
            let remoteChanged = !isEqual(baseValue, remoteValue)
            
            if localChanged && remoteChanged && !isEqual(localValue, remoteValue) {
                // We have a conflict to resolve
                wasConflict = true
                resolvedFields.append(fieldName)
                
                // Apply appropriate merge strategy based on field policy
                let resolution = resolveFieldConflict(
                    fieldName: fieldName,
                    fieldType: policy.fieldType,
                    baseValue: baseValue,
                    localValue: localValue,
                    remoteValue: remoteValue,
                    strategy: policy.mergeStrategy,
                    localTime: localEvent.lastModifiedAt,
                    remoteTime: remoteEvent.lastModifiedAt
                )
                
                resolvedEvent[fieldName] = resolution.value
                
                // Create edit history entry for this resolution
                if !hasCreatedHistory {
                    createConflictHistoryEntry(
                        eventId: localEvent.id,
                        localValue: localValue,
                        remoteValue: remoteValue,
                        resolvedValue: resolution.value,
                        fieldName: fieldName,
                        localDeviceId: localEvent.lastModifiedBy,
                        remoteDeviceId: remoteEvent.lastModifiedBy,
                        context: context
                    )
                    hasCreatedHistory = true
                }
                
                // Check if we preserved values (important for reporting)
                if resolution.preservedBoth {
                    preservedValues = true
                    resolutionType = .mergeResolved
                } else {
                    resolutionType = .timeResolved
                }
                
                logger.info("Resolved conflict for event \(localEvent.id) field '\(fieldName)': local=\(String(describing: localValue)), remote=\(String(describing: remoteValue)), resolved=\(String(describing: resolution.value))")
            } else if remoteChanged {
                // Remote changed, local didn't - take remote value
                resolvedEvent[fieldName] = remoteValue
            } else {
                // Either local changed or neither changed - keep local value
                resolvedEvent[fieldName] = localValue
            }
        }
        
        // Update the entity in the database with resolved values
        if wasConflict {
            updateEventWithResolvedValues(id: localEvent.id, values: resolvedEvent, context: context)
        }
        
        return ResolutionResult(
            entityType: "Event",
            entityId: localEvent.id.uuidString,
            wasConflict: wasConflict,
            resolution: resolutionType,
            fieldsResolved: resolvedFields,
            preservedValues: preservedValues
        )
    }
    
    /// Batch resolves conflicts for multiple events
    /// - Parameters:
    ///   - conflicts: Array of tuples containing base, local, and remote versions
    ///   - context: The managed object context
    /// - Returns: Array of resolution results
    func batchResolveEventConflicts(conflicts: [(base: EventDTO?, local: EventDTO, remote: EventDTO)], context: NSManagedObjectContext) -> [ResolutionResult] {
        return conflicts.map { conflict in
            resolveEventConflict(
                baseEvent: conflict.base,
                localEvent: conflict.local,
                remoteEvent: conflict.remote,
                context: context
            )
        }
    }
    
    // MARK: - Private Methods
    
    /// Resolves a conflict for a specific field using the appropriate merge strategy
    /// - Parameters:
    ///   - fieldName: Name of the field being resolved
    ///   - fieldType: Type of the field (text, number, date, etc.)
    ///   - baseValue: Original value from base version
    ///   - localValue: Value from local version
    ///   - remoteValue: Value from remote version
    ///   - strategy: Strategy to use for resolution
    ///   - localTime: Timestamp of local modification
    ///   - remoteTime: Timestamp of remote modification
    /// - Returns: The resolved value and whether both values were preserved
    private func resolveFieldConflict(
        fieldName: String,
        fieldType: FieldType,
        baseValue: Any?,
        localValue: Any?,
        remoteValue: Any?,
        strategy: MergeStrategy,
        localTime: Date,
        remoteTime: Date
    ) -> (value: Any?, preservedBoth: Bool) {
        
        switch strategy {
        case .preserveBoth:
            return resolveWithPreservation(fieldName: fieldName, fieldType: fieldType, localValue: localValue, remoteValue: remoteValue)
            
        case .latest:
            if localTime > remoteTime {
                return (localValue, false)
            } else {
                return (remoteValue, false)
            }
            
        case .combine:
            return resolveByCombining(fieldType: fieldType, localValue: localValue, remoteValue: remoteValue)
            
        case .largest:
            return resolveByLargest(fieldType: fieldType, localValue: localValue, remoteValue: remoteValue)
            
        case .earliest:
            if let localDate = localValue as? Date, let remoteDate = remoteValue as? Date {
                return (localDate < remoteDate ? localValue : remoteValue, false)
            }
            return (localTime < remoteTime ? localValue : remoteValue, false)
            
        case .logical:
            if let localBool = localValue as? Bool, let remoteBool = remoteValue as? Bool {
                return (localBool || remoteBool, false) // OR operation
            }
            return (localValue, false)
        }
    }
    
    /// Preserves both values with clear attribution
    private func resolveWithPreservation(fieldName: String, fieldType: FieldType, localValue: Any?, remoteValue: Any?) -> (value: Any?, preservedBoth: Bool) {
        // For text fields, we can combine the values with attribution
        if fieldType == .text {
            let localStr = localValue as? String ?? ""
            let remoteStr = remoteValue as? String ?? ""
            
            // If they're the same, just return one
            if localStr == remoteStr {
                return (localStr, false)
            }
            
            // If one is empty, return the other
            if localStr.isEmpty {
                return (remoteStr, false)
            }
            if remoteStr.isEmpty {
                return (localStr, false)
            }
            
            // Combine with attribution
            let combinedStr = "\(localStr) [\(fieldName) also changed to: \(remoteStr)]"
            return (combinedStr, true)
        }
        
        // For other field types, we default to the latest value but record history
        return (localValue, true)
    }
    
    /// Combines text values or uses logical operations for other types
    private func resolveByCombining(fieldType: FieldType, localValue: Any?, remoteValue: Any?) -> (value: Any?, preservedBoth: Bool) {
        if fieldType == .text {
            let localStr = localValue as? String ?? ""
            let remoteStr = remoteValue as? String ?? ""
            
            // If they're the same, just return one
            if localStr == remoteStr {
                return (localStr, false)
            }
            
            // If one is empty, return the other
            if localStr.isEmpty {
                return (remoteStr, false)
            }
            if remoteStr.isEmpty {
                return (localStr, false)
            }
            
            // Combine strings
            return ("\(localStr) \(remoteStr)", true)
        }
        
        // Default to local value for non-text fields
        return (localValue, false)
    }
    
    /// Uses the larger of the two values for numeric fields
    private func resolveByLargest(fieldType: FieldType, localValue: Any?, remoteValue: Any?) -> (value: Any?, preservedBoth: Bool) {
        if fieldType == .number {
            if let localNum = localValue as? Int, let remoteNum = remoteValue as? Int {
                return (max(localNum, remoteNum), false)
            } else if let localNum = localValue as? Double, let remoteNum = remoteValue as? Double {
                return (max(localNum, remoteNum), false)
            } else if let localNum = localValue as? Int16, let remoteNum = remoteValue as? Int16 {
                return (max(localNum, remoteNum), false)
            } else if let localNum = localValue as? Int32, let remoteNum = remoteValue as? Int32 {
                return (max(localNum, remoteNum), false)
            } else if let localNum = localValue as? Int64, let remoteNum = remoteValue as? Int64 {
                return (max(localNum, remoteNum), false)
            }
        }
        
        // Default to local value for non-numeric fields
        return (localValue, false)
    }
    
    /// Creates a history entry for a resolved conflict
    private func createConflictHistoryEntry(
        eventId: UUID,
        localValue: Any?,
        remoteValue: Any?,
        resolvedValue: Any?,
        fieldName: String,
        localDeviceId: String,
        remoteDeviceId: String,
        context: NSManagedObjectContext
    ) {
        // Find the event this history applies to
        let eventFetchRequest = Event.fetchRequest()
        eventFetchRequest.predicate = NSPredicate(format: "id == %@", eventId as CVarArg)
        
        do {
            let events = try context.fetch(eventFetchRequest)
            guard let event = events.first else {
                logger.error("Could not find event with ID \(eventId) to create conflict history")
                return
            }
            
            // Create a history entry
            let history = EditHistory(context: context)
            history.id = UUID()
            history.deviceId = localDeviceId
            history.deviceName = "Conflict Resolution"
            history.timestamp = Date()
            history.event = event
            
            // Record the appropriate field values based on field name
            switch fieldName {
            case "title":
                history.previousTitle = "\(localValue as? String ?? "") / \(remoteValue as? String ?? "")"
                history.newTitle = resolvedValue as? String
            case "location":
                history.previousLocation = "\(localValue as? String ?? "") / \(remoteValue as? String ?? "")"
                history.newLocation = resolvedValue as? String
            case "day":
                if let localDay = localValue as? Int16, let remoteDay = remoteValue as? Int16 {
                    // Record both local and remote days in a special format
                    history.previousDay = localDay
                    history.newDay = remoteDay
                }
            default:
                // For other fields, we can't directly store in EditHistory
                // We could extend EditHistory with additional fields or use a generic mechanism
                logger.info("Conflict resolution for field \(fieldName) recorded in history")
            }
            
            try context.save()
            logger.info("Created conflict resolution history for event \(eventId)")
            
        } catch {
            logger.error("Error creating conflict history: \(error.localizedDescription)")
        }
    }
    
    /// Updates an event entity with resolved values
    private func updateEventWithResolvedValues(id: UUID, values: [String: Any], context: NSManagedObjectContext) {
        let fetchRequest = Event.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let results = try context.fetch(fetchRequest)
            guard let event = results.first else {
                logger.error("Could not find event with ID \(id) to update with resolved values")
                return
            }
            
            // Update the event with resolved values
            if let title = values["title"] as? String {
                event.title = title
            }
            
            if let location = values["location"] as? String {
                event.location = location
            }
            
            if let day = values["day"] as? Int16 {
                event.day = day
            } else if let day = values["day"] as? Int {
                event.day = Int16(day)
            }
            
            if let month = values["month"] as? Int16 {
                event.month = month
            } else if let month = values["month"] as? Int {
                event.month = Int16(month)
            }
            
            if let color = values["color"] as? String {
                event.color = color
            }
            
            // Set modified metadata
            event.lastModifiedAt = Date()
            event.lastModifiedBy = "conflict_resolution"
            
            try context.save()
            logger.info("Updated event \(id) with resolved conflict values")
            
        } catch {
            logger.error("Error updating event with resolved values: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Utility Methods
    
    /// Gets a value for a field from an entity using reflection
    private func getValue(for field: String, from entity: Any) -> Any? {
        let mirror = Mirror(reflecting: entity)
        
        for child in mirror.children {
            if child.label == field {
                return child.value
            }
        }
        
        return nil
    }
    
    /// Compares two values for equality
    private func isEqual(_ value1: Any?, _ value2: Any?) -> Bool {
        // Handle nil cases
        if value1 == nil && value2 == nil {
            return true
        }
        if value1 == nil || value2 == nil {
            return false
        }
        
        // Compare based on type
        if let str1 = value1 as? String, let str2 = value2 as? String {
            return str1 == str2
        } else if let num1 = value1 as? Int, let num2 = value2 as? Int {
            return num1 == num2
        } else if let num1 = value1 as? Int16, let num2 = value2 as? Int16 {
            return num1 == num2
        } else if let num1 = value1 as? Int32, let num2 = value2 as? Int32 {
            return num1 == num2
        } else if let num1 = value1 as? Double, let num2 = value2 as? Double {
            return num1 == num2
        } else if let bool1 = value1 as? Bool, let bool2 = value2 as? Bool {
            return bool1 == bool2
        } else if let date1 = value1 as? Date, let date2 = value2 as? Date {
            return date1 == date2
        }
        
        // Default to not equal for unsupported types
        return false
    }
}

// MARK: - ConflictDetector

/// Detects conflicts between local and remote versions of entities
class ConflictDetector {
    /// Detects conflicts between sets of local and remote events
    /// - Parameters:
    ///   - localEvents: Array of local events
    ///   - remoteEvents: Array of remote events
    ///   - baseEvents: Optional array of base/common ancestor events
    /// - Returns: Array of conflicts with base, local, and remote versions
    static func detectEventConflicts(
        localEvents: [EventDTO], 
        remoteEvents: [EventDTO], 
        baseEvents: [EventDTO]? = nil
    ) -> [(base: EventDTO?, local: EventDTO, remote: EventDTO)] {
        var conflicts: [(base: EventDTO?, local: EventDTO, remote: EventDTO)] = []
        
        // Create dictionaries for easier lookup
        let localEventsDict = Dictionary(uniqueKeysWithValues: localEvents.map { ($0.id, $0) })
        let remoteEventsDict = Dictionary(uniqueKeysWithValues: remoteEvents.map { ($0.id, $0) })
        let baseEventsDict = baseEvents?.reduce(into: [UUID: EventDTO]()) { dict, event in
            dict[event.id] = event
        } ?? [:]
        
        // Check for events that exist in both local and remote
        for (id, localEvent) in localEventsDict {
            if let remoteEvent = remoteEventsDict[id] {
                // Get base version if available
                let baseEvent = baseEventsDict[id]
                
                // Check if there's a potential conflict
                if hasConflict(base: baseEvent, local: localEvent, remote: remoteEvent) {
                    conflicts.append((base: baseEvent, local: localEvent, remote: remoteEvent))
                }
            }
        }
        
        return conflicts
    }
    
    /// Determines if there's a conflict between versions
    private static func hasConflict(base: EventDTO?, local: EventDTO, remote: EventDTO) -> Bool {
        // If no base, assume there could be a conflict
        guard let base = base else {
            return true
        }
        
        // Check if both local and remote have changes from base for any field
        let localModified = local.lastModifiedAt > base.lastModifiedAt
        let remoteModified = remote.lastModifiedAt > base.lastModifiedAt
        
        // Only consider a conflict if both versions have been modified
        return localModified && remoteModified
    }
}