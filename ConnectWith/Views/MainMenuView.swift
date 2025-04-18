import SwiftUI
import CoreBluetooth
import CoreData
import OSLog

// Import our calendar components directly
struct CalendarViewContainer: View {
    @State private var events = [
        CalendarEvent(month: "January", title: "Event", location: "Home", day: 1, color: .blue),
        CalendarEvent(month: "February", title: "Event", location: "Home", day: 1, color: .pink),
        CalendarEvent(month: "March", title: "Event", location: "Home", day: 1, color: .green),
        CalendarEvent(month: "April", title: "Event", location: "Home", day: 1, color: .orange),
        CalendarEvent(month: "May", title: "Event", location: "Home", day: 1, color: .purple),
        CalendarEvent(month: "June", title: "Event", location: "Home", day: 1, color: .yellow),
        CalendarEvent(month: "July", title: "Event", location: "Home", day: 1, color: .red),
        CalendarEvent(month: "August", title: "Event", location: "Home", day: 1, color: .teal),
        CalendarEvent(month: "September", title: "Event", location: "Home", day: 1, color: .indigo),
        CalendarEvent(month: "October", title: "Event", location: "Home", day: 1, color: .brown),
        CalendarEvent(month: "November", title: "Event", location: "Home", day: 1, color: .cyan),
        CalendarEvent(month: "December", title: "Event", location: "Home", day: 1, color: .mint)
    ]
    @State private var currentIndex: Int = 0
    @Environment(\.presentationMode) private var presentationMode
    
    struct CalendarEvent: Identifiable {
        var id = UUID()
        var month: String
        var title: String
        var location: String
        var day: Int
        var color: Color
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .padding()
                    
                    Spacer()
                }
                
                Text("Family Calendar")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Swipe to browse your events")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
                
                TabView(selection: $currentIndex) {
                    ForEach(Array(events.indices), id: \.self) { index in
                        EventCardView(event: $events[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                .frame(height: 240)
                .padding(.vertical)
                
                Spacer()
                
                VStack(alignment: .leading) {
                    Text("Current Event: \(events[currentIndex].month)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.horizontal)
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Title: \(events[currentIndex].title)", systemImage: "pencil")
                            Label("Location: \(events[currentIndex].location)", systemImage: "mappin.and.ellipse")
                            Label("Date: \(events[currentIndex].day) \(events[currentIndex].month)", systemImage: "calendar")
                        }
                        .padding()
                        
                        Spacer()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding()
            }
        }
    }
    
    struct EventCardView: View {
        @Binding var event: CalendarEvent
        @State private var isEditing = false
        @State private var title: String
        @State private var location: String
        @State private var day: Int
        
        init(event: Binding<CalendarEvent>) {
            self._event = event
            self._title = State(initialValue: event.wrappedValue.title)
            self._location = State(initialValue: event.wrappedValue.location)
            self._day = State(initialValue: event.wrappedValue.day)
        }
        
        var body: some View {
            VStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(event.color)
                        .shadow(radius: 5)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(event.month)
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                            Button(action: {
                                isEditing.toggle()
                            }) {
                                Image(systemName: isEditing ? "checkmark.circle" : "pencil.circle")
                                    .foregroundColor(.white)
                                    .font(.title2)
                            }
                        }
                        
                        if isEditing {
                            editingView
                        } else {
                            displayView
                        }
                    }
                    .padding()
                }
                .frame(height: 180)
                .padding(.horizontal)
            }
        }
        
        var displayView: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text(event.title)
                    .font(.title)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(event.location)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                
                Spacer()
                
                HStack {
                    Text("Day: \(event.day)")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                }
            }
        }
        
        var editingView: some View {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $title)
                    .font(.title3)
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                    .padding(5)
                    .onChange(of: title) { newValue in
                        event.title = newValue
                    }
                
                TextField("Location", text: $location)
                    .font(.body)
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
                    .padding(5)
                    .onChange(of: location) { newValue in
                        event.location = newValue
                    }
                
                Stepper("Day: \(day)", value: $day, in: 1...31)
                    .foregroundColor(.white)
                    .onChange(of: day) { newValue in
                        event.day = newValue
                    }
            }
        }
    }
}

#if DEBUG
// Simple debug view that doesn't import BluetoothDebugView
struct DebugInfoView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @Environment(\.presentationMode) var presentationMode
    @State private var logMessages: [String] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    @State private var isAutoRefreshing = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("Device Info")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            DebugRow(label: "Device ID", value: UIDevice.current.identifierForVendor?.uuidString ?? "Unknown")
                            DebugRow(label: "Device Name", value: bluetoothManager.deviceName)
                            DebugRow(label: "BT Service UUID", value: BluetoothManager.serviceUUID.uuidString)
                            DebugRow(label: "Calendar Char UUID", value: BluetoothManager.calendarCharacteristicUUID.uuidString)
                            DebugRow(label: "Advertising", value: bluetoothManager.isAdvertising ? "Active" : "Inactive")
                            DebugRow(label: "Permission", value: bluetoothManager.permissionGranted ? "Granted" : "Denied")
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Group {
                        Text("Connection Status")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            DebugRow(label: "Scanning", value: bluetoothManager.isScanning ? "Active" : "Inactive")
                            DebugRow(label: "Scan Progress", value: "\(Int(bluetoothManager.scanningProgress * 100))%")
                            DebugRow(label: "Connected Devices", value: "\(bluetoothManager.connectedPeripherals.count)")
                            DebugRow(label: "Sync In Progress", value: bluetoothManager.syncInProgress ? "Yes" : "No")
                            
                            if let lastSyncTime = bluetoothManager.lastSyncTime {
                                DebugRow(label: "Last Sync", value: formatDateTime(lastSyncTime))
                                DebugRow(label: "With Device", value: bluetoothManager.lastSyncDeviceName ?? "Unknown")
                                DebugRow(label: "Events Synced", value: "\(bluetoothManager.syncedEventsCount)")
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Group {
                        Text("Nearby Devices (\(bluetoothManager.nearbyDevices.count))")
                            .font(.headline)
                        
                        if bluetoothManager.nearbyDevices.isEmpty {
                            Text("No nearby devices detected")
                                .foregroundColor(.gray)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        } else {
                            ForEach(bluetoothManager.nearbyDevices.indices, id: \.self) { index in
                                let device = bluetoothManager.nearbyDevices[index]
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(getDeviceName(device))
                                        .font(.headline)
                                    
                                    DebugRow(label: "ID", value: device.peripheral.identifier.uuidString)
                                    DebugRow(label: "RSSI", value: device.rssi.stringValue)
                                    
                                    if let manufacturerData = device.advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
                                        DebugRow(label: "Manufacturer", value: "Present (\(manufacturerData.count) bytes)")
                                    }
                                    
                                    if let serviceUUIDs = device.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                                        Text("Services: \(serviceUUIDs.map { $0.uuidString }.joined(separator: ", "))")
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    HStack {
                        Button("Start Scan") {
                            bluetoothManager.startScanning()
                            logMessages.insert("Manual scan started", at: 0)
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Button("Force Sync") {
                            bluetoothManager.scanAndSyncWithFamilyMembers()
                            logMessages.insert("Manual sync initiated", at: 0)
                        }
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        Spacer()
                        
                        Toggle("Auto Refresh", isOn: $isAutoRefreshing)
                    }
                    
                    Text("Log Messages")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if logMessages.isEmpty {
                            Text("No log messages yet")
                                .foregroundColor(.gray)
                                .padding()
                        } else {
                            ForEach(logMessages.indices.prefix(20), id: \.self) { index in
                                Text(logMessages[index])
                                    .font(.caption)
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("Bluetooth Debug")
            .navigationBarItems(
                trailing: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .onAppear {
                updateLogs()
            }
            .onReceive(timer) { _ in
                if isAutoRefreshing {
                    updateLogs()
                }
            }
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func updateLogs() {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        
        // Add basic bluetooth state info
        logMessages.insert("[\(timestamp)] Bluetooth: \(bluetoothManager.permissionGranted ? "Authorized" : "Unauthorized")", at: 0)
        logMessages.insert("[\(timestamp)] Scanning: \(bluetoothManager.isScanning ? "Yes" : "No")", at: 0)
        logMessages.insert("[\(timestamp)] Nearby devices: \(bluetoothManager.nearbyDevices.count)", at: 0)
        logMessages.insert("[\(timestamp)] Connected: \(bluetoothManager.connectedPeripherals.count)", at: 0)
        
        // Add sync status if available
        if let lastSyncTime = bluetoothManager.lastSyncTime {
            let formatter = RelativeDateTimeFormatter()
            let relativeTime = formatter.localizedString(for: lastSyncTime, relativeTo: Date())
            logMessages.insert("[\(timestamp)] Last sync: \(relativeTime)", at: 0)
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
}

struct DebugRow: View {
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

extension NSNumber {
    var stringValue: String {
        return String(describing: self)
    }
}
#endif

struct MainMenuView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @EnvironmentObject private var guidanceManager: GuidanceManager
    @State private var hasCheckedPermission = false
    @State private var showSettings = false
    @State private var showDeviceList = false
    @State private var showCalendarView = false
    @State private var showDebugView = false
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
                        iconName: "calendar.badge.plus", 
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
                    
                    #if DEBUG
                    // In debug builds, show a debug button that opens a temporary view
                    MenuButton(
                        title: "Bluetooth Debug", 
                        iconName: "antenna.radiowaves.left.and.right.circle", 
                        color: .orange
                    ) {
                        showDebugView = true
                    }
                    #endif
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
                // Use our new FamilyCalendarView with monthly event cards
                FamilyCalendarView()
                    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            }
            #if DEBUG
            .sheet(isPresented: $showDebugView) {
                // In debug mode, show a temporary debug view with Bluetooth info
                DebugInfoView(bluetoothManager: bluetoothManager)
            }
            #endif
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

// Using our new Family Calendar implementation with month cards

struct EventSyncInfoView: View {
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var calendarStore: CalendarStore
    let event: CalendarEvent
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Event Details")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title)
                            .font(.title2)
                            .bold()
                        
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.blue)
                            Text(event.date, style: .date)
                        }
                        
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.red)
                            Text(event.location)
                        }
                        
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("Sync Status")) {
                    HStack {
                        Text("Synced with")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(calendarStore.getSyncCountForEvent(id: event.id)) family members")
                            .foregroundColor(.primary)
                    }
                }
                
                Section(header: Text("Change History")) {
                    ForEach(calendarStore.getChangeHistoryForEvent(id: event.id), id: \.timestamp) { change in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: changeTypeIcon(change.changeType))
                                    .foregroundColor(changeTypeColor(change.changeType))
                                
                                Text(changeTypeString(change.changeType))
                                    .font(.headline)
                                
                                Spacer()
                                
                                Text(change.timestamp, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            Text("By: \(change.deviceName)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if let field = change.fieldChanged {
                                Text("Changed: \(field)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let oldValue = change.oldValue, let newValue = change.newValue {
                                Text("From: \(oldValue) → To: \(newValue)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Event Details")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    private func changeTypeIcon(_ type: CalendarStore.EventChange.ChangeType) -> String {
        switch type {
        case .created: return "plus.circle"
        case .updated: return "pencil.circle"
        case .deleted: return "trash.circle"
        case .synced: return "arrow.triangle.2.circlepath.circle"
        }
    }
    
    private func changeTypeColor(_ type: CalendarStore.EventChange.ChangeType) -> Color {
        switch type {
        case .created: return .green
        case .updated: return .blue
        case .deleted: return .red
        case .synced: return .purple
        }
    }
    
    private func changeTypeString(_ type: CalendarStore.EventChange.ChangeType) -> String {
        switch type {
        case .created: return "Created"
        case .updated: return "Updated"
        case .deleted: return "Deleted"
        case .synced: return "Synced"
        }
    }
}

struct EventRow: View {
    let event: CalendarEvent
    let syncCount: Int
    
    init(event: CalendarEvent, syncCount: Int = 0) {
        self.event = event
        self.syncCount = syncCount
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.title)
                    .font(.headline)
                
                Spacer()
                
                // Show sync badge
                HStack(spacing: 2) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundColor(syncCount > 0 ? .green : .gray)
                    
                    Text("\(syncCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(syncCount > 0 ? .green : .gray)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(syncCount > 0 ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
                )
            }
            
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
            
            
            if syncCount == 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    
                    Text("Only on this device. Not yet synced with family.")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
                .padding(.top, 2)
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
    
    var onSave: (CalendarEvent) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Details")) {
                    TextField("Event Title", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    TextField("Location", text: $location)
                }
                
            }
            .navigationTitle("New Family Event")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    let event = CalendarEvent(
                        id: UUID(),
                        title: title,
                        date: date,
                        location: location
                    )
                    
                    onSave(event)
                }
                .disabled(title.isEmpty || location.isEmpty)
            )
        }
    }
}

struct CalendarEvent: Identifiable, Codable {
    let id: UUID
    let title: String
    let date: Date
    let location: String
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
                                ForEach(Array(bluetoothManager.nearbyDevices.enumerated()), id: \.offset) { (index, device) in
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
                            ForEach(Array(bluetoothManager.nearbyDevices.enumerated()), id: \.offset) { (index, device) in
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
    
    private func handleNearbyDeviceSelection(_ device: (peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)) {
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