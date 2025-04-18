import Foundation
import CoreData
import Combine
import OSLog

/// SyncHistoryMerger handles chronological merging of edit histories
/// across devices to maintain a consistent view of all changes.
class SyncHistoryMerger {
    // Singleton instance
    static let shared = SyncHistoryMerger()
    
    // Private initializer for singleton
    private init() {}
    
    // Logger
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SyncHistoryMerger")
    
    /// Merges a list of remote edit histories with local histories
    /// - Parameters:
    ///   - remoteHistories: Array of edit histories from a remote device
    ///   - context: The managed object context
    /// - Returns: Number of histories processed and resulting newly added histories
    func mergeEditHistories(remoteHistories: [EditHistoryDTO], context: NSManagedObjectContext) -> (processed: Int, added: Int) {
        var processed = 0
        var added = 0
        
        // Fetch existing local histories
        let fetchRequest = EditHistory.fetchRequest()
        
        do {
            let localHistories = try context.fetch(fetchRequest)
            
            // Create dictionary of existing history entries by unique identifier (for fast lookup)
            let existingHistoryMap = Dictionary(uniqueKeysWithValues: localHistories.map { 
                // Create a unique key combining ID and deviceID to ensure uniqueness
                (self.createUniqueKey(id: $0.id!, deviceId: $0.deviceId!), $0)
            })
            
            // Create a new array for all histories to be sorted
            var allHistoriesDTO = remoteHistories
            
            // Convert local histories to DTOs to merge with remote
            let localHistoriesDTO = localHistories.map { EditHistoryDTO.from(editHistory: $0) }
            allHistoriesDTO.append(contentsOf: localHistoriesDTO)
            
            // Sort all histories chronologically
            let sortedHistories = sortHistoriesChronologically(histories: allHistoriesDTO)
            
            // Process each history in chronological order
            for historyDTO in sortedHistories {
                processed += 1
                
                let uniqueKey = createUniqueKey(id: historyDTO.id, deviceId: historyDTO.deviceId)
                
                // Skip if this history already exists locally
                if existingHistoryMap[uniqueKey] != nil {
                    continue
                }
                
                // Create new history entry
                let newHistory = EditHistory(context: context)
                newHistory.id = historyDTO.id
                newHistory.deviceId = historyDTO.deviceId
                newHistory.deviceName = historyDTO.deviceName
                newHistory.timestamp = historyDTO.timestamp
                
                // Set event relationship
                if let eventId = historyDTO.eventId {
                    let eventFetchRequest = Event.fetchRequest()
                    eventFetchRequest.predicate = NSPredicate(format: "id == %@", eventId as CVarArg)
                    
                    if let events = try? context.fetch(eventFetchRequest), let event = events.first {
                        newHistory.event = event
                    } else {
                        logger.warning("Could not find event with ID \(eventId) for history \(historyDTO.id)")
                    }
                }
                
                // Set specific fields
                newHistory.previousTitle = historyDTO.previousTitle
                newHistory.newTitle = historyDTO.newTitle
                newHistory.previousLocation = historyDTO.previousLocation
                newHistory.newLocation = historyDTO.newLocation
                
                if let previousDay = historyDTO.previousDay {
                    newHistory.previousDay = Int16(previousDay)
                }
                
                if let newDay = historyDTO.newDay {
                    newHistory.newDay = Int16(newDay)
                }
                
                added += 1
                logger.info("Added new history entry from device \(historyDTO.deviceId): \(historyDTO.id)")
            }
            
            // Save the context if we added anything
            if added > 0 {
                try context.save()
                logger.info("Successfully merged \(added) new history entries out of \(processed) processed")
            }
            
        } catch {
            logger.error("Error merging edit histories: \(error.localizedDescription)")
        }
        
        return (processed, added)
    }
    
    /// Sorts edit histories chronologically with special handling for simultaneous edits
    /// - Parameter histories: Array of edit histories to sort
    /// - Returns: Array of histories sorted by timestamp, then by device ID for identical timestamps
    private func sortHistoriesChronologically(histories: [EditHistoryDTO]) -> [EditHistoryDTO] {
        return histories.sorted { first, second in
            // First sort by timestamp
            if first.timestamp != second.timestamp {
                return first.timestamp < second.timestamp
            }
            
            // For identical timestamps, sort by device ID to ensure consistency
            return first.deviceId < second.deviceId
        }
    }
    
    /// Analyzes edit histories to maintain causal relationships
    /// - Parameters:
    ///   - eventId: The event ID to analyze histories for
    ///   - context: The managed object context
    /// - Returns: A reconstructed chain of edits in causal order
    func analyzeCausalRelationships(eventId: UUID, context: NSManagedObjectContext) -> [EditHistory] {
        // Fetch all edit histories for this event
        let fetchRequest = EditHistory.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "event.id == %@", eventId as CVarArg)
        
        // Sort by timestamp
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        
        var result: [EditHistory] = []
        
        do {
            let histories = try context.fetch(fetchRequest)
            
            // Group histories by device
            let historiesByDevice = Dictionary(grouping: histories) { $0.deviceId ?? "unknown" }
            
            // Track all processed histories to avoid duplication
            var processedHistoryIds = Set<UUID>()
            
            // Create a dependency graph based on field values
            var dependencyGraph: [UUID: Set<UUID>] = [:]
            
            // Build dependency graph
            for history in histories {
                guard let id = history.id else { continue }
                
                // Find potential dependencies (earlier histories that this one depends on)
                let potentialDependencies = histories.filter { earlierHistory -> Bool in
                    guard let earlierId = earlierHistory.id,
                          let earlierTimestamp = earlierHistory.timestamp,
                          let currentTimestamp = history.timestamp else {
                        return false
                    }
                    
                    // Only consider earlier histories
                    return earlierTimestamp < currentTimestamp && id != earlierId
                }
                
                // Track dependencies
                dependencyGraph[id] = Set(potentialDependencies.compactMap { $0.id })
            }
            
            // Perform topological sort to maintain causal relationships
            var temporarilyMarked = Set<UUID>()
            var permanentlyMarked = Set<UUID>()
            var sorted: [UUID] = []
            
            // Start with histories that have no dependencies
            for history in histories {
                guard let id = history.id else { continue }
                if !permanentlyMarked.contains(id) {
                    visit(id: id, 
                          dependencyGraph: dependencyGraph,
                          temporarilyMarked: &temporarilyMarked,
                          permanentlyMarked: &permanentlyMarked,
                          sorted: &sorted)
                }
            }
            
            // Map sorted IDs back to histories
            let historiesById = Dictionary(uniqueKeysWithValues: histories.compactMap { 
                history -> (UUID, EditHistory)? in
                guard let id = history.id else { return nil }
                return (id, history)
            })
            
            // Construct the result in causal order
            result = sorted.reversed().compactMap { historiesById[$0] }
            
        } catch {
            logger.error("Error analyzing causal relationships: \(error.localizedDescription)")
        }
        
        return result
    }
    
    /// Helper for topological sort
    private func visit(id: UUID, 
                       dependencyGraph: [UUID: Set<UUID>],
                       temporarilyMarked: inout Set<UUID>,
                       permanentlyMarked: inout Set<UUID>,
                       sorted: inout [UUID]) {
        
        // Check for cyclic dependencies
        if temporarilyMarked.contains(id) {
            // Handle cycle by breaking it
            logger.warning("Detected cycle in edit history dependencies for \(id)")
            return
        }
        
        // Skip if already processed
        if permanentlyMarked.contains(id) {
            return
        }
        
        temporarilyMarked.insert(id)
        
        // Visit dependencies first
        if let dependencies = dependencyGraph[id] {
            for dependencyId in dependencies {
                visit(id: dependencyId,
                      dependencyGraph: dependencyGraph,
                      temporarilyMarked: &temporarilyMarked,
                      permanentlyMarked: &permanentlyMarked,
                      sorted: &sorted)
            }
        }
        
        temporarilyMarked.remove(id)
        permanentlyMarked.insert(id)
        sorted.append(id)
    }
    
    /// Creates a unique key for an edit history
    private func createUniqueKey(id: UUID, deviceId: String) -> String {
        return "\(id.uuidString)_\(deviceId)"
    }
    
    /// Resolves conflicts between edit histories with identical timestamps
    /// - Parameter histories: Array of histories with identical timestamps
    /// - Returns: Ordered array resolving the conflicts
    func resolveIdenticalTimestamps(histories: [EditHistoryDTO]) -> [EditHistoryDTO] {
        // Group by timestamp
        let historiesByTimestamp = Dictionary(grouping: histories) { $0.timestamp }
        
        var result: [EditHistoryDTO] = []
        
        for (timestamp, historiesAtTimestamp) in historiesByTimestamp {
            if historiesAtTimestamp.count == 1 {
                // Only one edit at this timestamp - no conflict
                result.append(historiesAtTimestamp[0])
            } else {
                // Multiple edits at same timestamp - resolve by:
                // 1. First by deviceId for deterministic ordering
                // 2. Then by field importance if affecting the same fields
                
                let sortedHistories = historiesAtTimestamp.sorted { first, second in
                    // First sort by device ID for deterministic ordering
                    if first.deviceId != second.deviceId {
                        return first.deviceId < second.deviceId
                    }
                    
                    // If same device, sort by ID to ensure consistent ordering
                    return first.id.uuidString < second.id.uuidString
                }
                
                result.append(contentsOf: sortedHistories)
            }
        }
        
        return result.sorted { $0.timestamp < $1.timestamp }
    }
}

/// Extension for EditHistoryDTO to support merging operations
extension EditHistoryDTO {
    /// Creates a DTO from a CoreData EditHistory
    static func from(editHistory: EditHistory) -> EditHistoryDTO {
        return EditHistoryDTO(
            id: editHistory.id ?? UUID(),
            eventId: editHistory.event?.id,
            deviceId: editHistory.deviceId ?? "",
            deviceName: editHistory.deviceName,
            previousTitle: editHistory.previousTitle,
            newTitle: editHistory.newTitle,
            previousLocation: editHistory.previousLocation,
            newLocation: editHistory.newLocation,
            previousDay: editHistory.previousDay != 0 ? Int(editHistory.previousDay) : nil,
            newDay: editHistory.newDay != 0 ? Int(editHistory.newDay) : nil,
            timestamp: editHistory.timestamp ?? Date()
        )
    }
}