import SwiftUI
import CoreBluetooth
import CoreData

struct MainMenuView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @State private var hasCheckedPermission = false
    @State private var showSettings = false
    @State private var showDeviceList = false
    @State private var showCalendarView = false
    @State private var customDeviceName = UserDefaults.standard.string(forKey: "DeviceCustomName") ?? ""
    
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
                
                // Bluetooth scanning section
                VStack(spacing: 10) {
                    HStack {
                        if bluetoothManager.isScanning {
                            Text("Scanning for family members...")
                                .font(.headline)
                                .foregroundColor(.blue)
                        } else if connectedDevicesCount > 0 {
                            Text("\(connectedDevicesCount) family member\(connectedDevicesCount > 1 ? "s" : "")")
                                .font(.headline)
                                .foregroundColor(.green)
                        } else {
                            Text("No family members connected")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        if !bluetoothManager.isScanning && connectedDevicesCount > 0 {
                            Button(action: {
                                bluetoothManager.startScanning()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    
                    if bluetoothManager.isScanning {
                        ProgressView(value: bluetoothManager.scanningProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(height: 8)
                            .padding(.horizontal)
                    }
                    
                    // Connected devices preview
                    if connectedDevicesCount > 0 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 15) {
                                ForEach(DeviceStore.shared.getAllDevices().prefix(3), id: \.identifier) { device in
                                    VStack {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 36))
                                            .foregroundColor(.blue)
                                        Text(device.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 70)
                                }
                                
                                if connectedDevicesCount > 3 {
                                    Button(action: {
                                        showDeviceList = true
                                    }) {
                                        VStack {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.gray.opacity(0.2))
                                                    .frame(width: 36, height: 36)
                                                Text("+\(connectedDevicesCount-3)")
                                                    .font(.system(size: 14, weight: .bold))
                                                    .foregroundColor(.gray)
                                            }
                                            Text("See all")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        .frame(width: 70)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)
                
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
                if !hasCheckedPermission {
                    // Auto-start scanning only if no devices in database
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if bluetoothManager.permissionGranted && connectedDevicesCount == 0 {
                            bluetoothManager.startScanning()
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
    
    var body: some View {
        NavigationView {
            List {
                if storedDevices.isEmpty && bluetoothManager.nearbyDevices.isEmpty {
                    Text("No devices found")
                        .foregroundColor(.gray)
                } else {
                    // Show devices from memory store
                    ForEach(storedDevices, id: \.identifier) { device in
                        StoredDeviceRow(device: device)
                    }
                    
                    // Also show current scan results
                    ForEach(bluetoothManager.nearbyDevices.indices, id: \.self) { index in
                        let device = bluetoothManager.nearbyDevices[index]
                        DeviceRowView(peripheral: device.peripheral, advertisementData: device.advertisementData)
                    }
                }
            }
            .navigationTitle("Nearby Devices")
            .navigationBarItems(
                leading: Button("Back") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button(action: {
                    bluetoothManager.startScanning()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            )
            .onAppear {
                // Load stored devices when view appears
                storedDevices = DeviceStore.shared.getAllDevices()
            }
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
        }
    }
}


#Preview {
    MainMenuView()
        .environmentObject(BluetoothManager())
}