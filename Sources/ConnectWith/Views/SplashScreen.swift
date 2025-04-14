import SwiftUI

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

#Preview {
    SplashScreen(isShowingSplash: .constant(true))
}
