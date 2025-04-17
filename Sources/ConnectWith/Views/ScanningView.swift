import SwiftUI

struct ScanningView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var scanProgress: Double = 0.0
    @State private var isScanning = true
    @State private var devicesFound: [ScannedDevice] = []
    
    // Animation timer
    let timer = Timer.publish(every: 0.03, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 30) {
            // Header
            Text("Find Your First Family Member")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .cyan : .blue)
                .padding(.top, 40)
            
            Text("To get started, you need to connect with at least one device")
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Spacer()
            
            // Scanning circle animation
            ZStack {
                Circle()
                    .stroke(
                        colorScheme == .dark ? Color.gray.opacity(0.3) : Color.gray.opacity(0.2), 
                        lineWidth: 20
                    )
                    .frame(width: 250, height: 250)
                
                if isScanning {
                    Circle()
                        .trim(from: 0, to: scanProgress)
                        .stroke(
                            colorScheme == .dark ? Color.cyan : Color.blue, 
                            style: StrokeStyle(lineWidth: 20, lineCap: .round)
                        )
                        .frame(width: 250, height: 250)
                        .rotationEffect(.degrees(-90))
                    
                    Text("Scanning...")
                        .font(.title)
                        .foregroundColor(colorScheme == .dark ? .cyan : .blue)
                }
            }
            .onReceive(timer) { _ in
                if isScanning {
                    // Animate the progress
                    withAnimation(.linear(duration: 0.03)) {
                        scanProgress = (scanProgress + 0.003).truncatingRemainder(dividingBy: 1.0)
                    }
                    
                    // After 5 seconds, add a device (simulating detection)
                    if devicesFound.isEmpty && scanProgress > 0.6 {
                        let deviceName = UIDevice.current.name
                        devicesFound.append(ScannedDevice(id: "ABDC1E68...", name: "Nearby Device (\(deviceName.prefix(10))...)", isSaved: true))
                    }
                }
            }
            
            Spacer()
            
            // Devices list - use the DeviceResultRow component to match the screenshot
            if !devicesFound.isEmpty {
                DevicesList()
            }
            
            // Close button
            Button("Done") {
                dismiss()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(colorScheme == .dark ? Color.blue.opacity(0.8) : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding()
    }
}

struct ScannedDevice: Identifiable {
    let id: String
    let name: String
    let isSaved: Bool
}

struct DeviceRow: View {
    let device: ScannedDevice
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            // Device icon
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.blue.opacity(0.3) : Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "iphone")
                    .foregroundColor(colorScheme == .dark ? .white : .blue)
            }
            
            // Device info with high contrast 
            VStack(alignment: .leading) {
                Text(device.name)
                    .font(.headline)
                    .foregroundColor(colorScheme == .dark ? .white : .black) // Explicit contrast
                
                Text(device.id)
                    .font(.caption)
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
            }
            
            Spacer()
            
            // Status indicator with improved contrast
            if device.isSaved {
                SavedBadge()
            }
            
            Image(systemName: "chevron.right")
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
                .padding(.leading, 8)
        }
        .padding()
        .background(
            colorScheme == .dark ? 
                Color(red: 0.15, green: 0.15, blue: 0.15) : // Darker background in dark mode
                Color.white // Light background in light mode
        )
        .cornerRadius(10)
        .shadow(color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct SavedBadge: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Text("Saved")
            .font(.caption)
            .fontWeight(.bold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                colorScheme == .dark ? 
                    Color.green : // Brighter green in dark mode
                    Color.green   // Green in light mode
            )
            .foregroundColor(
                // Always white text on green background for maximum contrast
                .white
            )
            .cornerRadius(12)
    }
}

#Preview {
    Group {
        ScanningView()
            .preferredColorScheme(.light)
        
        ScanningView()
            .preferredColorScheme(.dark)
    }
}