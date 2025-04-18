import Foundation
import CoreData
import OSLog
import UserNotifications
import Combine

/// Manages sync history, logging, notifications, and edit history merging for devices
class SyncHistoryManager {
    // Singleton instance
    static let shared = SyncHistoryManager()
    
    // Private initializer for singleton
    private init() {
        // Initialize notification settings
        initializeNotificationSettings()
    }
    
    // MARK: - Properties
    
    /// Published properties for observing sync activity
    @Published var recentSyncActivity: [SyncLog] = []
    @Published var pendingConflicts: [PendingConflictInfo] = []
    @Published var syncHealthMetrics: SyncHealthMetrics = SyncHealthMetrics()
    
    /// Background refresh timer
    private var refreshTimer: Timer?
    
    /// Notification manager for sync notifications
    private let notificationCenter = UNUserNotificationCenter.current()
    
    /// Default notification category identifiers
    private let syncCompletedCategoryId = "SYNC_COMPLETED"
    private let syncConflictCategoryId = "SYNC_CONFLICT"
    private let syncErrorCategoryId = "SYNC_ERROR"
    
    /// Logger for sync history
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.connectwith", category: "SyncHistory")
    
    // MARK: - Types
    
    /// Represents information about a pending conflict
    struct PendingConflictInfo: Identifiable {
        let id: UUID
        let deviceId: String
        let deviceName: String
        let eventId: UUID
        let eventTitle: String
        let conflictDate: Date
        let severity: ConflictDetector.ConflictSeverity
        let affectedFields: [String]
        let requiresManualResolution: Bool
    }
    
    /// Health metrics for sync activity
    struct SyncHealthMetrics {
        var successRate: Double = 1.0  // Success rate of sync operations (0.0-1.0)
        var averageDuration: TimeInterval = 0.0  // Average sync duration in seconds
        var totalConflictsResolved: Int = 0  // Total number of conflicts resolved
        var conflictResolutionRate: Double = 1.0  // Rate of successful conflict resolutions
        var lastSyncAttemptTime: Date?  // Time of last sync attempt
        var lastSuccessfulSyncTime: Date?  // Time of last successful sync
        var totalEventsExchanged: Int = 0  // Total events exchanged
        var deviceSyncCoverage: Double = 0.0  // Percentage of devices synced recently
    }
    
    // MARK: - Initialization and Setup
    
    /// Initialize notification settings
    private func initializeNotificationSettings() {
        // Set up notification categories
        let syncCompletedCategory = UNNotificationCategory(
            identifier: syncCompletedCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        let viewAction = UNNotificationAction(
            identifier: "VIEW_CONFLICT",
            title: "View Details",
            options: .foreground
        )
        
        let resolveAction = UNNotificationAction(
            identifier: "RESOLVE_CONFLICT",
            title: "Resolve Now",
            options: .foreground
        )
        
        let syncConflictCategory = UNNotificationCategory(
            identifier: syncConflictCategoryId,
            actions: [viewAction, resolveAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        let retryAction = UNNotificationAction(
            identifier: "RETRY_SYNC",
            title: "Retry Sync",
            options: .foreground
        )
        
        let syncErrorCategory = UNNotificationCategory(
            identifier: syncErrorCategoryId,
            actions: [retryAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // Register categories
        notificationCenter.setNotificationCategories([
            syncCompletedCategory,
            syncConflictCategory,
            syncErrorCategory
        ])
        
        // Start background refresh
        startBackgroundRefresh()
    }
    
    /// Starts a background refresh timer for sync data
    private func startBackgroundRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refreshSyncData()
        }
    }
    
    /// Refreshes sync data in the background
    private func refreshSyncData() {
        loadRecentSyncActivity()
        loadPendingConflicts()
        calculateSyncHealthMetrics()
    }
    
    // MARK: - Sync History Methods
    
    /// Gets the last sync time for a device
    /// - Parameter bluetoothIdentifier: The device's Bluetooth identifier
    /// - Returns: The last sync time, or nil if the device has never synced
    func getLastSyncTime(bluetoothIdentifier: String) -> Date? {
        var lastSyncTime: Date?
        
        let context = PersistenceController.shared.container.viewContext
        let familyDeviceRepository = FamilyDeviceRepository(context: context)
        
        if let familyDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: bluetoothIdentifier) {
            lastSyncTime = familyDevice.lastSyncTimestamp
        }
        
        return lastSyncTime
    }
    
    /// Gets recent sync logs for a device
    /// - Parameters:
    ///   - bluetoothIdentifier: The device's Bluetooth identifier
    ///   - limit: Maximum number of logs to retrieve
    /// - Returns: Array of sync logs
    func getRecentSyncLogs(bluetoothIdentifier: String, limit: Int = 5) -> [SyncLog] {
        let context = PersistenceController.shared.container.viewContext
        let syncLogRepository = SyncLogRepository(context: context)
        
        let logs = syncLogRepository.fetchLogsByDevice(deviceId: bluetoothIdentifier)
        
        // Return the most recent logs up to the limit
        return Array(logs.prefix(limit))
    }
    
    /// Gets all recent sync logs across all devices
    /// - Parameter limit: Maximum number of logs to retrieve
    /// - Returns: Array of sync logs
    func getAllRecentSyncLogs(limit: Int = 20) -> [SyncLog] {
        let context = PersistenceController.shared.container.viewContext
        let syncLogRepository = SyncLogRepository(context: context)
        
        let logs = syncLogRepository.fetchRecentSyncLogs(limit: limit)
        
        // Return the most recent logs up to the limit
        return logs
    }
    
    /// Creates a new sync log entry
    /// - Parameters:
    ///   - deviceId: The device's Bluetooth identifier
    ///   - deviceName: The device's name
    ///   - eventsReceived: Number of events received during sync
    ///   - eventsSent: Number of events sent during sync
    ///   - conflicts: Number of conflicts detected during sync
    ///   - resolutionMethod: Method used to resolve conflicts (if any)
    ///   - conflictDetails: Detailed information about resolved conflicts
    ///   - syncDuration: Duration of the sync operation in seconds
    ///   - syncSuccess: Whether the sync operation was successful
    ///   - errorMessage: Error message if sync failed
    /// - Returns: The created sync log, or nil if creation failed
    func createSyncLog(
        deviceId: String,
        deviceName: String?,
        eventsReceived: Int,
        eventsSent: Int,
        conflicts: Int = 0,
        resolutionMethod: String? = nil,
        conflictDetails: [String]? = nil,
        syncDuration: TimeInterval = 0,
        syncSuccess: Bool = true,
        errorMessage: String? = nil,
        historiesProcessed: Int = 0,
        historiesAdded: Int = 0
    ) -> SyncLog? {
        var createdLog: SyncLog?
        
        PersistenceController.shared.performBackgroundTask { context in
            let syncLogRepository = SyncLogRepository(context: context)
            
            // Create the sync log
            let log = syncLogRepository.createSyncLog(
                deviceId: deviceId,
                deviceName: deviceName
            )
            
            // Update with sync details
            log.eventsReceived = Int32(eventsReceived)
            log.eventsSent = Int32(eventsSent)
            log.conflicts = Int32(conflicts)
            log.resolutionMethod = resolutionMethod
            
            // Generate summary details
            var detailsText = """
            Synchronized with \(deviceName ?? "Unknown Device")
            Received: \(eventsReceived) events
            Sent: \(eventsSent) events
            Conflicts: \(conflicts)
            Duration: \(String(format: "%.2f", syncDuration)) seconds
            """
            
            // Add history sync details
            if historiesProcessed > 0 {
                detailsText += "\nHistory: \(historiesProcessed) processed, \(historiesAdded) added"
            }
            
            // Add success/failure and error message
            detailsText += "\nStatus: \(syncSuccess ? "Success" : "Failed")"
            if let errorMsg = errorMessage {
                detailsText += "\nError: \(errorMsg)"
            }
            
            // Add conflict resolution details if available
            if conflicts > 0 {
                detailsText += "\nResolution Method: \(resolutionMethod ?? "automatic")"
                
                if let details = conflictDetails, !details.isEmpty {
                    detailsText += "\n\nConflict Details:"
                    for detail in details {
                        detailsText += "\n- \(detail)"
                    }
                }
            }
            
            log.details = detailsText
            
            do {
                try context.save()
                createdLog = log
                
                // Also update the FamilyDevice last sync timestamp
                let familyDeviceRepository = FamilyDeviceRepository(context: context)
                if let familyDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: deviceId) {
                    familyDevice.lastSyncTimestamp = Date()
                    try context.save()
                }
                
                // Log the sync event
                if syncSuccess {
                    self.logger.info("Created sync log for device \(deviceId): \(eventsReceived) received, \(eventsSent) sent, \(conflicts) conflicts")
                } else {
                    self.logger.error("Sync failed with device \(deviceId): \(errorMessage ?? "Unknown error")")
                }
                
                // Send notifications
                if syncSuccess {
                    if conflicts > 0 {
                        // Conflicts require attention
                        self.sendConflictNotification(deviceName: deviceName, conflicts: conflicts, syncLogId: log.id!)
                    } else {
                        // Successful sync without conflicts
                        self.sendSyncCompletedNotification(deviceName: deviceName, events: eventsReceived + eventsSent)
                    }
                } else {
                    // Failed sync
                    self.sendSyncErrorNotification(deviceName: deviceName, error: errorMessage)
                }
                
                // Update observed properties
                DispatchQueue.main.async {
                    self.refreshSyncData()
                }
                
            } catch {
                self.logger.error("Failed to create sync log: \(error.localizedDescription)")
            }
        }
        
        return createdLog
    }
    
    /// Updates an existing sync log with conflict resolution information
    /// - Parameters:
    ///   - syncLogId: The ID of the sync log to update
    ///   - conflicts: Number of conflicts detected
    ///   - resolutionMethod: Method used to resolve conflicts
    ///   - resolvedFields: List of fields that had conflicts resolved
    ///   - preservedValues: Whether values were preserved during resolution
    func updateSyncLogWithConflictInfo(
        syncLogId: UUID,
        conflicts: Int,
        resolutionMethod: String,
        resolvedFields: [String],
        preservedValues: Bool
    ) {
        PersistenceController.shared.performBackgroundTask { context in
            // Fetch the sync log
            let fetchRequest = SyncLog.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", syncLogId as CVarArg)
            
            do {
                let results = try context.fetch(fetchRequest)
                guard let syncLog = results.first else {
                    self.logger.error("Could not find sync log with ID \(syncLogId) to update with conflict info")
                    return
                }
                
                // Update conflict information
                syncLog.conflicts = Int32(conflicts)
                syncLog.resolutionMethod = resolutionMethod
                
                // Add conflict details to the existing details
                var detailsText = syncLog.details ?? ""
                detailsText += "\n\nConflict Resolution Details:"
                detailsText += "\n- \(conflicts) conflicts detected"
                detailsText += "\n- Resolution method: \(resolutionMethod)"
                
                if !resolvedFields.isEmpty {
                    detailsText += "\n- Resolved fields: \(resolvedFields.joined(separator: ", "))"
                }
                
                detailsText += "\n- Data preservation: \(preservedValues ? "All values preserved" : "Latest values used")"
                
                syncLog.details = detailsText
                
                try context.save()
                self.logger.info("Updated sync log \(syncLogId) with conflict resolution information")
                
                // Update observed properties
                DispatchQueue.main.async {
                    self.refreshSyncData()
                }
                
            } catch {
                self.logger.error("Failed to update sync log with conflict info: \(error.localizedDescription)")
            }
        }
    }
    
    /// Gets sync statistics for a device
    /// - Parameter bluetoothIdentifier: The device's Bluetooth identifier
    /// - Returns: Tuple containing total events sent, received, and conflicts
    func getSyncStatistics(bluetoothIdentifier: String) -> (sent: Int, received: Int, conflicts: Int) {
        let context = PersistenceController.shared.container.viewContext
        let syncLogRepository = SyncLogRepository(context: context)
        
        let logs = syncLogRepository.fetchLogsByDevice(deviceId: bluetoothIdentifier)
        
        // Calculate totals
        var totalSent = 0
        var totalReceived = 0
        var totalConflicts = 0
        
        for log in logs {
            totalSent += Int(log.eventsSent)
            totalReceived += Int(log.eventsReceived)
            totalConflicts += Int(log.conflicts)
        }
        
        return (sent: totalSent, received: totalReceived, conflicts: totalConflicts)
    }
    
    /// Cleans up old sync logs
    /// - Parameter olderThan: Remove logs older than this date
    /// - Returns: Number of logs deleted
    func cleanupOldSyncLogs(olderThan: Date) -> Int {
        var deletedCount = 0
        
        PersistenceController.shared.performBackgroundTask { context in
            let syncLogRepository = SyncLogRepository(context: context)
            
            do {
                deletedCount = try syncLogRepository.deleteLogsOlderThan(date: olderThan)
                self.logger.info("Deleted \(deletedCount) old sync logs")
            } catch {
                self.logger.error("Failed to delete old sync logs: \(error.localizedDescription)")
            }
        }
        
        return deletedCount
    }
    
    // MARK: - Edit History Merging
    
    /// Merges remote edit histories with local histories
    /// - Parameters:
    ///   - histories: Array of edit histories from remote device
    ///   - context: Managed object context for persistence operations
    /// - Returns: Number of histories processed and added
    func mergeEditHistories(histories: [EditHistoryDTO], context: NSManagedObjectContext) -> (processed: Int, added: Int) {
        // Delegate to SyncHistoryMerger
        return SyncHistoryMerger.shared.mergeEditHistories(remoteHistories: histories, context: context)
    }
    
    /// Gets edit history for an event in chronological order
    /// - Parameters:
    ///   - eventId: The event ID to get history for
    ///   - withCausalRelationships: Whether to maintain causal relationships
    /// - Returns: Array of edit history entries
    func getEventEditHistory(eventId: UUID, withCausalRelationships: Bool = true) -> [EditHistory] {
        var result: [EditHistory] = []
        
        let context = PersistenceController.shared.container.viewContext
        
        if withCausalRelationships {
            // Use causal relationship analyzer
            result = SyncHistoryMerger.shared.analyzeCausalRelationships(eventId: eventId, context: context)
        } else {
            // Just sort by timestamp
            let fetchRequest = EditHistory.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "event.id == %@", eventId as CVarArg)
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            
            do {
                result = try context.fetch(fetchRequest)
            } catch {
                logger.error("Error fetching edit history: \(error.localizedDescription)")
            }
        }
        
        return result
    }
    
    // MARK: - Dashboard Data Loading
    
    /// Loads recent sync activity for the dashboard
    private func loadRecentSyncActivity() {
        let context = PersistenceController.shared.container.viewContext
        let syncLogRepository = SyncLogRepository(context: context)
        
        let logs = syncLogRepository.fetchRecentSyncLogs(limit: 20)
        
        DispatchQueue.main.async {
            self.recentSyncActivity = logs
        }
    }
    
    /// Loads pending conflicts requiring attention
    private func loadPendingConflicts() {
        let context = PersistenceController.shared.container.viewContext
        var pendingConflicts: [PendingConflictInfo] = []
        
        // In a real implementation, this would query for events with pending conflicts
        // For now, we'll use a simplified implementation based on sync logs with unresolved conflicts
        let syncLogRepository = SyncLogRepository(context: context)
        let logs = syncLogRepository.fetchRecentSyncLogs(limit: 50)
        
        for log in logs {
            if log.conflicts > 0 && (log.resolutionMethod == nil || log.resolutionMethod == "pending") {
                // This is a simplification - in a real implementation, we would track specific events
                // with conflicts and their detailed information
                
                // Get the corresponding device
                let familyDeviceRepository = FamilyDeviceRepository(context: context)
                if let device = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: log.deviceId ?? "") {
                    
                    // Create a pending conflict entry
                    let conflictInfo = PendingConflictInfo(
                        id: UUID(),
                        deviceId: log.deviceId ?? "",
                        deviceName: device.customName ?? "Unknown Device",
                        eventId: UUID(), // Placeholder - would be the actual event ID in a real implementation
                        eventTitle: "Event with conflict", // Placeholder
                        conflictDate: log.timestamp ?? Date(),
                        severity: .moderate, // Placeholder
                        affectedFields: ["title", "location"], // Placeholder
                        requiresManualResolution: false // Placeholder
                    )
                    
                    pendingConflicts.append(conflictInfo)
                }
            }
        }
        
        DispatchQueue.main.async {
            self.pendingConflicts = pendingConflicts
        }
    }
    
    /// Calculates overall sync health metrics
    private func calculateSyncHealthMetrics() {
        let context = PersistenceController.shared.container.viewContext
        let syncLogRepository = SyncLogRepository(context: context)
        let logs = syncLogRepository.fetchRecentSyncLogs(limit: 100)
        
        var metrics = SyncHealthMetrics()
        
        if !logs.isEmpty {
            // Success rate calculation
            let successfulSyncs = logs.filter { $0.details?.contains("Status: Success") ?? false }.count
            metrics.successRate = Double(successfulSyncs) / Double(logs.count)
            
            // Average duration calculation
            var totalDuration: TimeInterval = 0
            var durationsFound = 0
            
            for log in logs {
                if let details = log.details, let durationRange = details.range(of: "Duration: \\d+\\.\\d+", options: .regularExpression) {
                    let durationString = details[durationRange].replacingOccurrences(of: "Duration: ", with: "")
                    if let duration = Double(durationString) {
                        totalDuration += duration
                        durationsFound += 1
                    }
                }
            }
            
            if durationsFound > 0 {
                metrics.averageDuration = totalDuration / Double(durationsFound)
            }
            
            // Total conflicts and resolution rate
            var totalConflicts = 0
            var resolvedConflicts = 0
            
            for log in logs {
                let conflicts = Int(log.conflicts)
                totalConflicts += conflicts
                
                if conflicts > 0 && log.resolutionMethod != nil && log.resolutionMethod != "pending" {
                    resolvedConflicts += conflicts
                }
            }
            
            metrics.totalConflictsResolved = resolvedConflicts
            metrics.conflictResolutionRate = totalConflicts > 0 ? Double(resolvedConflicts) / Double(totalConflicts) : 1.0
            
            // Last sync times
            metrics.lastSyncAttemptTime = logs.first?.timestamp
            metrics.lastSuccessfulSyncTime = logs.first(where: { $0.details?.contains("Status: Success") ?? false })?.timestamp
            
            // Total events exchanged
            var totalEvents = 0
            for log in logs {
                totalEvents += Int(log.eventsReceived + log.eventsSent)
            }
            metrics.totalEventsExchanged = totalEvents
            
            // Device sync coverage
            let familyDeviceRepository = FamilyDeviceRepository(context: context)
            let allDevices = familyDeviceRepository.fetchAllDevices()
            let recentThreshold = Date().addingTimeInterval(-86400 * 7) // One week
            
            if !allDevices.isEmpty {
                let syncedDevicesCount = allDevices.filter { $0.lastSyncTimestamp != nil && $0.lastSyncTimestamp! > recentThreshold }.count
                metrics.deviceSyncCoverage = Double(syncedDevicesCount) / Double(allDevices.count)
            }
        }
        
        DispatchQueue.main.async {
            self.syncHealthMetrics = metrics
        }
    }
    
    // MARK: - Notification Methods
    
    /// Sends a notification for completed sync
    /// - Parameters:
    ///   - deviceName: The name of the device synced with
    ///   - events: Number of events exchanged
    private func sendSyncCompletedNotification(deviceName: String?, events: Int) {
        requestNotificationPermission { granted in
            guard granted else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "Sync Completed"
            content.body = "Synchronized with \(deviceName ?? "Unknown Device"). \(events) events exchanged."
            content.sound = UNNotificationSound.default
            content.categoryIdentifier = self.syncCompletedCategoryId
            
            // Create a unique identifier
            let identifier = "sync-completed-\(UUID().uuidString)"
            
            // Create the request
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            
            // Add the request
            self.notificationCenter.add(request) { error in
                if let error = error {
                    self.logger.error("Error sending sync completed notification: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Sends a notification for sync conflicts
    /// - Parameters:
    ///   - deviceName: The name of the device synced with
    ///   - conflicts: Number of conflicts detected
    ///   - syncLogId: The ID of the sync log
    private func sendConflictNotification(deviceName: String?, conflicts: Int, syncLogId: UUID) {
        requestNotificationPermission { granted in
            guard granted else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "Sync Conflicts Detected"
            content.body = "\(conflicts) conflicts detected during sync with \(deviceName ?? "Unknown Device")."
            content.sound = UNNotificationSound.default
            content.categoryIdentifier = self.syncConflictCategoryId
            
            // Add sync log ID to userInfo for handling actions
            content.userInfo = ["syncLogId": syncLogId.uuidString]
            
            // Create a unique identifier
            let identifier = "sync-conflict-\(UUID().uuidString)"
            
            // Create the request
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            
            // Add the request
            self.notificationCenter.add(request) { error in
                if let error = error {
                    self.logger.error("Error sending conflict notification: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Sends a notification for sync errors
    /// - Parameters:
    ///   - deviceName: The name of the device synced with
    ///   - error: Error message
    private func sendSyncErrorNotification(deviceName: String?, error: String?) {
        requestNotificationPermission { granted in
            guard granted else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "Sync Failed"
            content.body = "Sync with \(deviceName ?? "Unknown Device") failed: \(error ?? "Unknown error")"
            content.sound = UNNotificationSound.default
            content.categoryIdentifier = self.syncErrorCategoryId
            
            // Create a unique identifier
            let identifier = "sync-error-\(UUID().uuidString)"
            
            // Create the request
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            
            // Add the request
            self.notificationCenter.add(request) { error in
                if let error = error {
                    self.logger.error("Error sending sync error notification: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Requests permission for sending notifications
    /// - Parameter completion: Completion handler with granted flag
    private func requestNotificationPermission(completion: @escaping (Bool) -> Void) {
        notificationCenter.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                completion(true)
                
            case .notDetermined:
                self.notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error = error {
                        self.logger.error("Error requesting notification permission: \(error.localizedDescription)")
                    }
                    DispatchQueue.main.async {
                        completion(granted)
                    }
                }
                
            case .denied, .ephemeral:
                completion(false)
                
            @unknown default:
                completion(false)
            }
        }
    }
}

// MARK: - Logger Extension
extension Logger {
    static let sync = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.connectwith", category: "Sync")
}