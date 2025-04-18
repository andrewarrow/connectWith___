import SwiftUI
import CoreBluetooth

// MARK: - Onboarding View
struct OnboardingView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @Binding var isComplete: Bool
    @State private var selectedDevice: (peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)? = nil
    @State private var customName: String = ""
    @State private var isNamingDevice = false
    @State private var hasStartedScanning = false
    @State private var currentPage = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    // Onboarding page content
    private let onboardingPages = [
        OnboardingPage(
            title: "Welcome to Family Connect",
            description: "A simple way to plan your family's most important events",
            imageName: "calendar.badge.clock",
            imageColor: .blue
        ),
        OnboardingPage(
            title: "12 Events, 12 Months",
            description: "Focus on what matters most - one important event per month for your family",
            imageName: "calendar",
            imageColor: .purple
        ),
        OnboardingPage(
            title: "Connect Without Internet",
            description: "Sync automatically with family members via Bluetooth when you're at home together",
            imageName: "antenna.radiowaves.left.and.right",
            imageColor: .green
        )
    ]
    
    var body: some View {
        ZStack {
            // Main content
            if currentPage < onboardingPages.count {
                // Introduction pages
                OnboardingPageView(
                    page: onboardingPages[currentPage],
                    currentPage: $currentPage,
                    totalPages: onboardingPages.count,
                    onNext: {
                        withAnimation {
                            currentPage += 1
                        }
                    },
                    onSkip: {
                        withAnimation {
                            currentPage = onboardingPages.count
                        }
                    }
                )
            } else if !bluetoothManager.permissionGranted {
                // Bluetooth permission request
                BluetoothPermissionView(
                    onContinue: {
                        // When user taps Continue, we'll show the device setup screen
                        // The bluetoothManager will handle the actual permission request
                        bluetoothManager.startScanning()
                        bluetoothManager.stopScanning()
                    },
                    onSkip: {
                        // User can skip and we'll mark onboarding as complete
                        isComplete = true
                    }
                )
            } else {
                // Device setup
                DeviceSetupView(
                    isScanning: bluetoothManager.isScanning,
                    scanningProgress: bluetoothManager.scanningProgress,
                    hasSelectedDevice: selectedDevice != nil,
                    deviceCount: bluetoothManager.nearbyDevices.count,
                    hasStartedScanning: hasStartedScanning,
                    nearbyDevices: bluetoothManager.nearbyDevices,
                    onTapAction: {
                        if !bluetoothManager.isScanning && selectedDevice == nil {
                            bluetoothManager.startScanning()
                            hasStartedScanning = true
                        }
                    },
                    onSelectDevice: { device in
                        selectedDevice = device
                        setInitialCustomName(for: device)
                        isNamingDevice = true
                    },
                    onScanAgain: {
                        bluetoothManager.startScanning()
                    },
                    onSkip: {
                        // Allow users to skip device setup
                        isComplete = true
                    }
                )
            }
        }
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
            
            // Start advertising this device if permission is granted
            if bluetoothManager.permissionGranted {
                bluetoothManager.startAdvertising()
            }
        }
    }
    
    private func setInitialCustomName(for device: (peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)) {
        if let localName = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            customName = localName
        } else if let name = device.peripheral.name, !name.isEmpty {
            customName = name
        } else {
            customName = "Family Member"
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
        
        // Set user's device name
        UserDefaults.standard.set(newName, forKey: "DeviceCustomName")
        
        // Mark onboarding as complete
        isComplete = true
    }
}

// MARK: - Onboarding Page Model
struct OnboardingPage {
    let title: String
    let description: String
    let imageName: String
    let imageColor: Color
}

// MARK: - Onboarding Page View
struct OnboardingPageView: View {
    let page: OnboardingPage
    @Binding var currentPage: Int
    let totalPages: Int
    let onNext: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? page.imageColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)
            
            // Icon
            Image(systemName: page.imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .foregroundColor(page.imageColor)
                .padding(30)
                .background(
                    Circle()
                        .fill(page.imageColor.opacity(0.1))
                )
            
            // Title
            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .padding(.horizontal)
            
            // Description
            Text(page.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
            
            Spacer()
            
            // Navigation buttons
            HStack {
                Button(action: onSkip) {
                    Text("Skip")
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Button(action: onNext) {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(page.imageColor)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Bluetooth Permission View
struct BluetoothPermissionView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Icon
            Image(systemName: "antenna.radiowaves.left.and.right")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .foregroundColor(.blue)
                .padding(30)
                .background(
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                )
            
            // Title
            Text("Bluetooth Permission")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .padding(.horizontal)
            
            // Description
            VStack(spacing: 20) {
                Text("This app needs Bluetooth access to sync events with your family members' devices when you're at home together.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)
                
                Text("You'll be prompted to allow Bluetooth access in the next step.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            // Navigation buttons
            HStack {
                Button(action: onSkip) {
                    Text("Skip")
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                Button(action: onContinue) {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Device Setup View
struct DeviceSetupView: View {
    let isScanning: Bool
    let scanningProgress: Double
    let hasSelectedDevice: Bool
    let deviceCount: Int
    let hasStartedScanning: Bool
    let nearbyDevices: [(peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)]
    let onTapAction: () -> Void
    let onSelectDevice: ((peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)) -> Void
    let onScanAgain: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            Text("Find Your Family Members")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.blue)
                .padding(.top, 40)
                .multilineTextAlignment(.center)
            
            Text("Connect with family members' devices to automatically sync your important events")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            // Scanning state visualization
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 15)
                    .frame(width: 250, height: 250)
                
                if isScanning {
                    // Animated scanning effect
                    Circle()
                        .trim(from: 0, to: scanningProgress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                        .frame(width: 250, height: 250)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: scanningProgress)
                    
                    Text("Scanning...")
                        .font(.title2)
                        .foregroundColor(.blue)
                } else if hasSelectedDevice {
                    // Device selected
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        
                        Text("Device Found!")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                } else if deviceCount == 0 && hasStartedScanning {
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
            .onTapGesture(perform: onTapAction)
            
            // List of found devices
            if !nearbyDevices.isEmpty && !hasSelectedDevice {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Devices Found:")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(Array(nearbyDevices.enumerated()), id: \.offset) { (_, device) in
                                OnboardingDeviceRow(device: device) {
                                    onSelectDevice(device)
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
            
            // Action buttons
            HStack {
                if !isScanning && !nearbyDevices.isEmpty && !hasSelectedDevice {
                    Button(action: onScanAgain) {
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
                }
                
                Button(action: onSkip) {
                    Text("Skip for Now")
                        .padding()
                        .frame(maxWidth: onScanAgain != nil && !isScanning && !nearbyDevices.isEmpty && !hasSelectedDevice ? nil : .infinity)
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 20)
            
            Spacer()
        }
        .padding()
    }
}

// MARK: - Device Row Component
struct OnboardingDeviceRow: View {
    let device: (peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber)
    let onSelect: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var deviceName: String {
        // First check if this device is already stored with a custom name
        if let storedDevice = DeviceStore.shared.getDevice(identifier: device.peripheral.identifier.uuidString),
           storedDevice.name != "Unknown Device" {
            return storedDevice.name
        }
        
        // Next try to get the name from advertisement data
        if let localName = device.advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
            return localName
        }
        
        // Then try the peripheral name
        if let name = device.peripheral.name, !name.isEmpty {
            return name
        }
        
        // Finally, use a default name
        return "Unknown Device"
    }
    
    // Check if this device is already in our saved list
    var isSaved: Bool {
        return DeviceStore.shared.getDevice(identifier: device.peripheral.identifier.uuidString) != nil
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                // Device icon with better contrast
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
                        .foregroundColor(.primary)
                    
                    Text(device.peripheral.identifier.uuidString.prefix(8) + "...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.white)
            .cornerRadius(10)
            .shadow(color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Device Naming View
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

// MARK: - Preview
#Preview {
    OnboardingView(isComplete: .constant(false))
        .environmentObject(BluetoothManager())
}