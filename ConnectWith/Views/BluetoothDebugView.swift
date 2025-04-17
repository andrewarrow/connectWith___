import SwiftUI
import CoreBluetooth
import OSLog

#if DEBUG
struct BluetoothDebugView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @State private var expandedSection: DebugSection? = nil
    @State private var isAutoRefreshing = false
    @State private var logMessages: [String] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    enum DebugSection: String, CaseIterable {
        case deviceInfo = "Device Info"
        case nearbyDevices = "Nearby Devices"
        case connectionStatus = "Connection Status"
        case syncHistory = "Sync History"
        case dataTransfer = "Data Transfer"
        case eventDetails = "Event Details"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Debug Header
                HStack {
                    Text("Bluetooth Debug")
                        .font(.system(size: 20, weight: .bold))
                    
                    Spacer()
                    
                    Toggle("Auto Refresh", isOn: $isAutoRefreshing)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .labelsHidden()
                    
                    Button(action: {
                        // Capture current state in logs
                        captureCurrentState()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18))
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
                
                // Debug Sections
                ForEach(DebugSection.allCases, id: \.self) { section in
                    DebugSectionView(
                        title: section.rawValue,
                        isExpanded: expandedSection == section,
                        content: { getContentForSection(section) }
                    ) {
                        if expandedSection == section {
                            expandedSection = nil
                        } else {
                            expandedSection = section
                        }
                    }
                }
                
                // Log Messages Section
                DebugSectionView(
                    title: "Log Messages",
                    isExpanded: expandedSection == nil,
                    content: {
                        VStack(alignment: .leading, spacing: 8) {
                            if logMessages.isEmpty {
                                Text("No logs captured yet")
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                ForEach(logMessages.indices, id: \.self) { index in
                                    Text(logMessages[logMessages.count - 1 - index])
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(nil)
                                        .padding(.vertical, 2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                ) {
                    if expandedSection == nil {
                        expandedSection = .deviceInfo
                    } else {
                        expandedSection = nil
                    }
                }
                
                // Debug Actions
                HStack(spacing: 12) {
                    Button("Scan") {
                        bluetoothManager.startScanning()
                        addLog("Manual scan started")
                    }
                    .buttonStyle(DebugButtonStyle())
                    
                    Button("Force Sync") {
                        bluetoothManager.scanAndSyncWithFamilyMembers()
                        addLog("Manual sync initiated")
                    }
                    .buttonStyle(DebugButtonStyle())
                    
                    Button("Clear Logs") {
                        logMessages.removeAll()
                    }
                    .buttonStyle(DebugButtonStyle(bgColor: .red.opacity(0.8)))
                    
                    Spacer()
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .onAppear {
            captureCurrentState()
        }
        .onReceive(timer) { _ in
            if isAutoRefreshing {
                captureCurrentState()
            }
        }
        .navigationTitle("Bluetooth Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func captureCurrentState() {
        // Log the current state of Bluetooth
        addLog("Device ID: \(UIDevice.current.identifierForVendor?.uuidString ?? "Unknown")")
        addLog("Bluetooth State: \(bluetoothManager.permissionGranted ? "Authorized" : "Unauthorized")")
        addLog("Scanning: \(bluetoothManager.isScanning ? "Yes" : "No")")
        addLog("Nearby devices: \(bluetoothManager.nearbyDevices.count)")
        addLog("Connected peripherals: \(bluetoothManager.connectedPeripherals.count)")
        
        // Log sync status
        if let lastSyncTime = bluetoothManager.lastSyncTime {
            let formatter = RelativeDateTimeFormatter()
            let relativeTime = formatter.localizedString(for: lastSyncTime, relativeTo: Date())
            addLog("Last sync: \(relativeTime) with \(bluetoothManager.lastSyncDeviceName ?? "Unknown")")
            addLog("Synced events: \(bluetoothManager.syncedEventsCount)")
        }
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logMessages.insert("[\(timestamp)] \(message)", at: 0)
        
        // Limit log history
        if logMessages.count > 100 {
            logMessages.removeLast()
        }
    }
    
    private func getContentForSection(_ section: DebugSection) -> some View {
        switch section {
        case .deviceInfo:
            return AnyView(deviceInfoSection)
        case .nearbyDevices:
            return AnyView(nearbyDevicesSection)
        case .connectionStatus:
            return AnyView(connectionStatusSection)
        case .syncHistory:
            return AnyView(syncHistorySection)
        case .dataTransfer:
            return AnyView(dataTransferSection)
        case .eventDetails:
            return AnyView(eventDetailsSection)
        }
    }
    
    // MARK: - Section Content
    
    private var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailRow(label: "Device ID", value: UIDevice.current.identifierForVendor?.uuidString ?? "Unknown")
            DetailRow(label: "Device Name", value: bluetoothManager.deviceName)
            DetailRow(label: "BT Service UUID", value: BluetoothManager.serviceUUID.uuidString)
            DetailRow(label: "Calendar Char UUID", value: BluetoothManager.calendarCharacteristicUUID.uuidString)
            DetailRow(label: "Advertising", value: bluetoothManager.isAdvertising ? "Active" : "Inactive")
            DetailRow(label: "Permission", value: bluetoothManager.permissionGranted ? "Granted" : "Denied")
        }
        .padding()
    }
    
    private var nearbyDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if bluetoothManager.nearbyDevices.isEmpty {
                Text("No nearby devices detected")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ForEach(Array(bluetoothManager.nearbyDevices.enumerated()), id: \.offset) { (index, device) in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(getDeviceName(device))
                            .font(.headline)
                        
                        DetailRow(label: "ID", value: device.peripheral.identifier.uuidString)
                        DetailRow(label: "RSSI", value: device.rssi.stringValue)
                        
                        if let manufacturerData = device.advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
                            DetailRow(label: "Manufacturer", value: manufacturerData.hexDescription)
                        }
                        
                        if let serviceUUIDs = device.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                            Text("Services:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ForEach(serviceUUIDs, id: \.self) { uuid in
                                Text("• \(uuid.uuidString)")
                                    .font(.caption)
                                    .padding(.leading)
                            }
                        }
                        
                        DetailRow(
                            label: "Status", 
                            value: isDeviceConnected(device.peripheral.identifier) ? "Connected" : "Not Connected"
                        )
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
    }
    
    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRow(label: "Scanning", value: bluetoothManager.isScanning ? "Active" : "Inactive")
            DetailRow(label: "Scan Progress", value: "\(Int(bluetoothManager.scanningProgress * 100))%")
            DetailRow(label: "Connected Devices", value: "\(bluetoothManager.connectedPeripherals.count)")
            DetailRow(label: "Sync In Progress", value: bluetoothManager.syncInProgress ? "Yes" : "No")
            
            Divider()
            
            if bluetoothManager.connectedPeripherals.isEmpty {
                Text("No active connections")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                Text("Connected Peripherals:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(bluetoothManager.connectedPeripherals, id: \.identifier) { peripheral in
                    HStack {
                        Text(getDeviceName(peripheral: peripheral))
                        Spacer()
                        Text(peripheral.identifier.uuidString)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
    }
    
    private var syncHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lastSyncTime = bluetoothManager.lastSyncTime {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .medium
                
                DetailRow(label: "Last Sync", value: formatter.string(from: lastSyncTime))
                DetailRow(label: "With Device", value: bluetoothManager.lastSyncDeviceName ?? "Unknown")
                DetailRow(label: "Events Synced", value: "\(bluetoothManager.syncedEventsCount)")
                
                Divider()
                
                Text("Sync Log:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ForEach(bluetoothManager.syncLog.indices, id: \.self) { index in
                    let entry = bluetoothManager.syncLog[bluetoothManager.syncLog.count - 1 - index]
                    VStack(alignment: .leading) {
                        Text(formatter.string(from: entry.timestamp))
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(entry.deviceName): \(entry.action)")
                            .font(.body)
                        
                        if !entry.details.isEmpty {
                            Text(entry.details)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Text("No sync history available")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
        .padding()
    }
    
    private var dataTransferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lastData = bluetoothManager.lastTransferredData {
                DetailRow(label: "Size", value: "\(lastData.count) bytes")
                DetailRow(label: "Direction", value: bluetoothManager.lastTransferDirection)
                DetailRow(label: "Timestamp", value: formatTimestamp(bluetoothManager.lastTransferTimestamp))
                
                Divider()
                
                Text("Data Preview:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(lastData.hexDescription)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(4)
                }
                
                Divider()
                
                if let jsonString = prettyPrintJson(lastData) {
                    Text("JSON Content:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ScrollView {
                        Text(jsonString)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .frame(height: 200)
                }
            } else {
                Text("No data transfer recorded")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
        .padding()
    }
    
    private var eventDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let calendarStore = CalendarStore.shared
            let events = calendarStore.getAllEvents()
            
            if events.isEmpty {
                Text("No events available")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ForEach(events, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title)
                            .font(.headline)
                        
                        DetailRow(label: "ID", value: event.id.uuidString)
                        DetailRow(label: "Date", value: formatDate(event.date))
                        DetailRow(label: "Location", value: event.location)
                        
                        let syncCount = calendarStore.getSyncCountForEvent(id: event.id)
                        DetailRow(label: "Synced With", value: "\(syncCount) device(s)")
                        
                        let history = calendarStore.getChangeHistoryForEvent(id: event.id)
                        if !history.isEmpty {
                            Text("Change History:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.top, 4)
                            
                            ForEach(history.indices.prefix(3), id: \.self) { index in
                                let change = history[history.count - 1 - index]
                                Text("\(formatTimestamp(change.timestamp)) - \(change.deviceName): \(change.changeType.rawValue.capitalized)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if history.count > 3 {
                                Text("+ \(history.count - 3) more changes")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Helper Functions
    
    private func getDeviceName(peripheral: CBPeripheral) -> String {
        if let storedDevice = DeviceStore.shared.getDevice(identifier: peripheral.identifier.uuidString) {
            return storedDevice.name
        } else if let name = peripheral.name, !name.isEmpty {
            return name
        } else {
            return "Unknown Device"
        }
    }
    
    private func getDeviceName(_ device: (peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)) -> String {
        if let storedDevice = DeviceStore.shared.getDevice(identifier: device.peripheral.identifier.uuidString) {
            return storedDevice.name
        } else if let localName = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
            return localName
        } else if let name = device.peripheral.name, !name.isEmpty {
            return name
        } else {
            return "Unknown Device"
        }
    }
    
    private func isDeviceConnected(_ identifier: UUID) -> Bool {
        return bluetoothManager.connectedPeripherals.contains { $0.identifier == identifier }
    }
    
    private func formatTimestamp(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func prettyPrintJson(_ data: Data) -> String? {
        do {
            let json = try JSONSerialization.jsonObject(with: data)
            let prettyData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            return String(data: prettyData, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - Supporting Views

struct DebugSectionView<Content: View>: View {
    let title: String
    let isExpanded: Bool
    let content: () -> Content
    let toggleAction: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: toggleAction) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Content
            if isExpanded {
                content()
                    .transition(.opacity)
            }
        }
        .background(Color.white.opacity(0.001)) // Ensures the whole area is tappable
        .padding(.horizontal)
        .animation(.spring(), value: isExpanded)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DebugButtonStyle: ButtonStyle {
    var bgColor: Color = .blue
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded))
            .fontWeight(.medium)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(bgColor.opacity(configuration.isPressed ? 0.7 : 0.6))
            .foregroundColor(.white)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(), value: configuration.isPressed)
    }
}

// MARK: - Helper Extensions

extension Data {
    var hexDescription: String {
        return self.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension NSNumber {
    var stringValue: String {
        return String(describing: self)
    }
}

// This preview requires the BluetoothManager to be mocked
struct BluetoothDebugView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            BluetoothDebugView()
                .environmentObject(BluetoothManager())
        }
    }
}
#endif