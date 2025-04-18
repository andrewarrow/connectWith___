import CoreData
import UIKit

class PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    private let isPreview: Bool
    
    // Create a background context for operations that should not block the UI
    lazy var backgroundContext: NSManagedObjectContext = {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }()
    
    // Initialize with option for preview data
    init(inMemory: Bool = false) {
        self.isPreview = inMemory
        container = NSPersistentContainer(name: "DeviceModel")
        
        if inMemory {
            // Use in-memory store for previews and tests
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure data protection - Complete protection (no access when device is locked)
            guard let storeDescription = container.persistentStoreDescriptions.first else {
                fatalError("Failed to retrieve store description")
            }
            
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            storeDescription.setOption(FileProtectionType.complete as NSString, forKey: NSPersistentStoreFileProtectionKey)
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                // In a production app, you might want to report this to an analytics service
                // rather than crashing the app
                fatalError("Error loading Core Data stores: \(error.localizedDescription)")
            }
            
            // Verify data protection is enabled
            if !inMemory {
                self.verifyDataProtection()
            }
        }
        
        // Configure view context
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Set up to merge changes from background contexts automatically
        NotificationCenter.default.addObserver(
            self, selector: #selector(managedObjectContextDidSave),
            name: .NSManagedObjectContextDidSave, object: nil
        )
        
        // If in preview mode, load sample data
        if inMemory {
            self.createSampleData()
        }
    }
    
    // MARK: - Context Management
    
    @objc private func managedObjectContextDidSave(notification: Notification) {
        // Only merge changes from other contexts into the view context
        let sender = notification.object as! NSManagedObjectContext
        if sender !== container.viewContext && 
            sender.persistentStoreCoordinator == container.persistentStoreCoordinator {
            container.viewContext.perform {
                self.container.viewContext.mergeChanges(fromContextDidSave: notification)
            }
        }
    }
    
    // MARK: - Data Operations
    
    /// Saves changes in the view context
    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // In a production app, you would handle this error more gracefully
                print("Error saving view context: \(error)")
                
                // Provide more detailed error information in debug builds
                #if DEBUG
                let nsError = error as NSError
                print("Core Data save error: \(nsError), \(nsError.userInfo)")
                #endif
            }
        }
    }
    
    /// Performs work on a background context and saves
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            block(context)
            
            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    print("Background context save error: \(error)")
                }
            }
        }
    }
    
    /// Deletes all data from the persistent store
    func deleteAllData() {
        performBackgroundTask { context in
            // Delete all CoreData entities
            let entityNames = self.container.managedObjectModel.entities.compactMap { $0.name }
            
            for entityName in entityNames {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                batchDeleteRequest.resultType = .resultTypeObjectIDs
                
                do {
                    let batchResult = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
                    if let objectIDs = batchResult?.result as? [NSManagedObjectID] {
                        // Update view context with deletions
                        let changes = [NSDeletedObjectsKey: objectIDs]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.container.viewContext])
                    }
                } catch {
                    print("Error deleting \(entityName) entities: \(error)")
                }
            }
        }
    }
    
    // MARK: - Data Protection
    
    /// Verifies that data protection is properly enabled on the persistent store
    private func verifyDataProtection() {
        guard let storeURL = container.persistentStoreCoordinator.persistentStores.first?.url else {
            print("Warning: Could not determine store URL for data protection verification")
            return
        }
        
        do {
            let resourceValues = try storeURL.resourceValues(forKeys: [.fileProtectionKey])
            if let protection = resourceValues.fileProtection {
                print("Core Data store protection level: \(protection)")
                
                if protection != .complete {
                    print("Warning: Data protection is not set to Complete")
                }
            } else {
                print("Warning: Could not determine file protection level")
            }
        } catch {
            print("Error checking data protection: \(error)")
        }
    }
    
    // MARK: - Sample Data
    
    /// Creates sample data for previews
    private func createSampleData() {
        let context = container.viewContext
        
        // Create sample events for each month
        for month in Month.allCases {
            let event = Event.create(
                in: context,
                title: "Sample \(month.rawValue) Event",
                location: "Location for \(month.rawValue)",
                day: Int.random(in: 1...28),
                month: month
            )
            
            // Add some edit history
            let history = EditHistory.create(in: context, for: event)
            history.recordChanges(
                previousTitle: nil,
                newTitle: event.title,
                previousLocation: nil,
                newLocation: event.location,
                previousDay: nil,
                newDay: Int(event.day)
            )
        }
        
        // Create sample devices
        let localDevice = FamilyDevice.createLocalDevice(in: context)
        
        // Create some family devices
        let familyMembers = ["Mom", "Dad", "Sister", "Brother"]
        for member in familyMembers {
            let device = FamilyDevice.create(
                in: context,
                bluetoothIdentifier: UUID().uuidString,
                customName: member
            )
            
            // Create sample sync log
            let syncLog = SyncLog.create(in: context, deviceId: device.bluetoothIdentifier, deviceName: device.customName)
            syncLog.eventsReceived = Int32.random(in: 1...12)
            syncLog.eventsSent = Int32.random(in: 1...12)
            syncLog.conflicts = Int32.random(in: 0...3)
            syncLog.resolutionMethod = "Automatic merge"
            syncLog.details = "Sample sync log for \(member)"
        }
        
        // Save the sample data
        save()
    }
}