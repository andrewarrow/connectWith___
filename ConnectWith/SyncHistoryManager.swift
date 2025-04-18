import Foundation
import CoreData
import OSLog

/// Manages sync history for devices
class SyncHistoryManager {
    // Singleton instance
    static let shared = SyncHistoryManager()
    
    // Private initializer for singleton
    private init() {}
    
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
    
    /// Creates a new sync log entry
    /// - Parameters:
    ///   - deviceId: The device's Bluetooth identifier
    ///   - deviceName: The device's name
    ///   - eventsReceived: Number of events received during sync
    ///   - eventsSent: Number of events sent during sync
    ///   - conflicts: Number of conflicts detected during sync
    /// - Returns: The created sync log, or nil if creation failed
    func createSyncLog(
        deviceId: String,
        deviceName: String?,
        eventsReceived: Int,
        eventsSent: Int,
        conflicts: Int = 0,
        resolutionMethod: String? = nil
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
            let details = """
            Synchronized with \(deviceName ?? "Unknown Device")
            Received: \(eventsReceived) events
            Sent: \(eventsSent) events
            Conflicts: \(conflicts)
            """
            log.details = details
            
            do {
                try context.save()
                createdLog = log
                
                // Also update the FamilyDevice last sync timestamp
                let familyDeviceRepository = FamilyDeviceRepository(context: context)
                if let familyDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: deviceId) {
                    familyDevice.lastSyncTimestamp = Date()
                    try context.save()
                }
                
                Logger.bluetooth.info("Created sync log for device \(deviceId): \(eventsReceived) received, \(eventsSent) sent, \(conflicts) conflicts")
            } catch {
                Logger.bluetooth.error("Failed to create sync log: \(error.localizedDescription)")
            }
        }
        
        return createdLog
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
                Logger.bluetooth.info("Deleted \(deletedCount) old sync logs")
            } catch {
                Logger.bluetooth.error("Failed to delete old sync logs: \(error.localizedDescription)")
            }
        }
        
        return deletedCount
    }
}