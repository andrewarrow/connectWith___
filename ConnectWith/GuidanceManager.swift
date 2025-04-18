import Foundation
import SwiftUI
import Combine

/// GuidanceManager provides app guidance and tutorial functionality
class GuidanceManager: ObservableObject {
    // MARK: - Published Properties
    
    /// Flag to indicate if guidance is currently being shown
    @Published var isShowingGuidance = false
    
    /// Current guidance step (zero-based index)
    @Published var currentStep = 0
    
    /// Total number of steps in current guidance flow
    @Published var totalSteps = 0
    
    /// Current guidance message
    @Published var guidanceMessage = ""
    
    /// Current guidance title
    @Published var guidanceTitle = ""
    
    /// Flag to indicate if the user has seen all guidance steps
    @Published var guidanceComplete = false
    
    // MARK: - Private Properties
    
    /// Storage for user guidance preferences
    private let userDefaults = UserDefaults.standard
    
    /// The currently active guidance flow
    private var currentFlow: GuidanceFlow?
    
    /// Guidance flow factory to create guidance flows
    private let flowFactory = GuidanceFlowFactory()
    
    /// Tracks the available guidance types
    private var availableGuidanceTypes: [GuidanceType] = [
        .firstLaunch,
        .syncFlow,
        .deviceDiscovery,
        .calendarEditing
    ]
    
    // MARK: - Initialization
    
    init() {
        // Check user defaults for completed guidance
        for type in GuidanceType.allCases {
            if userDefaults.bool(forKey: guidanceCompletionKey(for: type)) {
                availableGuidanceTypes.removeAll { $0 == type }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Starts a specific guidance flow
    /// - Parameter type: The type of guidance to start
    func startGuidance(type: GuidanceType) {
        guard let flow = flowFactory.createFlow(type: type) else {
            return
        }
        
        currentFlow = flow
        totalSteps = flow.steps.count
        currentStep = 0
        
        if totalSteps > 0 {
            updateCurrentGuidance()
            isShowingGuidance = true
        }
    }
    
    /// Get the next guidance step, if available
    func nextStep() {
        guard let flow = currentFlow, currentStep < flow.steps.count - 1 else {
            completeGuidance()
            return
        }
        
        currentStep += 1
        updateCurrentGuidance()
    }
    
    /// Get the previous guidance step, if available
    func previousStep() {
        guard currentStep > 0 else { return }
        
        currentStep -= 1
        updateCurrentGuidance()
    }
    
    /// Skip the current guidance flow
    func skipGuidance() {
        guard let flow = currentFlow else { return }
        
        // Mark as completed so it doesn't show again
        markGuidanceAsCompleted(type: flow.type)
        
        // Hide guidance
        isShowingGuidance = false
        guidanceComplete = true
    }
    
    /// Check if a specific guidance type is available
    /// - Parameter type: The guidance type to check
    /// - Returns: True if the guidance is available (not completed)
    func isGuidanceAvailable(type: GuidanceType) -> Bool {
        return availableGuidanceTypes.contains(type)
    }
    
    /// Resets all guidance completion statuses
    func resetAllGuidance() {
        for type in GuidanceType.allCases {
            userDefaults.removeObject(forKey: guidanceCompletionKey(for: type))
        }
        
        availableGuidanceTypes = GuidanceType.allCases
    }
    
    // MARK: - Private Methods
    
    /// Updates the current guidance message and title based on the current step
    private func updateCurrentGuidance() {
        guard let flow = currentFlow, currentStep < flow.steps.count else { return }
        
        let step = flow.steps[currentStep]
        guidanceTitle = step.title
        guidanceMessage = step.message
    }
    
    /// Completes the current guidance flow
    private func completeGuidance() {
        guard let flow = currentFlow else { return }
        
        // Mark as completed
        markGuidanceAsCompleted(type: flow.type)
        
        // Hide guidance
        isShowingGuidance = false
        guidanceComplete = true
    }
    
    /// Marks a guidance type as completed
    /// - Parameter type: The guidance type to mark as completed
    private func markGuidanceAsCompleted(type: GuidanceType) {
        userDefaults.set(true, forKey: guidanceCompletionKey(for: type))
        availableGuidanceTypes.removeAll { $0 == type }
    }
    
    /// Creates a user defaults key for a guidance type
    /// - Parameter type: The guidance type
    /// - Returns: A string key for user defaults
    private func guidanceCompletionKey(for type: GuidanceType) -> String {
        return "guidance_completed_\(type.rawValue)"
    }
}

// MARK: - Guidance Types

/// Types of guidance flows available in the app
enum GuidanceType: String, CaseIterable {
    case firstLaunch = "first_launch"
    case syncFlow = "sync_flow"
    case deviceDiscovery = "device_discovery"
    case calendarEditing = "calendar_editing"
}

// MARK: - Guidance Step

/// Represents a single step in a guidance flow
struct GuidanceStep {
    let title: String
    let message: String
}

// MARK: - Guidance Flow

/// Represents a complete guidance flow with multiple steps
class GuidanceFlow {
    let type: GuidanceType
    let steps: [GuidanceStep]
    
    init(type: GuidanceType, steps: [GuidanceStep]) {
        self.type = type
        self.steps = steps
    }
}

// MARK: - Guidance Flow Factory

/// Factory to create different guidance flows
class GuidanceFlowFactory {
    /// Creates a guidance flow for a specific type
    /// - Parameter type: The type of guidance to create
    /// - Returns: A guidance flow, or nil if the type is not supported
    func createFlow(type: GuidanceType) -> GuidanceFlow? {
        switch type {
        case .firstLaunch:
            return createFirstLaunchFlow()
        case .syncFlow:
            return createSyncFlow()
        case .deviceDiscovery:
            return createDeviceDiscoveryFlow()
        case .calendarEditing:
            return createCalendarEditingFlow()
        }
    }
    
    /// Creates the first launch guidance flow
    private func createFirstLaunchFlow() -> GuidanceFlow {
        let steps = [
            GuidanceStep(
                title: "Welcome to 12×",
                message: "12× helps you plan 12 important family events per year - one for each month. Let's get started!"
            ),
            GuidanceStep(
                title: "No Internet Required",
                message: "12× works entirely offline. Your calendar syncs automatically with family members over Bluetooth."
            ),
            GuidanceStep(
                title: "Find Family Members",
                message: "Tap 'Find Family Members' to discover other devices running 12× nearby."
            ),
            GuidanceStep(
                title: "Create Events",
                message: "Tap 'Family Calendar' to view and create monthly events."
            ),
            GuidanceStep(
                title: "You're Ready!",
                message: "That's it! Enjoy planning your family events with 12×."
            )
        ]
        
        return GuidanceFlow(type: .firstLaunch, steps: steps)
    }
    
    /// Creates the sync flow guidance
    private func createSyncFlow() -> GuidanceFlow {
        let steps = [
            GuidanceStep(
                title: "Automatic Syncing",
                message: "Your calendar syncs automatically with other family members when in range."
            ),
            GuidanceStep(
                title: "Sync Status",
                message: "You can check sync status in the debug view to confirm data transfer."
            ),
            GuidanceStep(
                title: "Version History",
                message: "All changes are tracked, so you can see who modified each event."
            )
        ]
        
        return GuidanceFlow(type: .syncFlow, steps: steps)
    }
    
    /// Creates the device discovery guidance
    private func createDeviceDiscoveryFlow() -> GuidanceFlow {
        let steps = [
            GuidanceStep(
                title: "Finding Family Members",
                message: "Make sure Bluetooth is enabled on all devices."
            ),
            GuidanceStep(
                title: "Naming Devices",
                message: "Give each device a family name to easily identify who made changes."
            ),
            GuidanceStep(
                title: "Family Members List",
                message: "Your saved family members will appear in the Family Members tab."
            )
        ]
        
        return GuidanceFlow(type: .deviceDiscovery, steps: steps)
    }
    
    /// Creates the calendar editing guidance
    private func createCalendarEditingFlow() -> GuidanceFlow {
        let steps = [
            GuidanceStep(
                title: "Monthly Calendar Cards",
                message: "Each month has its own card. Swipe to move between months."
            ),
            GuidanceStep(
                title: "Editing Events",
                message: "Tap the pencil icon to edit an event's title, location, and date."
            ),
            GuidanceStep(
                title: "Event Syncing",
                message: "Changes will automatically sync with family members when in Bluetooth range."
            )
        ]
        
        return GuidanceFlow(type: .calendarEditing, steps: steps)
    }
}