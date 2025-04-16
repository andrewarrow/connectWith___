import SwiftUI
import CoreBluetooth

struct MainMenuView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @State private var hasCheckedPermission = false
    
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
                MenuButton(title: "Settings", iconName: "gear", color: .purple)
                
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

#Preview {
    MainMenuView()
        .environmentObject(BluetoothManager())
}