import SwiftUI

struct DeviceResultRow: View {
    let deviceId: String
    let deviceName: String
    let isSaved: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            // Device icon
            ZStack {
                Circle()
                    .fill(Color.mint)
                    .frame(width: 56, height: 56)
                
                Image(systemName: "iphone")
                    .font(.system(size: 26))
                    .foregroundColor(.white)
            }
            
            // Device info
            VStack(alignment: .leading, spacing: 4) {
                Text(deviceName)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(
                        colorScheme == .dark ? .white : .black
                    )
                
                Text(deviceId)
                    .font(.subheadline)
                    .foregroundColor(
                        colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6)
                    )
            }
            .padding(.leading, 4)
            
            Spacer()
            
            // Saved status with high contrast
            if isSaved {
                Text("Saved")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        // Dark green border + darker green fill for better contrast
                        colorScheme == .dark ? 
                            Color.green.opacity(0.8) :
                            Color(red: 0.0, green: 0.6, blue: 0.0)
                    )
                    .foregroundColor(.white) // White text for maximum contrast
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color(red: 0.0, green: 0.5, blue: 0.0), lineWidth: 1)
                    )
            }
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .padding(.leading, 4)
        }
        .padding()
        .background(
            colorScheme == .dark ?
                Color(white: 0.2) : // Darker gray in dark mode
                Color(white: 0.9)   // Lighter gray in light mode
        )
        .cornerRadius(12)
    }
}

/// A component that matches the exact UI from the screenshot
struct DevicesList: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Devices Found:")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.bottom, 8)
            
            DeviceResultRow(
                deviceId: "ABDC1E68...",
                deviceName: "Unknown Device",
                isSaved: true
            )
        }
        .padding()
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

#Preview {
    Group {
        DevicesList()
            .preferredColorScheme(.dark)
        
        DevicesList()
            .preferredColorScheme(.light)
    }
}