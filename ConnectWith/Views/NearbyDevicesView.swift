import SwiftUI
import CoreBluetooth
import CoreData
import OSLog
import Combine

struct NearbyDevicesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var bluetoothManager: BluetoothDiscoveryManager
    
    @StateObject private var deviceManager = DeviceManager.shared
    @State private var showRenameSheet = false
    @State private var showDeleteConfirmation = false
    @State private var newDeviceName = ""
    @State private var selectedFamilyDevice: FamilyDevice?
    @State private var selectedBluetoothDevice: BluetoothDevice?
    @State private var navigateToDeviceDetail = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        NavigationView {
            ZStack {
                if deviceManager.familyDevices.isEmpty {
                    emptyStateView
                } else {
                    deviceListView
                }
                
                // Loading overlay when scanning
                if bluetoothManager.isScanning || deviceManager.isRefreshing {
                    scanningOverlay
                }
            }
            .navigationTitle("Family Devices")
            .navigationBarItems(
                leading: Button("Back") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button(action: {
                    refreshDevices()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            )
            .onAppear {
                // Start scanning when view appears
                if !bluetoothManager.isScanning {
                    refreshDevices()
                }
            }
            .sheet(isPresented: $showRenameSheet) {
                renameDeviceSheet
            }
            .alert("Remove Device", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Remove", role: .destructive) {
                    if let device = selectedFamilyDevice {
                        deviceManager.deleteDevice(device: device)
                    }
                }
            } message: {
                Text("Are you sure you want to remove this device? You'll need to discover it again to reconnect.")
            }
            .background(
                NavigationLink(
                    destination: selectedBluetoothDevice.map { device in
                        DeviceDetailView(
                            device: device,
                            isLocalDevice: isLocalDevice(device)
                        )
                    },
                    isActive: $navigateToDeviceDetail
                ) {
                    EmptyView()
                }
            )
        }
    }
    
    // MARK: - View Components
    
    var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "wifi.slash")
                .font(.system(size: 70))
                .foregroundColor(.gray)
            
            Text("No Family Devices Found")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
            
            Text("Tap the refresh button to search for family members' devices")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                refreshDevices()
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Scan for Devices")
                }
                .padding()
                .foregroundColor(.white)
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding(.top)
            
            Spacer()
        }
    }
    
    var deviceListView: some View {
        List {
            Section(header: Text("Family Devices")) {
                ForEach(deviceManager.familyDevices, id: \.id) { familyDevice in
                    FamilyDeviceRow(
                        device: familyDevice,
                        bluetoothDevice: deviceManager.findBluetoothDevice(for: familyDevice),
                        isLocalDevice: familyDevice.isLocalDevice,
                        connectionStatus: deviceManager.getConnectionStatus(device: familyDevice)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let bluetoothDevice = deviceManager.findBluetoothDevice(for: familyDevice) {
                            selectedBluetoothDevice = bluetoothDevice
                            navigateToDeviceDetail = true
                        }
                    }
                    .contextMenu {
                        if !familyDevice.isLocalDevice {
                            Button(action: {
                                selectedFamilyDevice = familyDevice
                                newDeviceName = familyDevice.customName ?? "Family Member"
                                showRenameSheet = true
                            }) {
                                Label("Rename", systemImage: "pencil")
                            }
                            
                            Button(action: {
                                connectToDevice(familyDevice)
                            }) {
                                Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .disabled(deviceManager.isConnectionInProgress(device: familyDevice))
                            
                            Button(action: {
                                selectedFamilyDevice = familyDevice
                                showDeleteConfirmation = true
                            }) {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        
                        if let bluetoothDevice = deviceManager.findBluetoothDevice(for: familyDevice) {
                            Button(action: {
                                selectedBluetoothDevice = bluetoothDevice
                                navigateToDeviceDetail = true
                            }) {
                                Label("View Details", systemImage: "info.circle")
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Device Management")) {
                Button(action: {
                    refreshDevices()
                }) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Refresh Device List")
                    }
                }
                
                Button(action: {
                    deviceManager.purgeOldDevices()
                    deviceManager.purgeOldSyncLogs()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear Old Device Data")
                    }
                }
                .foregroundColor(.red)
            }
        }
        .refreshable {
            refreshDevices()
        }
    }
    
    var scanningOverlay: some View {
        VStack {
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                            .frame(width: 100, height: 100)
                        
                        Circle()
                            .trim(from: 0, to: bluetoothManager.scanningProgress)
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear, value: bluetoothManager.scanningProgress)
                        
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                    }
                    
                    Text("Scanning for family devices...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(20)
            }
        }
    }
    
    var renameDeviceSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Rename Family Device")) {
                    TextField("Device Name", text: $newDeviceName)
                        .autocapitalization(.words)
                    
                    if let device = selectedFamilyDevice {
                        Text("Device ID: \(device.bluetoothIdentifier.prefix(8))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Save") {
                        if let device = selectedFamilyDevice {
                            deviceManager.renameDevice(device: device, name: newDeviceName)
                            showRenameSheet = false
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Rename Device")
            .navigationBarItems(trailing: Button("Cancel") {
                showRenameSheet = false
            })
        }
    }
    
    // MARK: - Helper Functions
    
    private func refreshDevices() {
        deviceManager.refreshDevices()
    }
    
    private func isLocalDevice(_ device: BluetoothDevice) -> Bool {
        // Check if this device is the user's local device
        let localId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        return device.identifier == localId
    }
    
    private func connectToDevice(_ device: FamilyDevice) {
        deviceManager.connectToDevice(device: device)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        Logger.bluetooth.error("Connection failed: \(error.localizedDescription)")
                    }
                },
                receiveValue: { success in
                    Logger.bluetooth.info("Connection to \(device.customName ?? "Unknown") \(success ? "succeeded" : "failed")")
                }
            )
            .store(in: &cancellables)
    }
}

struct FamilyDeviceRow: View {
    let device: FamilyDevice
    let bluetoothDevice: BluetoothDevice?
    let isLocalDevice: Bool
    let connectionStatus: ConnectionManager.ConnectionStatus
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Device icon with better contrast
            ZStack {
                Circle()
                    .fill(deviceColor)
                    .frame(width: 44, height: 44)
                
                Image(systemName: deviceIcon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.customName ?? "Unknown Device")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if isLocalDevice {
                        Text("This Device")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                
                if let lastSync = device.lastSyncTimestamp {
                    Text("Last sync: \(formattedDate(lastSync))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let lastSeen = bluetoothDevice?.lastSeen {
                    Text("Last seen: \(formattedDate(lastSeen))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
    
    private var deviceIcon: String {
        if isLocalDevice {
            return "iphone.homebutton"
        } else if bluetoothDevice?.supports12xSync == true {
            return "iphone.radiowaves.left.and.right"
        } else {
            return "iphone"
        }
    }
    
    private var deviceColor: Color {
        if isLocalDevice {
            return .blue
        } else if connectionStatus == .connected {
            return .green
        } else if bluetoothDevice?.supports12xSync == true || device.lastSyncTimestamp != nil {
            return .orange
        } else {
            return .gray
        }
    }
    
    private var statusText: String {
        if isLocalDevice {
            return "Local Device"
        } else if connectionStatus == .connected {
            return "Connected"
        } else if bluetoothDevice?.isRecentlyActive == true {
            return "Recently Active"
        } else if device.lastSyncTimestamp != nil {
            return "Synced Previously"
        } else {
            return "Not Connected"
        }
    }
    
    private var statusColor: Color {
        if isLocalDevice {
            return .blue
        } else if connectionStatus == .connected {
            return .green
        } else if bluetoothDevice?.isRecentlyActive == true {
            return .orange
        } else {
            return .gray
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NearbyDevicesView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        .environmentObject(BluetoothDiscoveryManager.shared)
}