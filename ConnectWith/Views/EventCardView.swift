import SwiftUI

struct EventCardView: View {
    var event: Event?
    var month: Month
    var onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    // Get the appropriate month color
    private var cardColor: Color {
        Color(month.color)
    }
    
    // Determine if there's an event or if we need to show empty state
    private var isEmpty: Bool {
        return event == nil
    }
    
    var body: some View {
        Button(action: onTap) {
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
                        
                        Spacer()
                        
                        // If there's an event, show a checkmark
                        if !isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                                .font(.title3)
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
            .frame(height: 220)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(month.rawValue) card with \(isEmpty ? "no event" : "event: \(event!.title)")")
            .accessibilityHint("Tap to edit this month's event")
            .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // View when no event exists for the month
    private var emptyStateView: some View {
        VStack(alignment: .center, spacing: 16) {
            Spacer()
            
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.9))
            
            Text("No Event Planned")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Tap to add an event for \(month.rawValue)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
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
            
            Spacer()
            
            // Event details with smaller text
            VStack(alignment: .leading, spacing: 8) {
                // Location with icon
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text(event?.location ?? "")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
                
                // Date with icon
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundColor(.white.opacity(0.9))
                    
                    if let day = event?.day {
                        Text("Day \(day)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                    } else {
                        Text("No date set")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
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