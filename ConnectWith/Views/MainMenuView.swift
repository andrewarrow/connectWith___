import SwiftUI
import CoreBluetooth

struct MainMenuView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @State private var hasCheckedPermission = false
    @State private var showSettings = false
    @State private var customDeviceName = UserDefaults.standard.string(forKey: "DeviceCustomName") ?? ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Bluetooth scanning section
                VStack(spacing: 10) {
                    if bluetoothManager.isScanning {
                        Text("Scanning...")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        ProgressView(value: bluetoothManager.scanningProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .frame(height: 8)
                    } else if !bluetoothManager.nearbyDevices.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .foregroundColor(.green)
                                Text("\(bluetoothManager.nearbyDevices.count) nearby")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                                Button(action: {
                                    bluetoothManager.startScanning()
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal)
                            
                            // Show details for each detected device
                            ForEach(bluetoothManager.nearbyDevices.indices, id: \.self) { index in
                                let device = bluetoothManager.nearbyDevices[index]
                                let adData = device.advertisementData
                                
                                HStack {
                                    Image(systemName: "iphone")
                                        .foregroundColor(.blue)
                                    
                                    VStack(alignment: .leading) {
                                        // Show device name if available, otherwise show peripheral name or identifier
                                        if let localName = adData[CBAdvertisementDataLocalNameKey] as? String {
                                            Text("Name: \(localName)")
                                                .font(.subheadline)
                                                .bold()
                                        } else if let name = device.peripheral.name, !name.isEmpty {
                                            Text("Device: \(name)")
                                                .font(.subheadline)
                                                .bold()
                                        } else {
                                            Text("ID: \(device.peripheral.identifier.uuidString.prefix(8))...")
                                                .font(.subheadline)
                                                .bold()
                                        }
                                        
                                        // Show other details
                                        if let manufacturer = adData[CBAdvertisementDataManufacturerDataKey] {
                                            Text("Manufacturer data present")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 2)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "person.2.slash")
                                .foregroundColor(.gray)
                            Text("No one nearby")
                                .font(.headline)
                                .foregroundColor(.gray)
                            Spacer()
                            Button(action: {
                                bluetoothManager.startScanning()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                Text("Welcome to 12x")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                MenuButton(title: "Connect", iconName: "person.2.fill", color: .blue)
                MenuButton(title: "Discover", iconName: "magnifyingglass", color: .green)
                MenuButton(title: "Settings", iconName: "gear", color: .purple) {
                    showSettings = true
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Main Menu")
            .alert("Bluetooth Permission Required", isPresented: $bluetoothManager.showPermissionAlert) {
                Button("Settings", role: .destructive) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("This app needs Bluetooth access to find nearby users. Please enable Bluetooth permission in Settings.")
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(customDeviceName: $customDeviceName) {
                    // Save custom name and restart advertising
                    UserDefaults.standard.set(customDeviceName, forKey: "DeviceCustomName")
                    bluetoothManager.stopAdvertising()
                    bluetoothManager.startAdvertising()
                }
            }
            .onAppear {
                if !hasCheckedPermission {
                    // Start scanning when view appears if permissions are granted
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if bluetoothManager.permissionGranted {
                            bluetoothManager.startScanning()
                        }
                        hasCheckedPermission = true
                    }
                }
            }
        }
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