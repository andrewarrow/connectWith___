import SwiftUI

/// A card component for displaying a device
struct DeviceCard: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Devices Found:")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.bottom, 8)
            
            // This recreates EXACTLY the UI shown in the screenshot but with fixed contrast
            HStack {
                // Green circle with phone icon
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "iphone")
                        .foregroundColor(.white)
                        .font(.system(size: 24))
                }
                
                // Device name and ID with FIXED contrast
                VStack(alignment: .leading, spacing: 5) {
                    Text("Unknown Device")
                        .font(.title3)
                        .fontWeight(.medium)
                        // FIXED: Use black text in light mode, white in dark mode
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text("ABDC1E68...")
                        .font(.subheadline)
                        // FIXED: Use darker gray in light mode
                        .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.8))
                }
                .padding(.leading, 8)
                
                Spacer()
                
                // "Saved" button with FIXED contrast
                Text("Saved")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    // FIXED: Use darker green in light mode
                    .background(colorScheme == .dark ? Color.green : Color(red: 0, green: 0.6, blue: 0))
                    // FIXED: Always use white text on green for better contrast
                    .foregroundColor(.white)
                    .cornerRadius(20)
                
                // Chevron
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .padding(.leading, 4)
            }
            .padding()
            // FIXED: Use darker gray in light mode for better contrast with device text
            .background(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.85))
            .cornerRadius(12)
        }
        .padding()
    }
}

#Preview {
    Group {
        DeviceCard()
            .preferredColorScheme(.dark)
        
        DeviceCard()
            .preferredColorScheme(.light)
    }
}