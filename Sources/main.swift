import SwiftUI

@main
struct ConnectWithApp: App {
    @State private var isShowingSplash = true
    
    var body: some Scene {
        WindowGroup {
            if isShowingSplash {
                SplashScreen(isShowingSplash: $isShowingSplash)
            } else {
                MainMenuView()
            }
        }
    }
}

struct SplashScreen: View {
    @Binding var isShowingSplash: Bool
    
    var body: some View {
        ZStack {
            Color.blue.opacity(0.7)
                .ignoresSafeArea()
            
            VStack {
                Text("connectWith___")
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
                }
            }
        }
    }
}

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

struct MenuButton: View {
    let title: String
    let iconName: String
    let color: Color
    
    var body: some View {
        Button(action: {
            // Action for button
            print("\(title) button tapped")
        }) {
            HStack {
                Image(systemName: iconName)
                    .font(.title)
                    .frame(width: 40)
                
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
