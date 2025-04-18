import SwiftUI

// MARK: - Guidance Overlay System
/// A view that provides first-time user guidance overlays for the app.
struct GuidanceOverlayView: View {
    @Binding var isVisible: Bool
    @State private var currentStep = 0
    @State private var stepsCompleted = 0
    
    // Guidance steps configuration
    private let steps: [GuidanceStep] = [
        GuidanceStep(
            title: "Welcome to Your Family Calendar",
            description: "Now that you've connected with your first family member, let's learn how to use the calendar.",
            highlightFrame: .zero,
            arrowPosition: .none
        ),
        GuidanceStep(
            title: "Monthly Event Cards",
            description: "Swipe left and right to browse through each month's event card.",
            highlightFrame: .zero,
            arrowPosition: .top
        ),
        GuidanceStep(
            title: "Create Events",
            description: "Tap on any month card to add or edit the event for that month.",
            highlightFrame: .zero,
            arrowPosition: .center
        ),
        GuidanceStep(
            title: "Navigate Months",
            description: "Use these buttons to quickly jump between months.",
            highlightFrame: .zero,
            arrowPosition: .bottom
        ),
        GuidanceStep(
            title: "View Event Details",
            description: "Current month's event details are shown here. Tap 'Edit Event' to make changes.",
            highlightFrame: .zero,
            arrowPosition: .bottom
        )
    ]
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    advanceToNextStep()
                }
                .accessibility(hidden: true)
            
            // Current guidance step
            if currentStep < steps.count {
                let step = steps[currentStep]
                
                VStack(spacing: 0) {
                    // Guidance content card
                    VStack(spacing: 16) {
                        Text(step.title)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                        
                        Text(step.description)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                        
                        // Step indicator
                        HStack(spacing: 8) {
                            ForEach(0..<steps.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentStep ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.top, 8)
                        
                        // Continue button
                        Button(action: {
                            advanceToNextStep()
                        }) {
                            Text(currentStep == steps.count - 1 ? "Got it!" : "Continue")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 20)
                                .background(Color.white)
                                .cornerRadius(16)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                    .padding(.horizontal, 16)
                    .background(Color.blue.opacity(0.9))
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                    .padding(.horizontal, 20)
                    
                    if step.arrowPosition != .none {
                        // Arrow indicator
                        ArrowView(position: step.arrowPosition)
                            .foregroundColor(Color.blue.opacity(0.9))
                            .frame(width: 20, height: 16)
                            .offset(step.arrowOffset)
                    }
                }
                .position(step.contentPosition)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                .animation(.easeInOut(duration: 0.3), value: currentStep)
                .accessibility(hidden: false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.title): \(step.description)")
                .accessibilityAddTraits(.isModal)
                .accessibilityHint(currentStep == steps.count - 1 ? "Double tap to finish tutorial" : "Double tap to continue to next tip")
            }
        }
        .onAppear {
            setupCoachMarkPositions()
            // Save that first-time guidance was shown
            UserDefaults.standard.set(true, forKey: "hasSeenCalendarGuidance")
        }
    }
    
    private func advanceToNextStep() {
        if currentStep < steps.count - 1 {
            currentStep += 1
            stepsCompleted = max(stepsCompleted, currentStep)
            
            // Haptic feedback on step change
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        } else {
            // Complete tutorial
            withAnimation {
                isVisible = false
            }
            
            // Completion haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
    
    private func setupCoachMarkPositions() {
        // In a real implementation, this would calculate actual frames
        // based on GeometryReader or UIKit UIView coordinates
        
        // For demonstration purposes, we're assigning approximate positions
        DispatchQueue.main.async {
            var updatedSteps = steps
            
            // Welcome step
            updatedSteps[0].contentPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2)
            
            // Monthly cards step
            updatedSteps[1].contentPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height * 0.35)
            
            // Create events step
            updatedSteps[2].contentPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height * 0.35)
            
            // Month navigation step
            updatedSteps[3].contentPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height * 0.3)
            
            // Event details step
            updatedSteps[4].contentPosition = CGPoint(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height * 0.4)
            
            // In a real implementation, we would update the steps with calculated frames
            // self.steps = updatedSteps
        }
    }
}

// MARK: - Guidance Step Model
struct GuidanceStep {
    var title: String
    var description: String
    var highlightFrame: CGRect
    var arrowPosition: ArrowPosition
    var contentPosition: CGPoint = .zero
    var arrowOffset: CGSize = .zero
    
    enum ArrowPosition {
        case top, bottom, left, right, center, none
    }
}

// MARK: - Arrow View
struct ArrowView: View {
    let position: GuidanceStep.ArrowPosition
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                
                switch position {
                case .top:
                    // Arrow pointing up
                    path.move(to: CGPoint(x: width / 2, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                case .bottom:
                    // Arrow pointing down
                    path.move(to: CGPoint(x: width / 2, y: height))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: width, y: 0))
                    path.closeSubpath()
                case .left:
                    // Arrow pointing left
                    path.move(to: CGPoint(x: 0, y: height / 2))
                    path.addLine(to: CGPoint(x: width, y: 0))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                case .right:
                    // Arrow pointing right
                    path.move(to: CGPoint(x: width, y: height / 2))
                    path.addLine(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                case .center, .none:
                    // No arrow
                    break
                }
            }
            .fill()
        }
    }
}

// MARK: - GuidanceManager
class GuidanceManager: ObservableObject {
    static let shared = GuidanceManager()
    
    @Published var showCalendarGuidance = false
    
    func checkAndShowCalendarGuidance() {
        // Check if guidance has already been shown
        let hasSeenGuidance = UserDefaults.standard.bool(forKey: "hasSeenCalendarGuidance")
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        // Only show guidance if onboarding is complete and guidance hasn't been shown yet
        if !hasSeenGuidance && hasCompletedOnboarding {
            // Delay slightly to ensure UI is fully loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showCalendarGuidance = true
            }
        }
    }
    
    // For testing purposes - allows forcing guidance to show
    func resetGuidance() {
        UserDefaults.standard.removeObject(forKey: "hasSeenCalendarGuidance")
    }
}

// Preview
#Preview {
    ZStack {
        Color.gray.opacity(0.5)
            .ignoresSafeArea()
        
        Text("Calendar View")
            .font(.largeTitle)
        
        GuidanceOverlayView(isVisible: .constant(true))
    }
}