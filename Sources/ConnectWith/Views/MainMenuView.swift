import SwiftUI

struct MainMenuView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var showingScanningView = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Welcome to connectWith___")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .padding()
                
                MenuButton(
                    title: "Connect", 
                    iconName: "person.2.fill", 
                    color: colorScheme == .dark ? .blue.opacity(0.9) : .blue,
                    action: {
                        showingScanningView = true
                    }
                )
                
                MenuButton(
                    title: "Discover", 
                    iconName: "magnifyingglass", 
                    color: colorScheme == .dark ? .green.opacity(0.9) : .green
                )
                
                MenuButton(
                    title: "Settings", 
                    iconName: "gear", 
                    color: colorScheme == .dark ? .purple.opacity(0.9) : .purple
                )
                
                Spacer()
            }
            .padding()
            .navigationTitle("Main Menu")
            .background(colorScheme == .dark ? Color.black : Color.white)
            .sheet(isPresented: $showingScanningView) {
                ScanningView()
            }
        }
    }
}

#Preview {
    MainMenuView()
}
