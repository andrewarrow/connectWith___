import SwiftUI

struct EventCardView: View {
    var event: Event?
    var month: Month
    var onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sizeCategory) var sizeCategory
    
    // Get the appropriate month color
    private var cardColor: Color {
        Color(month.color)
    }
    
    // Determine if there's an event or if we need to show empty state
    private var isEmpty: Bool {
        return event == nil
    }
    
    // For haptic feedback
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            onTap()
        }) {
            ZStack {
                // Card background with shadow
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardColor)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                
                // Card content
                VStack(alignment: .leading, spacing: 12) {
                    // Header with month name
                    HStack {
                        Text(month.rawValue)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge) // Limit maximum size
                        
                        Spacer()
                        
                        // If there's an event, show a checkmark
                        if !isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                                .font(.title3)
                                .imageScale(sizeCategory.isAccessibilityCategory ? .large : .medium)
                        }
                    }
                    
                    if isEmpty {
                        emptyStateView
                    } else {
                        populatedStateView
                    }
                }
                .padding(16)
            }
            .frame(height: calculateCardHeight())
            // Accessibility handling
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits([.isButton, .isHeader])
            // Focus state for keyboard navigation
            .contentShape(Rectangle()) // Ensure the entire card is tappable
            // Scaleup effect on press
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        // Gestures to handle press state
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in self.isPressed = true }
                .onEnded { _ in self.isPressed = false }
        )
    }
    
    // Adaptive card height based on Dynamic Type
    private func calculateCardHeight() -> CGFloat {
        let baseHeight: CGFloat = 220
        
        switch sizeCategory {
        case .accessibilityMedium:
            return baseHeight * 1.2
        case .accessibilityLarge:
            return baseHeight * 1.3
        case .accessibilityExtraLarge:
            return baseHeight * 1.4
        case .accessibilityExtraExtraLarge:
            return baseHeight * 1.5
        case .accessibilityExtraExtraExtraLarge:
            return baseHeight * 1.6
        default:
            return baseHeight
        }
    }
    
    // Dynamic accessibility label based on card state
    private var accessibilityLabel: String {
        if isEmpty {
            return "\(month.rawValue) card with no event planned"
        } else {
            let locationInfo = event?.location != nil ? ", location: \(event!.location!)" : ""
            let dayInfo = event?.day != nil ? ", day: \(event!.day)" : ""
            
            return "\(month.rawValue) card with event: \(event!.title)\(locationInfo)\(dayInfo)"
        }
    }
    
    // Dynamic accessibility hint based on card state
    private var accessibilityHint: String {
        if isEmpty {
            return "Double tap to add an event for \(month.rawValue)"
        } else {
            return "Double tap to edit this event"
        }
    }
    
    // View when no event exists for the month
    private var emptyStateView: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()
            
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.9))
                .imageScale(sizeCategory.isAccessibilityCategory ? .large : .medium)
                .accessibility(hidden: true) // Hide from VoiceOver since it's decorative
            
            Text("No Event Planned")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3) // Support larger sizes but with limit
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            
            Text("Tap to add an event for \(month.rawValue)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // View when an event exists for the month
    private var populatedStateView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Event title with prominent display
            Text(event?.title ?? "")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(2)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .minimumScaleFactor(0.7)
            
            Spacer()
            
            // Event details with smaller text
            VStack(alignment: .leading, spacing: 8) {
                // Location with icon
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.white.opacity(0.9))
                        .imageScale(sizeCategory.isAccessibilityCategory ? .large : .medium)
                        .accessibility(hidden: true) // Hide icon from VoiceOver
                    
                    Text(event?.location ?? "")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .minimumScaleFactor(0.7)
                        .accessibility(label: Text("Location: \(event?.location ?? "None")"))
                }
                
                // Date with icon
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundColor(.white.opacity(0.9))
                        .imageScale(sizeCategory.isAccessibilityCategory ? .large : .medium)
                        .accessibility(hidden: true) // Hide icon from VoiceOver
                    
                    if let day = event?.day {
                        Text("Day \(day)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .minimumScaleFactor(0.7)
                            .accessibility(label: Text("Date: Day \(day)"))
                    } else {
                        Text("No date set")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                            .minimumScaleFactor(0.7)
                            .accessibility(label: Text("No date set"))
                    }
                }
            }
        }
    }
}

// Preview
struct EventCardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Event card with event
            EventCardView(
                event: Event.create(
                    in: PersistenceController.shared.container.viewContext,
                    title: "Family Reunion",
                    location: "Grandma's House",
                    day: 15,
                    month: .july
                ),
                month: .july,
                onTap: {}
            )
            
            // Empty card
            EventCardView(
                event: nil,
                month: .december,
                onTap: {}
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .previewLayout(.sizeThatFits)
    }
}