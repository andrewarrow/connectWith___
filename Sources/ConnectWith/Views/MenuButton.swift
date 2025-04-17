import SwiftUI

struct MenuButton: View {
    let title: String
    let iconName: String
    let color: Color
    var action: () -> Void = {}
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: iconName)
                    .font(.title)
                    .frame(width: 40)
                    .padding(.trailing, 8)
                
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(colorScheme == .dark ? .gray.opacity(0.7) : .gray)
            }
            .padding()
            .background(colorScheme == .dark ? color.opacity(0.3) : color.opacity(0.15))
            .cornerRadius(10)
            .foregroundColor(color)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    MenuButton(title: "Connect", iconName: "person.2.fill", color: .blue)
        .previewLayout(.sizeThatFits)
        .padding()
}
