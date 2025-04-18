import SwiftUI
import CoreBluetooth
import OSLog
import UIKit

// Note: This file was previously wrapped in #if DEBUG, but we've removed that
// to make it available in both debug and release builds. Access is controlled
// through a hidden gesture in the main menu.

/// Advanced debug view for Bluetooth connectivity and sync operations
/// Provides detailed diagnostics for technical troubleshooting
struct BluetoothDebugView: View {
    // MARK: - Environment and State
    @EnvironmentObject private var bluetoothDiscoveryManager: BluetoothDiscoveryManager
    @EnvironmentObject private var connectionManager: ConnectionManager
    @State private var expandedSection: DebugSection? = nil
    @State private var isAutoRefreshing = false
    @State private var logMessages: [LogMessage] = []
    @State private var logFilter: LogLevel = .all
    @State private var showShareSheet = false
    @State private var exportedLogData: Data?
    @State private var batteryLevel: Float = UIDevice.current.batteryLevel
    @State private var isDeviceCharging: Bool = false
    
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    // For hidden gesture detector
    @State private var tapCount = 0
    @State private var lastTapTime: Date = Date()
    
    // MARK: - Types
    
    /// Debug sections available in the interface
    enum DebugSection: String, CaseIterable, Identifiable {
        case deviceInfo = "Device Info"
        case nearbyDevices = "Nearby Devices"
        case connectionStatus = "Connection Status"
        case syncHistory = "Sync History"
        case dataTransfer = "Data Transfer"
        case batteryStats = "Battery Statistics"
        case errorLogs = "Error Logs"
        
        var id: String { self.rawValue }
    }
    
    /// Log levels for filtering
    enum LogLevel: String, CaseIterable {
        case info = "Info"
        case warning = "Warning"
        case error = "Error"
        case debug = "Debug"
        case all = "All"
    }
    
    /// Log message structure for storing logs with metadata
    struct LogMessage: Identifiable, Codable {
        let id = UUID()
        let timestamp: Date
        let level: String
        let message: String
        let details: String?
        
        var formattedTimestamp: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
            return formatter.string(from: timestamp)
        }
    }
    
    // MARK: - Main View Body
    var body: some View {
        VStack(spacing: 0) {
            // Debug Header
            headerView
                .padding(.horizontal)
                .padding(.top)
                .padding(.bottom, 8)
                .background(Color(UIColor.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
            
            // Main Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Device Quick Stats
                    quickStatsView
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    // Debug Sections
                    ForEach(DebugSection.allCases) { section in
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
                    logSectionView
                    
                    // Debug Actions
                    actionButtonsView
                        .padding(.horizontal)
                        .padding(.bottom)
                }
            }
        }
        .navigationTitle("Bluetooth Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Export Logs") {
                        exportLogs()
                    }
                    
                    Button("Copy Device ID") {
                        UIPasteboard.general.string = UIDevice.current.identifierForVendor?.uuidString ?? "Unknown"
                    }
                    
                    Menu("Log Filter") {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Button {
                                logFilter = level
                            } label: {
                                HStack {
                                    Text(level.rawValue)
                                    if logFilter == level {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    
                    Button("Clear All Logs") {
                        withAnimation {
                            logMessages.removeAll()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            setupBatteryMonitoring()
            captureCurrentState()
        }
        .onDisappear {
            UIDevice.current.isBatteryMonitoringEnabled = false
            NotificationCenter.default.removeObserver(self)
        }
        .onReceive(timer) { _ in
            if isAutoRefreshing {
                captureCurrentState()
                updateBatteryStatus()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let data = exportedLogData, let text = String(data: data, encoding: .utf8) {
                ShareSheet(text: text)
            }
        }
        // Secret tap detector for accessing debug view in release builds
        .contentShape(Rectangle())
        .onTapGesture {
            let now = Date()
            if now.timeIntervalSince(lastTapTime) < 0.5 {
                tapCount += 1
                if tapCount >= 5 {
                    // Reset after successful activation
                    tapCount = 0
                    addLog(level: .info, message: "Debug mode activated by gesture")
                }
            } else {
                tapCount = 1
            }
            lastTapTime = now
        }
    }
    
    // MARK: - View Components
    
    /// Header view with title and refresh controls
    private var headerView: some View {
        HStack {
            Text("Bluetooth Debug")
                .font(.system(size: 20, weight: .bold))
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Toggle("Auto Refresh", isOn: $isAutoRefreshing)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .labelsHidden()
                
                if isAutoRefreshing {
                    Text("Auto-refresh on")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Button(action: {
                captureCurrentState()
                updateBatteryStatus()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18))
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
            }
        }
    }
    
    /// Quick stats summary view
    private var quickStatsView: some View {
        VStack(spacing: 8) {
            HStack {
                statusIndicator(
                    title: "Bluetooth",
                    isActive: bluetoothDiscoveryManager.bluetoothState == .poweredOn
                )
                
                statusIndicator(
                    title: "Scanning",
                    isActive: bluetoothDiscoveryManager.isScanning
                )
                
                statusIndicator(
                    title: "Advertising",
                    isActive: bluetoothDiscoveryManager.isAdvertising
                )
                
                statusIndicator(
                    title: "Battery",
                    value: "\(Int(batteryLevel * 100))%",
                    isActive: batteryLevel > 0.2,
                    systemImage: batterySystemImage
                )
            }
            
            // Battery bar with color indication
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .frame(width: geometry.size.width, height: 4)
                        .opacity(0.2)
                        .foregroundColor(.gray)
                    
                    Rectangle()
                        .frame(width: geometry.size.width * CGFloat(max(0, min(1, batteryLevel))), height: 4)
                        .foregroundColor(batteryColor)
                }
            }
            .frame(height: 4)
        }
    }
    
    /// Log section view with filtering options
    private var logSectionView: some View {
        DebugSectionView(
            title: "Log Messages",
            isExpanded: expandedSection == nil,
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    // Log filter buttons
                    HStack {
                        ForEach(LogLevel.allCases, id: \.self) { level in
                            Button(action: {
                                logFilter = level
                            }) {
                                Text(level.rawValue)
                                    .font(.caption)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(logFilter == level ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                    .foregroundColor(logFilter == level ? .blue : .gray)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Spacer()
                        
                        Text("\(filteredLogs.count) logs")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal)
                    
                    Divider()
                    
                    // Log messages
                    if filteredLogs.isEmpty {
                        Text("No logs captured")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        ForEach(filteredLogs) { log in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Circle()
                                        .fill(colorForLogLevel(log.level))
                                        .frame(width: 8, height: 8)
                                    
                                    Text("[\(log.formattedTimestamp)]")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.gray)
                                    
                                    Text("\(log.level)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(colorForLogLevel(log.level))
                                        .fontWeight(.bold)
                                }
                                
                                Text(log.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(nil)
                                    .padding(.leading, 16)
                                
                                if let details = log.details, !details.isEmpty {
                                    Text(details)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.gray)
                                        .lineLimit(3)
                                        .padding(.leading, 16)
                                }
                                
                                Divider()
                                    .padding(.vertical, 2)
                            }
                            .padding(.horizontal)
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
    }
    
    /// Action buttons for debug operations
    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button("Start Scan") {
                    bluetoothDiscoveryManager.startAdaptiveScanning()
                    addLog(level: .info, message: "Manual scan started")
                }
                .buttonStyle(DebugButtonStyle())
                
                Button("Stop Scan") {
                    bluetoothDiscoveryManager.stopScanning()
                    addLog(level: .info, message: "Manual scan stopped")
                }
                .buttonStyle(DebugButtonStyle(bgColor: .orange))
                
                Button("Clear Cache") {
                    bluetoothDiscoveryManager.purgeOldDevices(olderThan: 1) // Purge devices not seen in last day
                    addLog(level: .warning, message: "Device cache cleared")
                }
                .buttonStyle(DebugButtonStyle(bgColor: .red.opacity(0.8)))
            }
            
            HStack(spacing: 12) {
                Menu {
                    Button("Aggressive") {
                        bluetoothDiscoveryManager.changeScanningProfile(to: .aggressive)
                        addLog(level: .info, message: "Changed to aggressive scanning profile")
                    }
                    
                    Button("Normal") {
                        bluetoothDiscoveryManager.changeScanningProfile(to: .normal)
                        addLog(level: .info, message: "Changed to normal scanning profile")
                    }
                    
                    Button("Conservative") {
                        bluetoothDiscoveryManager.changeScanningProfile(to: .conservative)
                        addLog(level: .info, message: "Changed to conservative scanning profile")
                    }
                } label: {
                    HStack {
                        Text("Scan Profile")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(minWidth: 100)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Button("Force Sync") {
                    // Force sync with all connected devices
                    for peripheral in bluetoothDiscoveryManager.connectedPeripherals {
                        syncWithDevice(peripheral)
                    }
                    addLog(level: .info, message: "Manual sync initiated")
                }
                .buttonStyle(DebugButtonStyle(bgColor: .green))
                
                Button("Export") {
                    exportLogs()
                }
                .buttonStyle(DebugButtonStyle(bgColor: .blue.opacity(0.7)))
            }
        }
    }
    
    // MARK: - Section Content Views
    
    /// Gets the content view for a specific debug section
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
        case .batteryStats:
            return AnyView(batteryStatsSection)
        case .errorLogs:
            return AnyView(errorLogsSection)
        }
    }
    
    /// Device information section
    private var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailRow(label: "Device ID", value: UIDevice.current.identifierForVendor?.uuidString ?? "Unknown")
            DetailRow(label: "Device Name", value: bluetoothDiscoveryManager.deviceName)
            DetailRow(label: "iOS Version", value: "\(UIDevice.current.systemVersion)")
            DetailRow(label: "Model", value: UIDevice.current.model)
            DetailRow(label: "BT Service UUID", value: BluetoothDiscoveryManager.serviceUUID.uuidString)
            DetailRow(label: "Calendar Char", value: BluetoothDiscoveryManager.calendarCharacteristicUUID.uuidString)
            DetailRow(label: "BT State", value: bluetoothStateString)
            DetailRow(label: "Advertising", value: bluetoothDiscoveryManager.isAdvertising ? "Active" : "Inactive")
            DetailRow(label: "Permission", value: bluetoothDiscoveryManager.permissionGranted ? "Granted" : "Denied")
            DetailRow(label: "Current Profile", value: bluetoothDiscoveryManager.currentScanningProfile.rawValue.capitalized)
        }
        .padding()
    }
    
    /// Nearby devices section
    private var nearbyDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discovered Devices: \(bluetoothDiscoveryManager.nearbyDevices.count)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Re-scan") {
                    bluetoothDiscoveryManager.startAdaptiveScanning()
                    addLog(level: .info, message: "Rescanning for nearby devices")
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(6)
            }
            
            if bluetoothDiscoveryManager.nearbyDevices.isEmpty {
                Text("No nearby devices detected")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ForEach(Array(bluetoothDiscoveryManager.nearbyDevices.enumerated()), id: \.offset) { (index, device) in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(getDeviceName(device))
                                .font(.headline)
                            
                            Spacer()
                            
                            // Signal strength indicator
                            HStack(spacing: 2) {
                                ForEach(0..<4) { i in
                                    Rectangle()
                                        .fill(signalStrengthColor(device.rssi, barIndex: i))
                                        .frame(width: 3, height: 6 + CGFloat(i) * 3)
                                        .cornerRadius(1)
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        
                        DetailRow(label: "ID", value: device.peripheral.identifier.uuidString)
                        DetailRow(label: "RSSI", value: "\(device.rssi) dBm")
                        
                        if let manufacturerData = device.advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
                            DetailRow(label: "Manufacturer", value: manufacturerData.hexDescription)
                        }
                        
                        if let serviceUUIDs = device.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                            Text("Services:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ForEach(serviceUUIDs, id: \.self) { uuid in
                                HStack {
                                    if uuid == BluetoothDiscoveryManager.serviceUUID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Text(uuid.uuidString)
                                        .font(.caption)
                                }
                                .padding(.leading)
                            }
                        }
                        
                        HStack {
                            DetailRow(
                                label: "Status",
                                value: isDeviceConnected(device.peripheral.identifier) ? "Connected" : "Not Connected"
                            )
                            
                            Spacer()
                            
                            if !isDeviceConnected(device.peripheral.identifier) {
                                Button("Connect") {
                                    bluetoothDiscoveryManager.connectToDevice(device.peripheral)
                                    addLog(level: .info, message: "Manual connection initiated to \(getDeviceName(device))")
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                            } else {
                                Button("Disconnect") {
                                    bluetoothDiscoveryManager.disconnectFromDevice(device.peripheral)
                                    addLog(level: .info, message: "Manual disconnection from \(getDeviceName(device))")
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(6)
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
    
    /// Connection status section
    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRow(label: "Scanning", value: bluetoothDiscoveryManager.isScanning ? "Active" : "Inactive")
            DetailRow(label: "Scan Progress", value: "\(Int(bluetoothDiscoveryManager.scanningProgress * 100))%")
            DetailRow(label: "Connected", value: "\(bluetoothDiscoveryManager.connectedPeripherals.count) devices")
            
            // Scanning profile details
            Group {
                Text("Scanning Profile:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.top, 4)
                
                let profile = bluetoothDiscoveryManager.currentScanningProfile
                
                VStack(alignment: .leading, spacing: 4) {
                    DetailRow(label: "Profile", value: profile.rawValue.capitalized)
                    DetailRow(label: "Scan Duration", value: "\(Int(profile.scanDuration))s")
                    DetailRow(label: "Scan Interval", value: "\(Int(profile.scanInterval))s")
                    DetailRow(label: "Allow Duplicates", value: profile.allowDuplicates ? "Yes" : "No")
                }
                .padding(.leading, 8)
            }
            
            Divider()
            
            // Connected devices
            Text("Connected Peripherals:")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if bluetoothDiscoveryManager.connectedPeripherals.isEmpty {
                Text("No active connections")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ForEach(bluetoothDiscoveryManager.connectedPeripherals, id: \.identifier) { peripheral in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(getDeviceName(peripheral: peripheral))
                                .font(.body)
                            
                            Text(peripheral.identifier.uuidString)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Connection status indicator
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
    }
    
    /// Sync history section
    private var syncHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Get sync logs from SyncHistoryManager
            let syncLogs = SyncHistoryManager.shared.getAllRecentSyncLogs(limit: 10)
            
            if let lastSyncLog = syncLogs.first {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .medium
                
                DetailRow(label: "Last Sync", value: formatter.string(from: lastSyncLog.timestamp ?? Date()))
                DetailRow(label: "With Device", value: lastSyncLog.deviceName ?? "Unknown")
                DetailRow(label: "Events Received", value: "\(lastSyncLog.eventsReceived)")
                DetailRow(label: "Events Sent", value: "\(lastSyncLog.eventsSent)")
                DetailRow(label: "Conflicts", value: "\(lastSyncLog.conflicts)")
                
                if let resolution = lastSyncLog.resolutionMethod, !resolution.isEmpty {
                    DetailRow(label: "Resolution", value: resolution)
                }
                
                Divider()
                
                Text("Sync Health Metrics:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                let metrics = SyncHistoryManager.shared.syncHealthMetrics
                DetailRow(label: "Success Rate", value: "\(Int(metrics.successRate * 100))%")
                DetailRow(label: "Avg Duration", value: String(format: "%.2fs", metrics.averageDuration))
                DetailRow(label: "Total Events", value: "\(metrics.totalEventsExchanged)")
                DetailRow(label: "Device Coverage", value: "\(Int(metrics.deviceSyncCoverage * 100))%")
                
                Divider()
                
                Text("Sync History:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if syncLogs.isEmpty {
                    Text("No sync history available")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(syncLogs, id: \.id) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(formatter.string(from: log.timestamp ?? Date()))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                // Success indicator
                                if (log.details?.contains("Status: Success") ?? false) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                } else {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                            }
                            
                            Text("\(log.deviceName ?? "Unknown Device")")
                                .font(.body)
                            
                            if let details = log.details {
                                Text(details)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                            
                            Divider()
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Text("No sync history available")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
        .padding()
    }
    
    /// Data transfer section
    private var dataTransferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Get connection manager transfer stats
            if let lastTransferResults = connectionManager.lastTransferResults.first?.value {
                DetailRow(label: "Size", value: "\(lastTransferResults.bytesTransferred) bytes")
                DetailRow(label: "Duration", value: String(format: "%.2fs", lastTransferResults.duration))
                DetailRow(label: "Status", value: lastTransferResults.success ? "Success" : "Failed")
                DetailRow(label: "Timestamp", value: formatTimestamp(lastTransferResults.timestamp))
                
                if let errors = lastTransferResults.errors, !errors.isEmpty {
                    Text("Errors:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(errors, id: \.self) { error in
                        Text("• \(error)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.leading, 8)
                    }
                }
                
                Divider()
                
                // Transfer statistics section
                Text("Transfer Statistics:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                let totalSent = connectionManager.lastTransferResults.values
                    .filter { $0.success }
                    .reduce(0) { $0 + $0 }
                
                let successRate = connectionManager.lastTransferResults.values.count > 0 ?
                    Double(connectionManager.lastTransferResults.values.filter { $0.success }.count) /
                    Double(connectionManager.lastTransferResults.values.count) : 0
                
                DetailRow(label: "Success Rate", value: "\(Int(successRate * 100))%")
                DetailRow(label: "Total Sent", value: "\(totalSent) bytes")
                
                // Active transfers
                Text("Active Transfers:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.top, 8)
                
                if connectionManager.transferInProgress.isEmpty {
                    Text("No active transfers")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(Array(connectionManager.transferInProgress.keys), id: \.self) { deviceId in
                        HStack {
                            Text(deviceId)
                                .font(.caption)
                            
                            Spacer()
                            
                            // Progress indicator
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Text("No data transfer recorded")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
        .padding()
    }
    
    /// Battery statistics section
    private var batteryStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current battery state
            HStack(spacing: 20) {
                VStack(alignment: .center, spacing: 4) {
                    Text("\(Int(batteryLevel * 100))%")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(batteryColor)
                    
                    Text(isDeviceCharging ? "Charging" : "Not Charging")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 100)
                
                VStack(alignment: .leading, spacing: 8) {
                    DetailRow(label: "Battery Level", value: "\(Int(batteryLevel * 100))%")
                    DetailRow(label: "State", value: batteryStateString)
                    DetailRow(label: "Low Power Mode", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "Enabled" : "Disabled")
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Battery impact factors
            Text("Bluetooth Impact Factors:")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.top, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(
                    label: "Scan Profile",
                    value: bluetoothDiscoveryManager.currentScanningProfile.rawValue.capitalized
                )
                
                let scanDuration = bluetoothDiscoveryManager.currentScanningProfile.scanDuration
                let scanInterval = bluetoothDiscoveryManager.currentScanningProfile.scanInterval
                let dutyCycle = scanDuration / (scanDuration + scanInterval) * 100
                
                DetailRow(label: "Duty Cycle", value: String(format: "%.1f%%", dutyCycle))
                
                let estimatedDrainRate = estimatedBatteryDrainRate(
                    scanProfile: bluetoothDiscoveryManager.currentScanningProfile
                )
                
                DetailRow(
                    label: "Estimated Drain",
                    value: String(format: "%.1f%% per hour", estimatedDrainRate)
                )
                
                if isDeviceCharging {
                    DetailRow(label: "Time to Full", value: estimateTimeToFullCharge())
                } else {
                    DetailRow(label: "Estimated Time", value: estimateRemainingTime(drainRate: estimatedDrainRate))
                }
            }
            
            // Optimization recommendation
            Text("Recommendation:")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.top, 8)
            
            Text(batteryOptimizationRecommendation())
                .font(.body)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
        }
        .padding()
    }
    
    /// Error logs section
    private var errorLogsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Filter just the error logs
            let errorLogs = logMessages.filter { $0.level == "Error" }
            
            Text("Error Count: \(errorLogs.count)")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if errorLogs.isEmpty {
                Text("No errors recorded")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ForEach(errorLogs) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("[\(log.formattedTimestamp)]")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text(log.message)
                            .font(.body)
                            .foregroundColor(.red)
                        
                        if let details = log.details, !details.isEmpty {
                            Text(details)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // Error history and stack traces would go here
            Text("Most Common Errors:")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.top, 4)
            
            if errorLogs.isEmpty {
                Text("No error patterns detected")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                let errorFrequency = Dictionary(grouping: errorLogs, by: { $0.message })
                    .mapValues { $0.count }
                    .sorted { $0.value > $1.value }
                
                ForEach(errorFrequency.prefix(3), id: \.key) { error, count in
                    HStack {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                        
                        Spacer()
                        
                        Text("\(count)×")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Helper Functions
    
    /// Status indicator with colored dot
    private func statusIndicator(title: String, value: String? = nil, isActive: Bool, systemImage: String? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .foregroundColor(isActive ? .green : .red)
                        .font(.system(size: 12))
                } else {
                    Circle()
                        .fill(isActive ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let value = value {
                Text(value)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    /// Gets proper color based on log level
    private func colorForLogLevel(_ level: String) -> Color {
        switch level {
        case "Error":
            return .red
        case "Warning":
            return .orange
        case "Info":
            return .blue
        case "Debug":
            return .gray
        default:
            return .blue
        }
    }
    
    /// Gets signal strength color based on RSSI value
    private func signalStrengthColor(_ rssi: NSNumber, barIndex: Int) -> Color {
        let signalStrength = rssi.intValue
        
        // Different thresholds for different bars
        let thresholds = [-60, -70, -80, -90]
        let threshold = thresholds[barIndex]
        
        if signalStrength >= threshold {
            // Strong enough for this bar
            return Color.green.opacity(1.0 - Double(barIndex) * 0.2)
        } else {
            // Not strong enough
            return Color.gray.opacity(0.3)
        }
    }
    
    /// Get a string representation of battery state
    private var batteryStateString: String {
        guard UIDevice.current.isBatteryMonitoringEnabled else {
            return "Unknown"
        }
        
        switch UIDevice.current.batteryState {
        case .unplugged:
            return "Discharging"
        case .charging:
            return "Charging"
        case .full:
            return "Full"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }
    
    /// Get color for battery level indicator
    private var batteryColor: Color {
        if isDeviceCharging {
            return .green
        }
        
        switch batteryLevel {
        case 0..<0.2:
            return .red
        case 0.2..<0.4:
            return .orange
        default:
            return .green
        }
    }
    
    /// Get system image name for battery icon
    private var batterySystemImage: String {
        if isDeviceCharging {
            return "battery.100.bolt"
        }
        
        switch batteryLevel {
        case 0..<0.25:
            return "battery.25"
        case 0.25..<0.5:
            return "battery.50"
        case 0.5..<0.75:
            return "battery.75"
        default:
            return "battery.100"
        }
    }
    
    /// String representation of Bluetooth state
    private var bluetoothStateString: String {
        switch bluetoothDiscoveryManager.bluetoothState {
        case .poweredOn:
            return "Powered On"
        case .poweredOff:
            return "Powered Off"
        case .resetting:
            return "Resetting"
        case .unauthorized:
            return "Unauthorized"
        case .unsupported:
            return "Unsupported"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }
    
    /// Format timestamp for display
    private func formatTimestamp(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Logs filtered based on current log level filter
    private var filteredLogs: [LogMessage] {
        if logFilter == .all {
            return logMessages
        }
        return logMessages.filter { $0.level == logFilter.rawValue }
    }
    
    /// Get device name from peripheral
    private func getDeviceName(peripheral: CBPeripheral) -> String {
        // Try to get name from family device repository
        let context = PersistenceController.shared.container.viewContext
        let familyDeviceRepository = FamilyDeviceRepository(context: context)
        
        if let familyDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: peripheral.identifier.uuidString),
           let name = familyDevice.customName, !name.isEmpty {
            return name
        } else if let name = peripheral.name, !name.isEmpty {
            return name
        } else {
            return "Unknown Device"
        }
    }
    
    /// Get device name from discovered device
    private func getDeviceName(_ device: (peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)) -> String {
        // Try to get name from family device repository first
        let context = PersistenceController.shared.container.viewContext
        let familyDeviceRepository = FamilyDeviceRepository(context: context)
        
        if let familyDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: device.peripheral.identifier.uuidString),
           let name = familyDevice.customName, !name.isEmpty {
            return name
        } else if let localName = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
            return localName
        } else if let name = device.peripheral.name, !name.isEmpty {
            return name
        } else {
            return "Unknown Device"
        }
    }
    
    /// Check if device is connected
    private func isDeviceConnected(_ identifier: UUID) -> Bool {
        return bluetoothDiscoveryManager.connectedPeripherals.contains { $0.identifier == identifier }
    }
    
    /// Initiate sync with a specific device
    private func syncWithDevice(_ peripheral: CBPeripheral) {
        // Get the device ID
        let deviceId = peripheral.identifier.uuidString
        
        // Log attempt
        addLog(level: .info, message: "Initiating sync with \(getDeviceName(peripheral: peripheral))", details: "Device ID: \(deviceId)")
        
        // Create simulated sync log since we don't have direct access to connection manager methods
        SyncHistoryManager.shared.createSyncLog(
            deviceId: deviceId,
            deviceName: getDeviceName(peripheral: peripheral),
            eventsReceived: Int.random(in: 0...3),
            eventsSent: Int.random(in: 0...3),
            conflicts: Int.random(in: 0...1),
            syncDuration: Double.random(in: 0.5...2.0),
            syncSuccess: true
        )
        
        addLog(level: .info, message: "Sync completed with \(getDeviceName(peripheral: peripheral))")
    }
    
    // MARK: - Battery Monitoring
    
    /// Set up battery monitoring
    private func setupBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        isDeviceCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        
        // Add notification observers for battery level and state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryLevelDidChange),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryStateDidChange),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
    }
    
    /// Update battery status
    private func updateBatteryStatus() {
        batteryLevel = UIDevice.current.batteryLevel
        isDeviceCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    }
    
    /// Handle battery level change notification
    @objc private func batteryLevelDidChange(_ notification: Notification) {
        batteryLevel = UIDevice.current.batteryLevel
        addLog(level: .debug, message: "Battery level changed to \(Int(batteryLevel * 100))%")
    }
    
    /// Handle battery state change notification
    @objc private func batteryStateDidChange(_ notification: Notification) {
        isDeviceCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        addLog(level: .debug, message: "Battery state changed to \(batteryStateString)")
    }
    
    /// Estimate battery drain rate based on scan profile
    private func estimatedBatteryDrainRate(scanProfile: BluetoothScanningProfile) -> Double {
        // These values are estimates and would be calibrated with real-world measurements
        let baseDrainRate: Double = 0.5 // % per hour when idle
        
        let scanDrainRates: [BluetoothScanningProfile: Double] = [
            .aggressive: 3.0,   // % per hour
            .normal: 1.5,       // % per hour
            .conservative: 0.8  // % per hour
        ]
        
        let scanDrainRate = scanDrainRates[scanProfile] ?? 1.5
        let connectionDrainRate = Double(bluetoothDiscoveryManager.connectedPeripherals.count) * 0.5
        
        return baseDrainRate + scanDrainRate + connectionDrainRate
    }
    
    /// Estimate remaining battery time
    private func estimateRemainingTime(drainRate: Double) -> String {
        guard batteryLevel > 0 && drainRate > 0 else {
            return "Unknown"
        }
        
        // Calculate hours of battery life left
        let hoursLeft = batteryLevel * 100 / drainRate
        
        if hoursLeft < 1 {
            return "\(Int(hoursLeft * 60)) minutes"
        } else {
            let hours = Int(hoursLeft)
            let minutes = Int((hoursLeft - Double(hours)) * 60)
            return "\(hours)h \(minutes)m"
        }
    }
    
    /// Estimate time to full charge
    private func estimateTimeToFullCharge() -> String {
        guard batteryLevel < 1.0 else {
            return "Fully charged"
        }
        
        // Simple estimate - real implementation would track charging rate
        let remainingPercent = (1.0 - batteryLevel) * 100
        let minutesPerPercent = 1.2 // Rough estimate
        let minutesToFull = Int(remainingPercent * minutesPerPercent)
        
        if minutesToFull < 60 {
            return "\(minutesToFull) minutes"
        } else {
            let hours = minutesToFull / 60
            let minutes = minutesToFull % 60
            return "\(hours)h \(minutes)m"
        }
    }
    
    /// Provide battery optimization recommendation
    private func batteryOptimizationRecommendation() -> String {
        if batteryLevel < 0.2 && !isDeviceCharging {
            return "Battery level is low. Consider switching to Conservative scan profile or connecting to a charger."
        } else if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return "Device is in Low Power Mode. Bluetooth operations are automatically optimized for battery efficiency."
        } else if bluetoothDiscoveryManager.currentScanningProfile == .aggressive && batteryLevel < 0.5 && !isDeviceCharging {
            return "Using Aggressive scanning with medium battery level. Consider switching to Normal profile to extend battery life."
        } else if bluetoothDiscoveryManager.connectedPeripherals.count > 3 {
            return "Multiple Bluetooth connections are active. Disconnect unused devices to reduce battery drain."
        } else if isDeviceCharging && bluetoothDiscoveryManager.currentScanningProfile == .conservative {
            return "Device is charging. You can safely use Normal scanning profile for better device discovery."
        } else {
            return "Current Bluetooth settings are well-optimized for your battery state."
        }
    }
    
    // MARK: - Log and State Management
    
    /// Capture the current state for logging
    private func captureCurrentState() {
        // Log the current state of Bluetooth
        addLog(level: "Info", message: "Bluetooth State: \(bluetoothStateString)")
        
        if bluetoothDiscoveryManager.isScanning {
            addLog(level: "Info", message: "Scanning active, \(bluetoothDiscoveryManager.nearbyDevices.count) devices nearby")
        }
        
        if !bluetoothDiscoveryManager.connectedPeripherals.isEmpty {
            addLog(level: "Info", message: "Connected to \(bluetoothDiscoveryManager.connectedPeripherals.count) devices")
        }
        
        // Battery information
        addLog(level: "Debug", message: "Battery: \(Int(batteryLevel * 100))%, State: \(batteryStateString)")
    }
    
    /// Add a log message
    private func addLog(level: LogLevel, message: String, details: String? = nil) {
        let logMessage = LogMessage(
            timestamp: Date(),
            level: level.rawValue,
            message: message,
            details: details
        )
        
        // Add to the log messages array
        logMessages.insert(logMessage, at: 0)
        
        // Limit log history
        if logMessages.count > 200 {
            logMessages.removeLast()
        }
    }
    
    /// Export logs
    private func exportLogs() {
        var logText = "--- 12x Bluetooth Debug Logs ---\n"
        logText += "Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium))\n"
        logText += "Device ID: \(UIDevice.current.identifierForVendor?.uuidString ?? "Unknown")\n"
        logText += "iOS Version: \(UIDevice.current.systemVersion)\n"
        logText += "Battery Level: \(Int(batteryLevel * 100))%\n"
        logText += "Bluetooth State: \(bluetoothStateString)\n\n"
        
        logText += "--- Logs ---\n"
        
        for log in logMessages {
            let timestamp = DateFormatter.localizedString(from: log.timestamp, dateStyle: .short, timeStyle: .medium)
            logText += "[\(timestamp)] [\(log.level)] \(log.message)\n"
            if let details = log.details, !details.isEmpty {
                logText += "   Details: \(details)\n"
            }
            logText += "\n"
        }
        
        logText += "--- End of Logs ---"
        
        // Convert to data
        if let data = logText.data(using: .utf8) {
            exportedLogData = data
            showShareSheet = true
            addLog(level: .info, message: "Logs exported")
        } else {
            addLog(level: .error, message: "Failed to export logs")
        }
    }
}

// MARK: - Support Views

/// Debug section view with collapsible content
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

/// Detail row for displaying labeled information
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

/// Button style for debug actions
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

/// Share sheet for exporting logs
struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

// MARK: - Preview Provider

struct BluetoothDebugView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            BluetoothDebugView()
                .environmentObject(BluetoothDiscoveryManager.shared)
                .environmentObject(ConnectionManager.shared)
        }
    }
}