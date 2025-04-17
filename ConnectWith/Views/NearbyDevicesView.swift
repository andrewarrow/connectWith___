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
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "iphone")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading) {
                    Text(device.value(forKey: "deviceName") as? String ?? "Unknown Device")
                        .font(.headline)
                    
                    if let identifier = device.value(forKey: "identifier") as? String {
                        Text("ID: \(identifier.prefix(8))...")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    if let lastSeen = device.value(forKey: "lastSeen") as? Date {
                        Text("Last seen: \(formattedDate(lastSeen))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    if device.value(forKey: "manufacturerData") != nil {
                        Text("Manufacturer data available")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.vertical, 4)
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