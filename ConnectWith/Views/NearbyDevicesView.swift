import SwiftUI
import CoreBluetooth
import CoreData
import OSLog

struct NearbyDevicesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var bluetoothManager: BluetoothDiscoveryManager
    
    @State private var isRefreshing = false
    @State private var showRenameSheet = false
    @State private var newDeviceName = ""
    @State private var selectedDevice: BluetoothDevice?
    @State private var navigateToDeviceDetail = false
    
    @FetchRequest(
        entity: NSEntityDescription.entity(forEntityName: "BluetoothDevice", in: PersistenceController.shared.container.viewContext)!,
        sortDescriptors: [NSSortDescriptor(key: "lastSeen", ascending: false)],
        animation: .default)
    private var devices: FetchedResults<BluetoothDevice>
    
    var body: some View {
        NavigationView {
            ZStack {
                if devices.isEmpty {
                    emptyStateView
                } else {
                    deviceListView
                }
                
                // Loading overlay when scanning
                if bluetoothManager.isScanning {
                    scanningOverlay
                }
            }
            .navigationTitle("Family Devices")
            .navigationBarItems(
                leading: Button("Back") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button(action: {
                    startScan()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            )
            .onAppear {
                // Start scanning when view appears
                if !bluetoothManager.isScanning {
                    startScan()
                }
            }
            .sheet(isPresented: $showRenameSheet) {
                renameDeviceSheet
            }
            .background(
                NavigationLink(
                    destination: selectedDevice.map { device in
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
                startScan()
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
                ForEach(devices, id: \.identifier) { device in
                    DeviceRow(device: device, isLocalDevice: isLocalDevice(device))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedDevice = device
                            navigateToDeviceDetail = true
                        }
                        .contextMenu {
                            Button(action: {
                                selectedDevice = device
                                newDeviceName = device.deviceName ?? "Family Member"
                                showRenameSheet = true
                            }) {
                                Label("Rename", systemImage: "pencil")
                            }
                            
                            Button(action: {
                                if let uuid = UUID(uuidString: device.identifier) {
                                    connectToDevice(with: uuid)
                                }
                            }) {
                                Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            
                            Button(action: {
                                selectedDevice = device
                                navigateToDeviceDetail = true
                            }) {
                                Label("View Details", systemImage: "info.circle")
                            }
                        }
                }
            }
        }
        .refreshable {
            isRefreshing = true
            startScan()
            // Wait for scan duration and then update the flag
            DispatchQueue.main.asyncAfter(deadline: .now() + bluetoothManager.currentScanningProfile.scanDuration) {
                isRefreshing = false
            }
        }
    }
    
    var scanningOverlay: some View {
        VStack {
            // Only show this if not in pull-to-refresh mode
            if !isRefreshing {
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
    }
    
    var renameDeviceSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Rename Family Device")) {
                    TextField("Device Name", text: $newDeviceName)
                        .autocapitalization(.words)
                    
                    if let device = selectedDevice {
                        Text("Device ID: \(device.identifier.prefix(8))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Save") {
                        if let device = selectedDevice {
                            renameDevice(device, to: newDeviceName)
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
    
    private func startScan() {
        if bluetoothManager.permissionGranted {
            bluetoothManager.startAdaptiveScanning()
        } else {
            bluetoothManager.showPermissionAlert = true
        }
    }
    
    private func isLocalDevice(_ device: BluetoothDevice) -> Bool {
        // Check if this device is the user's local device
        let localId = UIDevice.current.identifierForVendor?.uuidString ?? ""
        return device.identifier == localId
    }
    
    private func connectToDevice(with uuid: UUID) {
        // Find the peripheral with this UUID
        for device in bluetoothManager.nearbyDevices {
            if device.peripheral.identifier == uuid {
                bluetoothManager.connectToDevice(device.peripheral)
                Logger.bluetooth.info("Connection requested with device: \(uuid)")
                break
            }
        }
    }
    
    private func renameDevice(_ device: BluetoothDevice, to newName: String) {
        PersistenceController.shared.performBackgroundTask { context in
            let fetchRequest = BluetoothDevice.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "identifier == %@", device.identifier)
            
            do {
                let results = try context.fetch(fetchRequest)
                if let deviceToRename = results.first {
                    deviceToRename.deviceName = newName
                    try context.save()
                    Logger.bluetooth.info("Renamed device \(device.identifier) to \(newName)")
                    
                    // Also update the FamilyDevice entry if it exists
                    let familyDeviceRepository = FamilyDeviceRepository(context: context)
                    if let familyDevice = familyDeviceRepository.fetchDeviceByBluetoothIdentifier(identifier: device.identifier) {
                        familyDevice.customName = newName
                        try context.save()
                        Logger.bluetooth.info("Updated FamilyDevice name to \(newName)")
                    }
                }
            } catch {
                Logger.bluetooth.error("Failed to rename device: \(error.localizedDescription)")
            }
        }
    }
}

struct DeviceRow: View {
    let device: BluetoothDevice
    let isLocalDevice: Bool
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
                    Text(device.deviceName ?? "Unknown Device")
                        .font(.headline)
                        .foregroundColor(.primary) // Uses system color for best contrast
                    
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
                
                if let lastSeen = device.lastSeen {
                    Text("Last seen: \(formattedDate(lastSeen))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(device.isRecentlyActive ? .green : .gray)
                    
                    Text(connectionStatus)
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
        } else if device.isRecentlyActive {
            return "Recently Active"
        } else {
            return "Not Connected"
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