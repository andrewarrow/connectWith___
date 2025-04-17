import SwiftUI
import CoreBluetooth
import CoreData
import OSLog

struct NearbyDevicesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    
    @FetchRequest(
        entity: NSEntityDescription.entity(forEntityName: "BluetoothDevice", in: PersistenceController.shared.container.viewContext)!,
        sortDescriptors: [NSSortDescriptor(key: "lastSeen", ascending: false)],
        animation: .default)
    private var devices: FetchedResults<NSManagedObject>
    
    var body: some View {
        NavigationView {
            List {
                ForEach(devices, id: \NSManagedObject.objectID) { device in
                    DeviceRow(device: device)
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
        }
    }
}

struct DeviceRow: View {
    let device: NSManagedObject
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                // Device icon with better contrast
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ? Color.gray.opacity(0.3) : Color.blue.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "iphone")
                        .foregroundColor(colorScheme == .dark ? .cyan : .blue)
                }
                
                VStack(alignment: .leading) {
                    Text(device.value(forKey: "deviceName") as? String ?? "Unknown Device")
                        .font(.headline)
                        .foregroundColor(.primary) // Uses system color for best contrast
                    
                    if let identifier = device.value(forKey: "identifier") as? String {
                        Text("ID: \(identifier.prefix(8))...")
                            .font(.caption)
                            .foregroundColor(.secondary) // Better than hardcoded gray
                    }
                    
                    if let lastSeen = device.value(forKey: "lastSeen") as? Date {
                        Text("Last seen: \(formattedDate(lastSeen))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if device.value(forKey: "manufacturerData") != nil {
                        HStack {
                            Text("Manufacturer data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // High contrast badge for important information
                            Text("Available")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    colorScheme == .dark ?
                                        Color.mint.opacity(0.8) : // Dark mode version
                                        Color.blue.opacity(0.8)  // Light mode version
                                )
                                .foregroundColor(
                                    colorScheme == .dark ?
                                        Color.black : // Dark text on light background
                                        Color.white   // Light text on dark background
                                )
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
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
        .environmentObject(BluetoothManager())
}