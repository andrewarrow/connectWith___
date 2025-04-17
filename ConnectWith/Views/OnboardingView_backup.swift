import SwiftUI
import CoreBluetooth

struct OnboardingView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @Binding var isComplete: Bool
    @State private var selectedDevice: (peripheral: CBPeripheral, advertisementData: [String: Any])? = nil
    @State private var customName: String = ""
    @State private var isNamingDevice = false
    @State private var hasStartedScanning = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            Text("Find Your First Family Member")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.blue)
                .padding(.top, 40)
                .multilineTextAlignment(.center)
            
            Text("To get started, you need to connect with at least one family member's device")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            // Scanning animation/state
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 15)
                    .frame(width: 250, height: 250)
                
                if bluetoothManager.isScanning {
                    // Animated scanning effect
                    Circle()
                        .trim(from: 0, to: bluetoothManager.scanningProgress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                        .frame(width: 250, height: 250)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: bluetoothManager.scanningProgress)
                    
                    Text("Scanning...")
                        .font(.title2)
                        .foregroundColor(.blue)
                } else if selectedDevice != nil {
                    // Device selected
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Device Found!")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                } else if bluetoothManager.nearbyDevices.isEmpty && hasStartedScanning {
                    // No devices found
                    VStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        
                        Text("No Devices Found")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                } else {
                    // Ready to scan
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Tap to Start Scanning")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }
                }
            }
            .onTapGesture {
                if !bluetoothManager.isScanning && selectedDevice == nil {
                    bluetoothManager.startScanning()
                    hasStartedScanning = true
                }
            }
            
            // List of found devices
            if !bluetoothManager.nearbyDevices.isEmpty && selectedDevice == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Devices Found:")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(bluetoothManager.nearbyDevices.indices, id: \.self) { index in
                                let device = bluetoothManager.nearbyDevices[index]
                                OnboardingDeviceRow(device: device) {
                                    selectedDevice = device
                                    
                                    // Pre-fill the custom name field
                                    if let localName = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String {
                                        customName = localName
                                    } else if let name = device.peripheral.name, !name.isEmpty {
                                        customName = name
                                    } else {
                                        customName = "Family Member"
                                    }
                                    
                                    // Show the naming sheet
                                    isNamingDevice = true
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 200)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)
            }
            
            // Action button
            if !bluetoothManager.isScanning && !bluetoothManager.nearbyDevices.isEmpty && selectedDevice == nil {
                Button(action: {
                    bluetoothManager.startScanning()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan Again")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $isNamingDevice) {
            NameDeviceView(
                deviceName: customName,
                onSave: { newName in
                    saveDeviceAndComplete(newName: newName)
                },
                onCancel: {
                    selectedDevice = nil
                    isNamingDevice = false
                }
            )
        }
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
        .onAppear {
            // Clear any previously discovered devices
            bluetoothManager.nearbyDevices.removeAll()
            
            // Start advertising this device
            if bluetoothManager.permissionGranted {
                bluetoothManager.startAdvertising()
            }
        }
    }
    
    private func saveDeviceAndComplete(newName: String) {
        guard let device = selectedDevice else { return }
        
        // Save with custom name
        DeviceStore.shared.saveDevice(
            identifier: device.peripheral.identifier.uuidString,
            name: newName,
            manufacturerData: device.advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
            advertisementData: device.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? Data
        )
        
        // Mark onboarding as complete
        isComplete = true
    }
}

struct OnboardingDeviceRow: View {
    let device: (peripheral: CBPeripheral, advertisementData: [String: Any])
    let onSelect: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var deviceName: String {
        if let localName = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            return localName
        } else if let name = device.peripheral.name, !name.isEmpty {
            return name
        } else {
            return "Unknown Device"
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                // Icon with better contrast background
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ? Color.gray.opacity(0.3) : Color.blue.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "iphone")
                        .font(.system(size: 22))
                        .foregroundColor(colorScheme == .dark ? .cyan : .blue)
                }
                .padding(.trailing, 8)
                
                VStack(alignment: .leading) {
                    Text(deviceName)
                        .font(.headline)
                        .foregroundColor(.primary) // System primary color
                    
                    Text(device.peripheral.identifier.uuidString.prefix(8) + "...")
                        .font(.caption)
                        .foregroundColor(.secondary) // System secondary color
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary) // System secondary color
            }
            .padding()
            .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.white)
            .cornerRadius(10)
            .shadow(color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct NameDeviceView: View {
    @Environment(\.presentationMode) var presentationMode
    @State var deviceName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Name This Device")
                    .font(.headline)
                    .padding(.top)
                
                Text("You can give this device a more personal name")
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
                    Text("Save and Continue")
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

#Preview {
    OnboardingView(isComplete: .constant(false))
        .environmentObject(BluetoothManager())
}