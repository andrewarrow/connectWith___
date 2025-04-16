import SwiftUI
import CoreBluetooth

@main
struct ConnectWithApp: App {
    @State private var isShowingSplash = true
    @StateObject private var bluetoothManager = BluetoothManager()
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if isShowingSplash {
                    SplashScreen(isShowingSplash: $isShowingSplash)
                } else {
                    MainMenuView()
                }
            }
            .environmentObject(bluetoothManager)
        }
    }
}

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralManagerDelegate {
    static let serviceUUID = CBUUID(string: "4514d666-d6c9-49cb-bc31-dc6dfa28bd58")
    
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    
    @Published var isScanning = false
    @Published var permissionGranted = false
    @Published var nearbyDevices: [CBPeripheral] = []
    @Published var scanningProgress: Double = 0.0
    @Published var showPermissionAlert = false
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard permissionGranted else {
            showPermissionAlert = true
            return
        }
        
        nearbyDevices.removeAll()
        isScanning = true
        scanningProgress = 0.0
        
        // Start the scanning progress animation
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            
            if self.scanningProgress < 1.0 {
                self.scanningProgress += 0.01
            } else {
                timer.invalidate()
            }
        }
        
        // Scan for the specific service UUID
        centralManager?.scanForPeripherals(withServices: [BluetoothManager.serviceUUID], options: nil)
        
        // Auto-stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.stopScanning()
            timer.invalidate()
            self?.scanningProgress = 1.0
        }
    }
    
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
    }
    
    func startAdvertising() {
        guard permissionGranted else {
            showPermissionAlert = true
            return
        }
        
        // Create a service with our UUID
        let service = CBMutableService(type: BluetoothManager.serviceUUID, primary: true)
        
        // Add the service to the peripheral manager
        peripheralManager?.add(service)
        
        // Start advertising
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BluetoothManager.serviceUUID]
        ])
    }
    
    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            permissionGranted = true
            startAdvertising() // Start advertising when BT is powered on
        case .unauthorized:
            permissionGranted = false
            showPermissionAlert = true
        default:
            permissionGranted = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check if we already discovered this device
        if !nearbyDevices.contains(where: { $0.identifier == peripheral.identifier }) {
            nearbyDevices.append(peripheral)
        }
    }
    
    // MARK: - CBPeripheralManagerDelegate
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            permissionGranted = true
        case .unauthorized:
            permissionGranted = false
            showPermissionAlert = true
        default:
            permissionGranted = false
        }
    }
}