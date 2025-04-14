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
