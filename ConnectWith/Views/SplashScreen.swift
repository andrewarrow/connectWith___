import SwiftUI
import CoreBluetooth

struct SplashScreen: View {
    @Binding var isShowingSplash: Bool
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    
    var body: some View {
        ZStack {
            Color.purple.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("12×")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Family Outings")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 26))
                        Image(systemName: "house.fill")
                            .font(.system(size: 26))
                        Image(systemName: "calendar")
                            .font(.system(size: 26))
                    }
                    .foregroundColor(.white)
                    
                    Text("Plan 12 outings together")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.top, 20)
            }
            .shadow(radius: 10)
        }
        .onAppear {
            // Start Bluetooth advertisement right away
            if bluetoothManager.permissionGranted {
                bluetoothManager.startAdvertising()
            }
            
            // Auto-dismiss splash screen after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    isShowingSplash = false
                }
            }
        }
    }
}

#Preview {
    SplashScreen(isShowingSplash: .constant(true))
        .environmentObject(BluetoothManager())
}