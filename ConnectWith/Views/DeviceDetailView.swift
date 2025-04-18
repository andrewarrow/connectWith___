import SwiftUI
import CoreBluetooth
import CoreData
import OSLog
import Combine

struct DeviceDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var bluetoothManager: BluetoothDiscoveryManager
    
    // Device data
    let device: BluetoothDevice
    let isLocalDevice: Bool
    
    // State for editing
    @State private var deviceName: String
    @State private var isEditing: Bool = false
    @State private var showDeleteConfirmation = false
    
    // Connection state
    @StateObject private var connectionManager = ConnectionManager.shared
    @State private var isConnecting = false
    @State private var connectionError: String?
    @State private var showConnectionError = false
    
    // Sync state
    @State private var isSyncing = false
    @State private var syncStats: (sent: Int, received: Int, conflicts: Int)?
    @State private var cancellables = Set<AnyCancellable>()
    
    // Initialize with default values
    init(device: BluetoothDevice, isLocalDevice: Bool) {
        self.device = device
        self.isLocalDevice = isLocalDevice
        self._deviceName = State(initialValue: device.deviceName ?? "Unknown Device")
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with large icon
                deviceHeader
                
                // Device information sections
                deviceIdentitySection
                connectionStatusSection
                syncHistorySection
                
                // Actions section
                actionsSection
            }
            .padding()
        }
        .navigationTitle("Device Details")
        .navigationBarItems(trailing: Button(action: {
            if isEditing {
                // Save the name
                saveDeviceName()
                isEditing = false
            } else {
                // Enter edit mode
                isEditing = true
            }
        }) {
            Text(isEditing ? "Save" : "Edit")
        })
        .onAppear {
            // Load sync statistics when the view appears
            loadSyncStatistics()
        }
        .alert("Delete Device", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteDevice()
            }
        } message: {
            Text("Are you sure you want to remove this device? You'll need to discover it again to reconnect.")
        }
        .alert("Connection Error", isPresented: $showConnectionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(connectionError ?? "Failed to connect to device")
        }
    }
    
    // MARK: - View Components
    
    private var deviceHeader: some View {
        HStack(spacing: 20) {
            // Device icon
            ZStack {
                Circle()
                    .fill(deviceColor)
                    .frame(width: 80, height: 80)
                
                Image(systemName: deviceIcon)
                    .font(.system(size: 40))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 5) {
                // Device name (editable in edit mode)
                if isEditing {
                    TextField("Device Name", text: $deviceName)
                        .font(.title)
                        .padding(10)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    Text(deviceName)
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                // Device type label
                HStack {
                    Text(isLocalDevice ? "This Device" : device.supports12xSync ? "Family Device" : "Other Device")
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(deviceColor.opacity(0.2))
                        .foregroundColor(deviceColor)
                        .cornerRadius(5)
                    
                    if connectionStatus == "Connected" {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(5)
                    } else if device.isRecentlyActive {
                        HStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Recently Active")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(5)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var deviceIdentitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Device Identity")
            
            infoRow(
                icon: "number",
                title: "Device ID",
                value: device.identifier.prefix(8) + "..."
            )
            
            if !isLocalDevice {
                infoRow(
                    icon: "person.fill",
                    title: "Family Member Name",
                    value: deviceName
                )
            }
            
            infoRow(
                icon: "bolt.horizontal.fill",
                title: "Supports Sync",
                value: device.supports12xSync ? "Yes" : "No"
            )
        }
    }
    
    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Connection Status")
            
            infoRow(
                icon: "antenna.radiowaves.left.and.right",
                title: "Status",
                value: connectionStatus,
                valueColor: connectionStatusColor
            )
            
            infoRow(
                icon: "clock",
                title: "Last Seen",
                value: formattedLastSeen
            )
            
            infoRow(
                icon: "wifi",
                title: "Signal Strength",
                value: signalStrengthText,
                customValue: signalStrengthBars
            )
        }
    }
    
    private var syncHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Sync History")
            
            if let lastSyncTime = SyncHistoryManager.shared.getLastSyncTime(bluetoothIdentifier: device.identifier) {
                infoRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Last Synchronized",
                    value: formatDate(lastSyncTime)
                )
                
                if let stats = syncStats {
                    infoRow(
                        icon: "tray.and.arrow.down",
                        title: "Events Received",
                        value: "\(stats.received)"
                    )
                    
                    infoRow(
                        icon: "tray.and.arrow.up",
                        title: "Events Sent",
                        value: "\(stats.sent)"
                    )
                    
                    if stats.conflicts > 0 {
                        infoRow(
                            icon: "exclamationmark.triangle",
                            title: "Conflicts Resolved",
                            value: "\(stats.conflicts)"
                        )
                    }
                } else {
                    Text("Loading sync statistics...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 5)
                }
            } else {
                Text("No sync history available")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 5)
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Actions")
            
            if !isLocalDevice {
                Button(action: {
                    initiateConnection()
                }) {
                    HStack {
                        if isConnecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                                .padding(.trailing, 5)
                            Text("Connecting...")
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text(connectionStatus == "Connected" ? "Reconnect" : "Connect Now")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isConnecting ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isConnecting)
                
                Button(action: {
                    initiateSync()
                }) {
                    HStack {
                        if isSyncing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                                .padding(.trailing, 5)
                            Text("Syncing...")
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Calendar Data")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSyncing ? Color.gray : connectionStatus == "Connected" ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isSyncing || connectionStatus != "Connected")
                
                Button(action: {
                    // Show delete confirmation
                    showDeleteConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Remove Device")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else {
                Text("This is your device.")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 5)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Divider()
                .frame(height: 1)
                .background(Color.gray.opacity(0.3))
                .frame(width: 250)
        }
    }
    
    private func infoRow(icon: String, title: String, value: String, valueColor: Color = .secondary, customValue: AnyView? = nil) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            Text(title)
                .foregroundColor(.primary)
            
            Spacer()
            
            if let customValue = customValue {
                customValue
            } else {
                Text(value)
                    .foregroundColor(valueColor)
            }
        }
        .padding(.vertical, 5)
    }
    
    private var signalStrengthBars: AnyView {
        let strength = device.signalStrengthIndicator
        return AnyView(
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    Rectangle()
                        .fill(index < strength ? Color.green : Color.secondary.opacity(0.3))
                        .frame(width: 3, height: CGFloat(6 + index * 3))
                        .cornerRadius(1)
                }
            }
        )
    }
    
    // MARK: - Helper Properties
    
    private var deviceIcon: String {
        if device.supports12xSync {
            return "iphone.radiowaves.left.and.right"
        } else {
            return "iphone"
        }
    }
    
    private var deviceColor: Color {
        if isLocalDevice {
            return .blue
        } else if device.supports12xSync {
            return .green
        } else {
            return .gray
        }
    }
    
    private var connectionStatus: String {
        if isLocalDevice {
            return "Local Device"
        } else if connectionManager.connectionInProgress[device.identifier] == true {
            return "Connecting..."
        } else {
            let status = connectionManager.getConnectionStatus(identifier: device.identifier)
            switch status {
            case .connected:
                return "Connected"
            case .disconnected:
                return device.isRecentlyActive ? "Recently Active" : "Not Connected"
            case .unknown:
                return "Unknown"
            }
        }
    }
    
    private var connectionStatusColor: Color {
        switch connectionStatus {
        case "Connected":
            return .green
        case "Connecting...":
            return .orange
        case "Recently Active":
            return .orange
        default:
            return .secondary
        }
    }
    
    private var formattedLastSeen: String {
        if let lastSeen = device.lastSeen {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: lastSeen, relativeTo: Date())
        } else {
            return "Never"
        }
    }
    
    private var signalStrengthText: String {
        switch device.signalStrengthIndicator {
        case 0: return "None"
        case 1: return "Very Weak"
        case 2: return "Weak"
        case 3: return "Moderate"
        case 4: return "Strong"
        case 5: return "Excellent"
        default: return "Unknown"
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func saveDeviceName() {
        PersistenceController.shared.performBackgroundTask { context in
            let fetchRequest = BluetoothDevice.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "identifier == %@", device.identifier)
            
            do {
                let results = try context.fetch(fetchRequest)
                if let deviceToRename = results.first {
                    deviceToRename.deviceName = deviceName
                    try context.save()
                    Logger.bluetooth.info("Renamed device \(self.device.identifier) to \(self.deviceName)")
                    
                    // Also update the FamilyDevice entry if it exists
                    let familyDeviceRepository = FamilyDeviceRepository(context: context)
                    if let familyDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: self.device.identifier) {
                        familyDevice.customName = self.deviceName
                        try context.save()
                    }
                }
            } catch {
                Logger.bluetooth.error("Failed to rename device: \(error.localizedDescription)")
            }
        }
    }
    
    private func deleteDevice() {
        PersistenceController.shared.performBackgroundTask { context in
            // First, delete the BluetoothDevice entry
            let fetchRequest = BluetoothDevice.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "identifier == %@", self.device.identifier)
            
            do {
                let results = try context.fetch(fetchRequest)
                if let deviceToDelete = results.first {
                    context.delete(deviceToDelete)
                    try context.save()
                    Logger.bluetooth.info("Deleted BluetoothDevice: \(self.device.identifier)")
                }
            } catch {
                Logger.bluetooth.error("Failed to delete BluetoothDevice: \(error.localizedDescription)")
            }
            
            // Also delete the FamilyDevice entry if it exists
            let familyDeviceRepository = FamilyDeviceRepository(context: context)
            if let familyDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: self.device.identifier) {
                try? familyDeviceRepository.delete(familyDevice)
                Logger.bluetooth.info("Deleted FamilyDevice: \(self.device.identifier)")
            }
        }
        
        // Dismiss the view after deleting
        presentationMode.wrappedValue.dismiss()
    }
    
    private func initiateConnection() {
        guard !isConnecting else { return }
        
        isConnecting = true
        
        connectionManager.connectToDevice(identifier: device.identifier)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isConnecting = false
                    
                    if case .failure(let error) = completion {
                        connectionError = error.localizedDescription
                        showConnectionError = true
                        Logger.bluetooth.error("Connection failed: \(error.localizedDescription)")
                    }
                },
                receiveValue: { success in
                    Logger.bluetooth.info("Connection status: \(success ? "connected" : "failed")")
                }
            )
            .store(in: &cancellables)
    }
    
    private func initiateSync() {
        guard !isSyncing && connectionStatus == "Connected" else { return }
        
        isSyncing = true
        
        // This is just a placeholder for the sync functionality
        // In a real implementation, this would call into the sync engine
        
        // Simulate a sync operation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Create a sync log entry
            let eventsReceived = Int.random(in: 0...5)
            let eventsSent = Int.random(in: 0...5)
            
            let _ = SyncHistoryManager.shared.createSyncLog(
                deviceId: device.identifier,
                deviceName: deviceName,
                eventsReceived: eventsReceived,
                eventsSent: eventsSent
            )
            
            // Update connection manager
            connectionManager.updateDeviceLastSync(identifier: device.identifier)
            
            // Reload sync statistics
            loadSyncStatistics()
            
            // End the sync operation
            isSyncing = false
            
            Logger.bluetooth.info("Simulated sync completed with device: \(device.identifier)")
        }
    }
    
    private func loadSyncStatistics() {
        // Get sync statistics for this device
        syncStats = SyncHistoryManager.shared.getSyncStatistics(bluetoothIdentifier: device.identifier)
    }
}

struct DeviceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        
        // Create a sample device for preview
        let device = BluetoothDevice(context: context)
        device.identifier = UUID().uuidString
        device.deviceName = "Mom's iPhone"
        device.lastSeen = Date().addingTimeInterval(-3600) // One hour ago
        
        return NavigationView {
            DeviceDetailView(device: device, isLocalDevice: false)
                .environment(\.managedObjectContext, context)
                .environmentObject(BluetoothDiscoveryManager.shared)
        }
    }
}