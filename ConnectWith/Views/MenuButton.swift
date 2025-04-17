import SwiftUI

struct MenuButton: View {
    let title: String
    let iconName: String
    let color: Color
    var action: (() -> Void)? = nil
    
    var body: some View {
        Button(action: {
            action?() ?? print("\(title) button tapped")
        }) {
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
                    .foregroundColor(.gray)
            }
            .padding()
            .background(color.opacity(0.2))
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
