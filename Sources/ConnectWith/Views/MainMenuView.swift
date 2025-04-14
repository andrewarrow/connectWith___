import SwiftUI

struct MainMenuView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Welcome to connectWith___")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                MenuButton(title: "Connect", iconName: "person.2.fill", color: .blue)
                MenuButton(title: "Discover", iconName: "magnifyingglass", color: .green)
                MenuButton(title: "Settings", iconName: "gear", color: .purple)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Main Menu")
        }
    }
}

#Preview {
    MainMenuView()
}
