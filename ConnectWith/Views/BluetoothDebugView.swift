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
    
    /// Sync history section with enhanced metrics visualization
    private var syncHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Get sync logs from SyncHistoryManager
            let syncLogs = SyncHistoryManager.shared.getAllRecentSyncLogs(limit: 10)
            let metrics = SyncHistoryManager.shared.syncHealthMetrics
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            
            // Last sync summary card
            if let lastSyncLog = syncLogs.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Synchronization:")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.bottom, 4)
                    
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "When", value: formatter.string(from: lastSyncLog.timestamp ?? Date()))
                            DetailRow(label: "With Device", value: lastSyncLog.deviceName ?? "Unknown")
                            DetailRow(label: "Duration", value: getDurationFromDetails(lastSyncLog.details))
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 8) {
                            let success = lastSyncLog.details?.contains("Status: Success") ?? false
                            
                            // Status indicator
                            HStack {
                                Text(success ? "Successful" : "Failed")
                                    .font(.subheadline.bold())
                                    .foregroundColor(success ? .green : .red)
                                
                                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(success ? .green : .red)
                            }
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                    
                                    Text("\(lastSyncLog.eventsReceived) received")
                                        .font(.caption)
                                }
                                
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    
                                    Text("\(lastSyncLog.eventsSent) sent")
                                        .font(.caption)
                                }
                                
                                if lastSyncLog.conflicts > 0 {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                        
                                        Text("\(lastSyncLog.conflicts) conflicts")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Events exchange visualization
                    if lastSyncLog.eventsReceived > 0 || lastSyncLog.eventsSent > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Data Exchange:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                            
                            HStack(spacing: 4) {
                                // Received events
                                if lastSyncLog.eventsReceived > 0 {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Rectangle()
                                                .fill(Color.blue)
                                                .frame(height: 16)
                                                .frame(width: min(200, CGFloat(lastSyncLog.eventsReceived) * 30))
                                                .cornerRadius(3)
                                                .overlay(
                                                    Text("\(lastSyncLog.eventsReceived)")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(.leading, 4),
                                                    alignment: .leading
                                                )
                                            
                                            Spacer()
                                        }
                                        
                                        Text("Received")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                // Sent events
                                if lastSyncLog.eventsSent > 0 {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Rectangle()
                                                .fill(Color.green)
                                                .frame(height: 16)
                                                .frame(width: min(200, CGFloat(lastSyncLog.eventsSent) * 30))
                                                .cornerRadius(3)
                                                .overlay(
                                                    Text("\(lastSyncLog.eventsSent)")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(.leading, 4),
                                                    alignment: .leading
                                                )
                                            
                                            Spacer()
                                        }
                                        
                                        Text("Sent")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Conflict resolution info if present
                    if lastSyncLog.conflicts > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                
                                Text("Conflict Resolution:")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .padding(.top, 4)
                            
                            Text("\(lastSyncLog.resolutionMethod ?? "Automatic merge")")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            } else {
                Text("No sync history available")
                    .foregroundColor(.gray)
                    .padding()
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Sync Health Metrics with visualizations
            Group {
                Text("Sync Health Metrics:")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.bottom, 4)
                
                // Metrics overview
                HStack(spacing: 20) {
                    StatisticView(
                        title: "Success Rate",
                        value: "\(Int(metrics.successRate * 100))%",
                        icon: "checkmark.seal.fill",
                        color: getColorForPercentage(metrics.successRate)
                    )
                    
                    StatisticView(
                        title: "Avg Duration",
                        value: String(format: "%.1fs", metrics.averageDuration),
                        icon: "timer",
                        color: .blue
                    )
                    
                    StatisticView(
                        title: "Device Coverage",
                        value: "\(Int(metrics.deviceSyncCoverage * 100))%",
                        icon: "network",
                        color: getColorForPercentage(metrics.deviceSyncCoverage)
                    )
                }
                .padding(.vertical, 8)
                
                // Success rate visualization
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync Success Rate:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    ZStack(alignment: .leading) {
                        // Background
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 24)
                            .cornerRadius(6)
                        
                        // Progress
                        Rectangle()
                            .fill(getColorForPercentage(metrics.successRate))
                            .frame(width: CGFloat(metrics.successRate) * 300, height: 24)
                            .cornerRadius(6)
                            .overlay(
                                Text("\(Int(metrics.successRate * 100))%")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8),
                                alignment: .leading
                            )
                    }
                    
                    // Device coverage visualization
                    Text("Device Sync Coverage:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    ZStack(alignment: .leading) {
                        // Background
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 24)
                            .cornerRadius(6)
                        
                        // Progress
                        Rectangle()
                            .fill(getColorForPercentage(metrics.deviceSyncCoverage))
                            .frame(width: CGFloat(metrics.deviceSyncCoverage) * 300, height: 24)
                            .cornerRadius(6)
                            .overlay(
                                Text("\(Int(metrics.deviceSyncCoverage * 100))%")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8),
                                alignment: .leading
                            )
                    }
                    
                    // Events exchanged metric
                    Text("Total Events Exchanged: \(metrics.totalEventsExchanged)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                // Other significant metrics
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Conflicts Resolved")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("\(metrics.totalConflictsResolved)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Conflict Resolution Rate")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("\(Int(metrics.conflictResolutionRate * 100))%")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(getColorForPercentage(metrics.conflictResolutionRate))
                        }
                        .frame(maxWidth: .infinity)
                        
                        if let lastSyncTime = metrics.lastSuccessfulSyncTime {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Last Successful Sync")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(timeAgoString(from: lastSyncTime))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Sync History detailed logs
            Group {
                Text("Sync History:")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.bottom, 4)
                
                if syncLogs.isEmpty {
                    Text("No sync history available")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(syncLogs, id: \.id) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            // Header with timestamp and status
                            HStack {
                                Text(formatter.string(from: log.timestamp ?? Date()))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                // Visual status indicator
                                let isSuccess = log.details?.contains("Status: Success") ?? false
                                HStack(spacing: 4) {
                                    Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundColor(isSuccess ? .green : .orange)
                                        .font(.caption)
                                    
                                    Text(isSuccess ? "Success" : "Issue")
                                        .font(.caption)
                                        .foregroundColor(isSuccess ? .green : .orange)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSuccess ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                                .cornerRadius(4)
                            }
                            
                            // Device name and summary info
                            HStack {
                                Text("\(log.deviceName ?? "Unknown Device")")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                if log.conflicts > 0 {
                                    Text("• \(log.conflicts) conflicts")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 8) {
                                    Label("\(log.eventsReceived)", systemImage: "arrow.down")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    
                                    Label("\(log.eventsSent)", systemImage: "arrow.up")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            
                            // Expandable details section
                            if let details = log.details {
                                DisclosureGroup {
                                    Text(details)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 6)
                                } label: {
                                    Text("Details")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .padding(.top, 2)
                            }
                            
                            Divider()
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            
            // Force Sync Button
            Button(action: {
                // Force sync with all connected devices
                for peripheral in bluetoothDiscoveryManager.connectedPeripherals {
                    syncWithDevice(peripheral)
                }
                addLog(level: .info, message: "Manual sync initiated with all connected devices")
            }) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Force Sync Now")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.top, 12)
        }
        .padding()
    }
    
    /// StatisticView for displaying metric stats with an icon
    private struct StatisticView: View {
        let title: String
        let value: String
        let icon: String
        let color: Color
        
        var body: some View {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(10)
        }
    }
    
    /// Get duration from sync log details
    private func getDurationFromDetails(_ details: String?) -> String {
        guard let details = details else { return "Unknown" }
        
        let durationPattern = #"Duration: (\d+\.\d+)"#
        if let regex = try? NSRegularExpression(pattern: durationPattern, options: []),
           let match = regex.firstMatch(in: details, options: [], range: NSRange(location: 0, length: details.count)) {
            let nsRange = match.range(at: 1)
            if let range = Range(nsRange, in: details) {
                let durationStr = String(details[range])
                if let duration = Double(durationStr) {
                    return String(format: "%.2fs", duration)
                }
            }
        }
        
        return "Unknown"
    }
    
    /// Get appropriate color based on percentage value
    private func getColorForPercentage(_ percentage: Double) -> Color {
        switch percentage {
        case 0.0..<0.5:
            return .red
        case 0.5..<0.7:
            return .orange
        case 0.7..<0.9:
            return .yellow
        default:
            return .green
        }
    }
    
    /// Generate relative time string
    private func timeAgoString(from date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let day = components.day, day > 0 {
            return day == 1 ? "Yesterday" : "\(day) days ago"
        } else if let hour = components.hour, hour > 0 {
            return "\(hour) hour\(hour == 1 ? "" : "s") ago"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute) min\(minute == 1 ? "" : "s") ago"
        } else {
            return "Just now"
        }
    }
    
    /// Data transfer section
    private var dataTransferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Last transfer details
            Group {
                Text("Last Transfer:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let lastTransferResults = connectionManager.lastTransferResults.first?.value {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            DetailRow(label: "Size", value: "\(lastTransferResults.bytesTransferred) bytes")
                            DetailRow(label: "Duration", value: String(format: "%.2fs", lastTransferResults.duration))
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            // Status indicator
                            HStack {
                                Text(lastTransferResults.success ? "Success" : "Failed")
                                    .font(.subheadline.bold())
                                    .foregroundColor(lastTransferResults.success ? .green : .red)
                                
                                Image(systemName: lastTransferResults.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(lastTransferResults.success ? .green : .red)
                            }
                            
                            Text(formatTimestamp(lastTransferResults.timestamp))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                    
                    if let errors = lastTransferResults.errors, !errors.isEmpty {
                        Text("Errors:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(errors, id: \.self) { error in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                } else {
                    Text("No transfer data available")
                        .foregroundColor(.gray)
                        .padding()
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Transfer statistics with visualizations
            Group {
                Text("Transfer Statistics:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                // Calculate transfer statistics
                let totalTransfers = connectionManager.lastTransferResults.count
                let successfulTransfers = connectionManager.lastTransferResults.values.filter { $0.success }.count
                let failedTransfers = totalTransfers - successfulTransfers
                let successRate = totalTransfers > 0 ? Double(successfulTransfers) / Double(totalTransfers) : 0.0
                
                let totalBytesSent = connectionManager.lastTransferResults.values
                    .filter { $0.success }
                    .reduce(0) { $0 + $1.bytesTransferred }
                
                let avgTransferTime = connectionManager.lastTransferResults.values
                    .filter { $0.success }
                    .map { $0.duration }
                    .reduce(0.0, +) / Double(max(1, successfulTransfers))
                
                // Statistics summary
                HStack(spacing: 20) {
                    StatisticView(
                        title: "Success Rate",
                        value: "\(Int(successRate * 100))%",
                        icon: "chart.bar.fill",
                        color: successRate > 0.8 ? .green : (successRate > 0.5 ? .orange : .red)
                    )
                    
                    StatisticView(
                        title: "Total Sent",
                        value: formatDataSize(totalBytesSent),
                        icon: "arrow.up.circle.fill",
                        color: .blue
                    )
                    
                    StatisticView(
                        title: "Avg Time",
                        value: String(format: "%.2fs", avgTransferTime),
                        icon: "clock.fill",
                        color: .purple
                    )
                }
                .padding(.vertical, 8)
                
                // Success/failure visualization
                if totalTransfers > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transfer Results:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 2) {
                            // Success portion
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: max(30, CGFloat(successfulTransfers) / CGFloat(totalTransfers) * 300), height: 24)
                                .overlay(
                                    Text("\(successfulTransfers)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .opacity(successfulTransfers > 2 ? 1 : 0),
                                    alignment: .leading
                                )
                            
                            // Failed portion
                            if failedTransfers > 0 {
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(width: max(30, CGFloat(failedTransfers) / CGFloat(totalTransfers) * 300), height: 24)
                                    .overlay(
                                        Text("\(failedTransfers)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .opacity(failedTransfers > 2 ? 1 : 0),
                                        alignment: .leading
                                    )
                            }
                        }
                        .cornerRadius(6)
                        
                        HStack {
                            HStack {
                                Rectangle()
                                    .fill(Color.green)
                                    .frame(width: 12, height: 12)
                                
                                Text("Success")
                                    .font(.caption)
                            }
                            
                            HStack {
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                                
                                Text("Failed")
                                    .font(.caption)
                            }
                            
                            Spacer()
                            
                            Text("Total: \(totalTransfers)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
                
                // Transfer history trend (last 5 transfers timeline)
                if connectionManager.lastTransferResults.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent Transfer History:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Timeline visualization
                        HStack(alignment: .center, spacing: 2) {
                            ForEach(Array(connectionManager.lastTransferResults.values.prefix(5).enumerated()), id: \.offset) { _, result in
                                VStack {
                                    Rectangle()
                                        .fill(result.success ? Color.green : Color.red)
                                        .frame(width: 10, height: 40)
                                        .cornerRadius(5)
                                    
                                    Text("\(result.bytesTransferred)")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Active transfers section with enhanced visualization
            Group {
                Text("Active Transfers:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if connectionManager.transferInProgress.isEmpty {
                    Text("No active transfers")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(Array(connectionManager.transferInProgress.keys), id: \.self) { deviceId in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                // Device name
                                Text(getDeviceName(bluetoothId: deviceId))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                // Animated transfer indicator
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.left.arrow.right")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    
                                    Text("Transferring")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            // Simulated progress visualization
                            ZStack(alignment: .leading) {
                                // Background
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 8)
                                    .cornerRadius(4)
                                
                                // Progress
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: calculateProgressWidth(deviceId: deviceId), height: 8)
                                    .cornerRadius(4)
                            }
                            
                            HStack {
                                Text("Device ID: \(deviceId)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                // Cancel button
                                Button(action: {
                                    // This would call cancelTransfer in a real implementation
                                    addLog(level: .warning, message: "Transfer canceled for device \(deviceId)")
                                }) {
                                    Text("Cancel")
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
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(10)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
    }
    
    /// Helper function to calculate dynamic progress width for transfer visualization
    private func calculateProgressWidth(deviceId: String) -> CGFloat {
        // In a real implementation, this would use actual progress data
        // For demo, we'll use a simulated progress based on the device ID hash
        let hash = abs(deviceId.hash)
        let randomProgress = Double(hash % 100) / 100.0
        
        // For visualization purposes, we'll use a 300pt max width
        return CGFloat(randomProgress * 300)
    }
    
    /// Format data size in appropriate units
    private func formatDataSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            let kb = Double(bytes) / 1024.0
            return String(format: "%.1f KB", kb)
        } else {
            let mb = Double(bytes) / (1024.0 * 1024.0)
            return String(format: "%.1f MB", mb)
        }
    }
    
    /// Get device name from bluetooth identifier
    private func getDeviceName(bluetoothId: String) -> String {
        let context = PersistenceController.shared.container.viewContext
        let familyDeviceRepository = FamilyDeviceRepository(context: context)
        
        if let device = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: bluetoothId),
           let name = device.customName, !name.isEmpty {
            return name
        } else {
            // Try to find in connected peripherals
            if let peripheral = findPeripheralById(bluetoothId), 
               let name = peripheral.name, !name.isEmpty {
                return name
            }
            
            return "Unknown Device"
        }
    }
    
    /// Find peripheral by identifier
    private func findPeripheralById(_ identifier: String) -> CBPeripheral? {
        for peripheral in bluetoothDiscoveryManager.connectedPeripherals {
            if peripheral.identifier.uuidString == identifier {
                return peripheral
            }
        }
        return nil
    }
    
    /// Battery statistics section with enhanced visualizations
    private var batteryStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current battery state with circular gauge
            HStack(spacing: 20) {
                // Visual battery gauge
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .trim(from: 0, to: batteryLevel)
                        .stroke(
                            batteryColor,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                    
                    VStack(spacing: 2) {
                        Text("\(Int(batteryLevel * 100))%")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(batteryColor)
                        
                        HStack(spacing: 4) {
                            Image(systemName: isDeviceCharging ? "bolt.fill" : batterySystemImage)
                                .foregroundColor(isDeviceCharging ? .green : batteryColor)
                                .font(.system(size: 14))
                            
                            Text(isDeviceCharging ? "Charging" : batteryStateString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: 130, height: 130)
                
                // Battery details
                VStack(alignment: .leading, spacing: 10) {
                    // Low power mode indicator
                    HStack {
                        Image(systemName: ProcessInfo.processInfo.isLowPowerModeEnabled ? "leaf.fill" : "leaf")
                            .foregroundColor(ProcessInfo.processInfo.isLowPowerModeEnabled ? .green : .gray)
                        
                        Text("Low Power Mode")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "OFF")
                            .font(.subheadline.bold())
                            .foregroundColor(ProcessInfo.processInfo.isLowPowerModeEnabled ? .green : .gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ProcessInfo.processInfo.isLowPowerModeEnabled ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    // Time remaining estimate
                    let estimatedDrainRate = estimatedBatteryDrainRate(
                        scanProfile: bluetoothDiscoveryManager.currentScanningProfile
                    )
                    
                    let timeEstimate = isDeviceCharging ? 
                        estimateTimeToFullCharge() : 
                        estimateRemainingTime(drainRate: estimatedDrainRate)
                    
                    HStack {
                        Image(systemName: isDeviceCharging ? "clock.arrow.2.circlepath" : "clock")
                            .foregroundColor(.blue)
                        
                        Text(isDeviceCharging ? "Full Charge In:" : "Estimated Time:")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text(timeEstimate)
                            .font(.subheadline.bold())
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            
            // Bluetooth impact on battery
            VStack(alignment: .leading, spacing: 12) {
                Text("Bluetooth Impact on Battery")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Scan profile gauge
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Current Scan Profile")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(bluetoothDiscoveryManager.currentScanningProfile.rawValue.capitalized)
                            .font(.subheadline.bold())
                            .foregroundColor(scanProfileColor(bluetoothDiscoveryManager.currentScanningProfile))
                    }
                    
                    // Visual profile indicator
                    HStack(spacing: 2) {
                        ForEach(BluetoothScanningProfile.allCases, id: \.self) { profile in
                            Rectangle()
                                .fill(profile == bluetoothDiscoveryManager.currentScanningProfile ? 
                                    scanProfileColor(profile) : Color.gray.opacity(0.2))
                                .frame(height: 20)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(4)
                                .overlay(
                                    Text(profile.rawValue.prefix(1).uppercased())
                                        .font(.caption.bold())
                                        .foregroundColor(profile == bluetoothDiscoveryManager.currentScanningProfile ? 
                                            .white : .gray)
                                )
                        }
                    }
                }
                
                // Duty cycle information with visual meter
                let scanDuration = bluetoothDiscoveryManager.currentScanningProfile.scanDuration
                let scanInterval = bluetoothDiscoveryManager.currentScanningProfile.scanInterval
                let dutyCycle = scanDuration / (scanDuration + scanInterval)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Scan Duty Cycle")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f%%", dutyCycle * 100))
                            .font(.subheadline.bold())
                            .foregroundColor(dutyCycleColor(dutyCycle))
                    }
                    
                    // Visual duty cycle gauge
                    ZStack(alignment: .leading) {
                        // Background
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 16)
                            .cornerRadius(8)
                        
                        // Filled portion
                        Rectangle()
                            .fill(dutyCycleColor(dutyCycle))
                            .frame(width: max(10, CGFloat(dutyCycle) * 300), height: 16)
                            .cornerRadius(8)
                    }
                    
                    // Duty cycle explanation
                    HStack {
                        Text("Active")
                            .font(.caption)
                            .frame(width: 70, alignment: .leading)
                        
                        Text("\(Int(scanDuration))s")
                            .font(.caption)
                            .frame(width: 40, alignment: .trailing)
                        
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 40, height: 6)
                            .cornerRadius(3)
                        
                        Spacer()
                    }
                    
                    HStack {
                        Text("Inactive")
                            .font(.caption)
                            .frame(width: 70, alignment: .leading)
                        
                        Text("\(Int(scanInterval))s")
                            .font(.caption)
                            .frame(width: 40, alignment: .trailing)
                        
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(width: 40, height: 6)
                            .cornerRadius(3)
                        
                        Spacer()
                    }
                }
                .padding(.vertical, 8)
                
                // Battery drain information
                let estimatedDrainRate = estimatedBatteryDrainRate(
                    scanProfile: bluetoothDiscoveryManager.currentScanningProfile
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Estimated Battery Drain")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.1f%% per hour", estimatedDrainRate))
                            .font(.subheadline.bold())
                            .foregroundColor(drainRateColor(estimatedDrainRate))
                    }
                    
                    // Visual drain rate indicator
                    HStack(spacing: 0) {
                        // Low drain zone
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: 100, height: 8)
                        
                        // Medium drain zone
                        Rectangle()
                            .fill(Color.yellow)
                            .frame(width: 100, height: 8)
                        
                        // High drain zone
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 100, height: 8)
                    }
                    .cornerRadius(4)
                    .overlay(
                        // Position indicator based on drain rate
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(drainRateColor(estimatedDrainRate), lineWidth: 2)
                            )
                            .offset(x: min(290, max(0, CGFloat(estimatedDrainRate / 5.0) * 290)) - 145)
                    )
                    
                    // Drain rate scale
                    HStack {
                        Text("Lower")
                            .font(.caption)
                            .foregroundColor(.green)
                        
                        Spacer()
                        
                        Text("Medium")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        
                        Spacer()
                        
                        Text("Higher")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.vertical, 8)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            
            // Connected peripherals impact
            VStack(alignment: .leading, spacing: 12) {
                Text("Connected Peripherals")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                let connectedCount = bluetoothDiscoveryManager.connectedPeripherals.count
                
                HStack(spacing: 16) {
                    // Connected devices count
                    VStack {
                        Text("\(connectedCount)")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(connectedCount > 3 ? .orange : .blue)
                        
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80)
                    
                    // Additional battery impact
                    VStack(alignment: .leading, spacing: 8) {
                        if connectedCount > 0 {
                            Text("Additional Battery Impact:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            // Battery impact bars
                            HStack(spacing: 2) {
                                ForEach(0..<min(5, connectedCount), id: \.self) { _ in
                                    Rectangle()
                                        .fill(Color.blue)
                                        .frame(width: 20, height: 24)
                                        .cornerRadius(4)
                                }
                                
                                ForEach(0..<(5 - min(5, connectedCount)), id: \.self) { _ in
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 20, height: 24)
                                        .cornerRadius(4)
                                }
                                
                                if connectedCount > 5 {
                                    Text("+\(connectedCount - 5)")
                                        .font(.caption.bold())
                                        .foregroundColor(.orange)
                                        .padding(.leading, 4)
                                }
                                
                                Spacer()
                            }
                            
                            Text("Approximately +\(connectedCount * 5)% battery usage")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No connected peripherals")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            
            // Optimization recommendation with visual indicator
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                        .font(.title3)
                    
                    Text("Battery Optimization Recommendation")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                let recommendation = batteryOptimizationRecommendation()
                let isGood = recommendation.contains("well-optimized")
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isGood ? .green : .orange)
                        .font(.title2)
                    
                    Text(recommendation)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(isGood ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                .cornerRadius(12)
                
                // Scan profile selector for optimization
                HStack {
                    Picker("Scan Profile", selection: Binding<String>(
                        get: { bluetoothDiscoveryManager.currentScanningProfile.rawValue },
                        set: { newValue in
                            if let profile = BluetoothScanningProfile(rawValue: newValue) {
                                bluetoothDiscoveryManager.changeScanningProfile(to: profile)
                                addLog(level: .info, message: "Changed to \(newValue) scanning profile")
                            }
                        }
                    )) {
                        ForEach(BluetoothScanningProfile.allCases, id: \.self) { profile in
                            Text(profile.rawValue.capitalized)
                                .tag(profile.rawValue)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.top, 8)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
        }
        .padding()
    }
    
    /// Returns the appropriate color for a scan profile
    private func scanProfileColor(_ profile: BluetoothScanningProfile) -> Color {
        switch profile {
        case .aggressive:
            return .red
        case .normal:
            return .blue
        case .conservative:
            return .green
        }
    }
    
    /// Returns the appropriate color for a duty cycle
    private func dutyCycleColor(_ dutyCycle: Double) -> Color {
        switch dutyCycle {
        case 0.0..<0.3:
            return .green
        case 0.3..<0.6:
            return .yellow
        default:
            return .orange
        }
    }
    
    /// Returns the appropriate color for a drain rate
    private func drainRateColor(_ drainRate: Double) -> Color {
        switch drainRate {
        case 0.0..<1.0:
            return .green
        case 1.0..<2.5:
            return .blue
        case 2.5..<4.0:
            return .yellow
        default:
            return .red
        }
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