import SwiftUI
import CoreBluetooth

struct SplashScreen: View {
    @Binding var isShowingSplash: Bool
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    
    var body: some View {
        ZStack {
            Color.blue.opacity(0.7)
                .ignoresSafeArea()
            
            VStack {
                Text("12x")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                
                Image(systemName: "link.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.white)
                    .padding()
            }
        }
        .onAppear {
            // Auto-dismiss splash screen after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    isShowingSplash = false
                    
                    // Start Bluetooth advertisement when we enter the app
                    if bluetoothManager.permissionGranted {
                        bluetoothManager.startAdvertising()
                        bluetoothManager.startScanning()
                    }
                }
            }
        }
    }
}

#Preview {
    SplashScreen(isShowingSplash: .constant(true))
        .environmentObject(BluetoothManager())
}