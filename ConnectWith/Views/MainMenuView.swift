import SwiftUI
import CoreBluetooth
import CoreData
import OSLog

struct MainMenuView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @State private var hasCheckedPermission = false
    @State private var showSettings = false
    @State private var showDeviceList = false
    @State private var showCalendarView = false
    @State private var customDeviceName = UserDefaults.standard.string(forKey: "DeviceCustomName") ?? ""
    // Added to track if we're in onboarding mode (should always be false here since onboarding is completed)
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var connectedDevicesCount: Int {
        return DeviceStore.shared.getAllDevices().count
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                Text("12×")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.blue)
                    .padding(.top)
                
                Text("Plan 12 family outings this year")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.bottom)
                
                // Main menu options
                VStack(spacing: 15) {
                    MenuButton(
                        title: "Family Calendar", 
                        iconName: "calendar", 
                        color: .purple
                    ) {
                        showCalendarView = true
                    }
                    
                    MenuButton(
                        title: "Find Family Members", 
                        iconName: "person.2.wave.2.fill", 
                        color: .blue
                    ) {
                        showDeviceList = true
                    }
                    
                    MenuButton(
                        title: "Settings", 
                        iconName: "gear", 
                        color: .gray
                    ) {
                        showSettings = true
                    }
                }
                .padding(.vertical)
                
                Spacer()
            }
            .padding()
            .navigationTitle("12× Family Outings")
            .navigationBarHidden(true)
            .alert("Bluetooth Permission Required", isPresented: $bluetoothManager.showPermissionAlert) {
                Button("Settings", role: .destructive) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("This app needs Bluetooth access to find your family members. Please enable Bluetooth permission in Settings.")
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(customDeviceName: $customDeviceName) {
                    // Save custom name and restart advertising
                    UserDefaults.standard.set(customDeviceName, forKey: "DeviceCustomName")
                    bluetoothManager.stopAdvertising()
                    bluetoothManager.startAdvertising()
                }
            }
            .sheet(isPresented: $showCalendarView) {
                FamilyCalendarView()
            }
            .onAppear {
                // We should already have at least one device since onboarding is complete,
                // but we can still start scanning again for more devices
                if !hasCheckedPermission {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if bluetoothManager.permissionGranted {
                            // Start advertising this device
                            bluetoothManager.startAdvertising()
                        }
                        hasCheckedPermission = true
                    }
                }
            }
            .sheet(isPresented: $showDeviceList) {
                DeviceListView()
            }
        }
    }
}

struct FamilyCalendarView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var events: [CalendarEvent] = [
        CalendarEvent(id: UUID(), title: "Family Picnic", date: Date().addingTimeInterval(86400 * 15), location: "City Park", participants: ["Mom", "Dad", "Sarah"]),
        CalendarEvent(id: UUID(), title: "Zoo Trip", date: Date().addingTimeInterval(86400 * 45), location: "City Zoo", participants: ["Mom", "Dad", "Sarah", "Grandma"])
    ]
    @State private var showingAddEvent = false
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(events) { event in
                        EventRow(event: event)
                    }
                    .onDelete(perform: removeEvents)
                }
                
                if events.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Events Planned")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                        
                        Text("Tap the + button to start planning your family outings")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("12× Calendar")
            .navigationBarItems(
                leading: Button("Back") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button(action: {
                    showingAddEvent = true
                }) {
                    Image(systemName: "plus")
                }
            )
            .sheet(isPresented: $showingAddEvent) {
                AddEventView { event in
                    events.append(event)
                    showingAddEvent = false
                }
            }
        }
    }
    
    func removeEvents(at offsets: IndexSet) {
        events.remove(atOffsets: offsets)
    }
}

struct EventRow: View {
    let event: CalendarEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
            
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                Text(event.date, style: .date)
                    .font(.subheadline)
            }
            
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.red)
                Text(event.location)
                    .font(.subheadline)
            }
            
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.green)
                Text(event.participants.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
    }
}

struct AddEventView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var title = ""
    @State private var date = Date().addingTimeInterval(86400 * 7) // One week from now
    @State private var location = ""
    @State private var participants = ""
    
    var onSave: (CalendarEvent) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Details")) {
                    TextField("Event Title", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    TextField("Location", text: $location)
                }
                
                Section(header: Text("Participants")) {
                    TextField("Participants (comma separated)", text: $participants)
                        .autocapitalization(.words)
                }
            }
            .navigationTitle("New Family Event")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    let participantsList = participants
                        .split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    
                    let event = CalendarEvent(
                        id: UUID(),
                        title: title,
                        date: date,
                        location: location,
                        participants: participantsList
                    )
                    
                    onSave(event)
                }
                .disabled(title.isEmpty || location.isEmpty)
            )
        }
    }
}

struct CalendarEvent: Identifiable {
    let id: UUID
    let title: String
    let date: Date
    let location: String
    let participants: [String]
}

struct DeviceListView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @State private var storedDevices: [DeviceStore.StoredDevice] = []
    @State private var deviceToRename: (DeviceStore.StoredDevice?, CBPeripheral?, [String: Any]?) = (nil, nil, nil)
    @State private var isRenamingDevice = false
    @State private var newDeviceName = ""
    @State private var selectedTab = 0 // 0 = Family Members, 1 = Nearby Devices
    @State private var showingSuccessAlert = false
    @State private var recentlyAddedName = ""
    
    var body: some View {
        NavigationView {
            VStack {
                // Tab selector
                Picker("Device View", selection: $selectedTab) {
                    Text("Family Members").tag(0)
                    Text("Nearby Devices").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if selectedTab == 0 {
                    // FAMILY MEMBERS TAB
                    if storedDevices.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                            
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("No Family Members Saved")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                            
                            Text("Tap 'Scan' to find nearby devices")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button(action: {
                                selectedTab = 1 // Switch to nearby devices tab
                                bluetoothManager.startScanning()
                            }) {
                                HStack {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
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
                        .padding()
                    } else {
                        List {
                            ForEach(storedDevices, id: \.identifier) { device in
                                StoredDeviceRow(device: device)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        deviceToRename = (device, nil, nil)
                                        newDeviceName = device.name
                                        isRenamingDevice = true
                                    }
                                    .contextMenu {
                                        Button(action: {
                                            deviceToRename = (device, nil, nil)
                                            newDeviceName = device.name
                                            isRenamingDevice = true
                                        }) {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        
                                        Button(role: .destructive, action: {
                                            // Remove the device from the local database
                                            // In a real app, we'd use a proper delete method
                                            // For now, we'll just reload the list without this device
                                            storedDevices = storedDevices.filter { $0.identifier != device.identifier }
                                        }) {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                } else {
                    // NEARBY DEVICES TAB
                    if bluetoothManager.isScanning {
                        VStack {
                            // Scanning progress indicator
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                                    .frame(width: 120, height: 120)
                                
                                Circle()
                                    .trim(from: 0, to: bluetoothManager.scanningProgress)
                                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                    .frame(width: 120, height: 120)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear, value: bluetoothManager.scanningProgress)
                                
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 40))
                                    .foregroundColor(.blue)
                            }
                            .padding()
                            
                            Text("Scanning for nearby devices...")
                                .font(.headline)
                                .foregroundColor(.blue)
                            
                            if bluetoothManager.nearbyDevices.isEmpty {
                                Text("No devices found yet")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .padding()
                            }
                        }
                        .padding()
                        
                        if !bluetoothManager.nearbyDevices.isEmpty {
                            List {
                                ForEach(bluetoothManager.nearbyDevices.indices, id: \.self) { index in
                                    let device = bluetoothManager.nearbyDevices[index]
                                    NearbyDeviceRow(peripheral: device.peripheral, advertisementData: device.advertisementData)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            handleNearbyDeviceSelection(device)
                                        }
                                }
                            }
                        }
                    } else if bluetoothManager.nearbyDevices.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                            
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("No Devices Found")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.gray)
                            
                            Text("Tap the Scan button to search for nearby devices")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button(action: {
                                bluetoothManager.startScanning()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Scan Again")
                                }
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(10)
                            }
                            .padding(.top)
                            
                            Spacer()
                        }
                        .padding()
                    } else {
                        List {
                            ForEach(bluetoothManager.nearbyDevices.indices, id: \.self) { index in
                                let device = bluetoothManager.nearbyDevices[index]
                                NearbyDeviceRow(peripheral: device.peripheral, advertisementData: device.advertisementData)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        handleNearbyDeviceSelection(device)
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle(selectedTab == 0 ? "Family Members" : "Nearby Devices")
            .navigationBarItems(
                leading: Button("Back") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: HStack {
                    if selectedTab == 1 {
                        Button(action: {
                            bluetoothManager.startScanning()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                        }
                    }
                }
            )
            .onAppear {
                // Load stored devices when view appears
                storedDevices = DeviceStore.shared.getAllDevices()
                
                // Auto-start scanning on the Nearby Devices tab
                if selectedTab == 1 && !bluetoothManager.isScanning && bluetoothManager.permissionGranted {
                    bluetoothManager.startScanning()
                }
            }
            .sheet(isPresented: $isRenamingDevice) {
                if let device = deviceToRename.0 {
                    // Renaming an existing family member
                    RenameDeviceView(
                        deviceName: $newDeviceName,
                        onSave: { newName in
                            // Save with new name
                            DeviceStore.shared.saveDevice(
                                identifier: device.identifier,
                                name: newName,
                                manufacturerData: device.manufacturerData,
                                advertisementData: device.advertisementData
                            )
                            
                            // Refresh the device list
                            storedDevices = DeviceStore.shared.getAllDevices()
                            recentlyAddedName = newName
                            showingSuccessAlert = true
                        },
                        onCancel: {
                            deviceToRename = (nil, nil, nil)
                            isRenamingDevice = false
                        }
                    )
                } else if let peripheral = deviceToRename.1, let advertisementData = deviceToRename.2 {
                    // Adding a new device from nearby devices
                    RenameDeviceView(
                        deviceName: $newDeviceName,
                        onSave: { newName in
                            // Get manufacturer data if available
                            let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
                            
                            // Create a serialized version of service UUIDs if available
                            var serviceData: Data? = nil
                            if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                                let uuidStrings = serviceUUIDs.map { $0.uuidString }
                                serviceData = try? JSONSerialization.data(withJSONObject: uuidStrings)
                            }
                            
                            // Save to our in-memory store
                            DeviceStore.shared.saveDevice(
                                identifier: peripheral.identifier.uuidString,
                                name: newName,
                                manufacturerData: manufacturerData,
                                advertisementData: serviceData
                            )
                            
                            // Refresh the device list
                            storedDevices = DeviceStore.shared.getAllDevices()
                            
                            // Switch to the Family Members tab
                            selectedTab = 0
                            recentlyAddedName = newName
                            showingSuccessAlert = true
                        },
                        onCancel: {
                            deviceToRename = (nil, nil, nil)
                            isRenamingDevice = false
                        }
                    )
                }
            }
            .alert("Family Member Added", isPresented: $showingSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\(recentlyAddedName) has been saved to your Family Members.")
            }
        }
    }
    
    private func handleNearbyDeviceSelection(_ device: (peripheral: CBPeripheral, advertisementData: [String: Any])) {
        // Get the best name for the device
        let deviceName: String
        if let localName = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            deviceName = localName
        } else if let name = device.peripheral.name, !name.isEmpty {
            deviceName = name
        } else {
            deviceName = "Family Member"
        }
        
        // Set up for renaming
        deviceToRename = (nil, device.peripheral, device.advertisementData)
        newDeviceName = deviceName
        isRenamingDevice = true
    }
}

struct NearbyDeviceRow: View {
    let peripheral: CBPeripheral
    let advertisementData: [String: Any]
    
    var deviceName: String {
        // First check if this device is already stored with a custom name
        if let storedDevice = DeviceStore.shared.getDevice(identifier: peripheral.identifier.uuidString),
           storedDevice.name != "Unknown Device" {
            return storedDevice.name
        }
        
        // Next try to get the name from advertisement data
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
            return localName
        }
        
        // Then try the peripheral name
        if let name = peripheral.name, !name.isEmpty {
            return name
        }
        
        // If we've scanned this device before but don't have a name yet, see if we can derive a name from the device type
        let myDeviceName = UIDevice.current.name
        return "Nearby Device (\(myDeviceName.prefix(10))...)"
    }
    
    // Check if this device is already in our saved list
    var isSaved: Bool {
        return DeviceStore.shared.getDevice(identifier: peripheral.identifier.uuidString) != nil
    }
    
    var body: some View {
        HStack {
            Image(systemName: isSaved ? "iphone.circle.fill" : "iphone")
                .font(.system(size: 30))
                .foregroundColor(isSaved ? .green : .blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(deviceName)
                        .font(.headline)
                    
                    if isSaved {
                        Text("Saved")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .cornerRadius(10)
                    }
                }
                
                Text(peripheral.identifier.uuidString.prefix(8) + "...")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text("Tap to add to Family Members")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .opacity(isSaved ? 0 : 1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
        .opacity(isSaved ? 0.7 : 1)
    }
}

struct RenameDeviceView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var deviceName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Rename Device")
                    .font(.headline)
                    .padding(.top)
                
                Text("Give this device a more personal name")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 70))
                    .foregroundColor(.blue)
                    .padding()
                
                TextField("Device Name", text: $deviceName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal, 40)
                    .autocapitalization(.words)
                
                Text("This name will help you identify this device in the future")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                Button(action: {
                    onSave(deviceName)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Save")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
                .disabled(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationBarItems(
                leading: Button("Cancel") {
                    onCancel()
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

struct StoredDeviceRow: View {
    let device: DeviceStore.StoredDevice
    
    var body: some View {
        HStack {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .foregroundColor(.green)
            
            VStack(alignment: .leading) {
                Text(device.name)
                    .font(.headline)
                
                Text("ID: \(device.identifier.prefix(8))...")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text("Last seen: \(formattedDate(device.lastSeen))")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                if device.manufacturerData != nil {
                    Text("Manufacturer data available")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct DeviceRowView: View {
    let peripheral: CBPeripheral
    let advertisementData: [String: Any]
    
    var body: some View {
        HStack {
            Image(systemName: "iphone")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                // Show device name if available, otherwise show peripheral name or identifier
                if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
                    Text("Name: \(localName)")
                        .font(.subheadline)
                        .bold()
                } else if let name = peripheral.name, !name.isEmpty {
                    Text("Device: \(name)")
                        .font(.subheadline)
                        .bold()
                } else {
                    Text("ID: \(peripheral.identifier.uuidString.prefix(8))...")
                        .font(.subheadline)
                        .bold()
                }
                
                // Show other details
                if let _ = advertisementData[CBAdvertisementDataManufacturerDataKey] {
                    Text("Manufacturer data present")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SettingsView: View {
    @Binding var customDeviceName: String
    var onSave: () -> Void
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var showingResetConfirmation = false
    @State private var showingRestartAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Device Identity")) {
                    TextField("Custom Device Name", text: $customDeviceName)
                        .autocapitalization(.words)
                    
                    Text("This name will be visible to other devices when connecting")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Section(header: Text("Data Management"), footer: Text("This will delete all saved device data and return you to the onboarding screen.")) {
                    Button(action: {
                        showingResetConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Reset Database")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    onSave()
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .confirmationDialog(
                "Reset Database",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Database", role: .destructive) {
                    resetAppData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all saved devices and return to the onboarding screen. This cannot be undone.")
            }
            .alert("Database Reset Complete", isPresented: $showingRestartAlert) {
                Button("OK") {
                    // Just dismiss the settings view, will return to onboarding
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                Text("Your database has been reset. You'll now return to the onboarding screen.")
            }
        }
    }
    
    private func resetAppData() {
        // Clear device name from UserDefaults
        UserDefaults.standard.removeObject(forKey: "DeviceCustomName")
        
        // Clear in-memory device store
        DeviceStore.shared.deleteAllDevices()
        
        // Reset app to onboarding mode
        hasCompletedOnboarding = false
        
        // Reset Bluetooth device scanning
        bluetoothManager.stopScanning()
        bluetoothManager.nearbyDevices.removeAll()
        
        // Show completion alert
        showingRestartAlert = true
    }
}


#Preview {
    MainMenuView()
        .environmentObject(BluetoothManager())
}
