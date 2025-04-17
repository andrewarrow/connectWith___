import SwiftUI

@main
struct ConnectWithApp: App {
    @State private var isShowingSplash = true
    @State private var showTestCard = true // For testing the fixed card
    
    var body: some Scene {
        WindowGroup {
            if showTestCard {
                // Show the fixed device card for testing
                DeviceCard()
            } else if isShowingSplash {
                SplashScreen(isShowingSplash: $isShowingSplash)
            } else {
                MainMenuView()
            }
        }
        .preferredColorScheme(.none) // Respect system color scheme
    }
}
