import SwiftUI

struct SplashScreen: View {
    @Binding var isShowingSplash: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.blue.opacity(0.6) : Color.blue.opacity(0.8))
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

#Preview {
    SplashScreen(isShowingSplash: .constant(true))
}
