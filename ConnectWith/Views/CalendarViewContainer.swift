import SwiftUI

// Month model for consistent use across the app
enum Month: String, CaseIterable, Identifiable {
    case january = "January"
    case february = "February"
    case march = "March"
    case april = "April"
    case may = "May"
    case june = "June"
    case july = "July"
    case august = "August"
    case september = "September"
    case october = "October"
    case november = "November"
    case december = "December"
    
    var id: String { self.rawValue }
    
    var colorName: String {
        switch self {
        case .january: return "card.january"
        case .february: return "card.february"
        case .march: return "card.march"
        case .april: return "card.april"
        case .may: return "card.may"
        case .june: return "card.june"
        case .july: return "card.july"
        case .august: return "card.august"
        case .september: return "card.september"
        case .october: return "card.october"
        case .november: return "card.november"
        case .december: return "card.december"
        }
    }
    
    // Get the actual Color from the asset
    var color: Color {
        return Color(colorName)
    }
    
    // Get the month number (1-12)
    var number: Int {
        switch self {
        case .january: return 1
        case .february: return 2
        case .march: return 3
        case .april: return 4
        case .may: return 5
        case .june: return 6
        case .july: return 7
        case .august: return 8
        case .september: return 9
        case .october: return 10
        case .november: return 11
        case .december: return 12
        }
    }
    
    // Get the max days in this month (simplified)
    var maxDays: Int {
        switch self {
        case .february: return 29 // Account for leap years
        case .april, .june, .september, .november: return 30
        default: return 31
        }
    }
}

// Monthly event model
struct MonthlyEvent: Identifiable {
    var id = UUID()
    var title: String
    var location: String
    var day: Int
    var month: Month
    var hasBeenEdited: Bool = false
    
    // Empty state event (used for months without events)
    static func emptyEvent(for month: Month) -> MonthlyEvent {
        MonthlyEvent(title: "No Event", location: "Add an event for \(month.rawValue)", day: 1, month: month)
    }
    
    // Create default events for all months
    static var defaultEvents: [MonthlyEvent] {
        Month.allCases.map { month in
            MonthlyEvent.emptyEvent(for: month)
        }
    }
}

// Main calendar view container
struct CalendarViewContainer: View {
    @State private var monthlyEvents = MonthlyEvent.defaultEvents
    @State private var currentMonthIndex = Calendar.current.component(.month, from: Date()) - 1 // 0-based index for current month
    @Environment(\.presentationMode) private var presentationMode
    @State private var isEditing = false
    @State private var dragOffset: CGFloat = 0
    
    // Layout constants
    private let cardHeight: CGFloat = 220
    private let cardPadding: CGFloat = 16
    private let pageControlHeight: CGFloat = 30
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Month pager view
                    TabView(selection: $currentMonthIndex) {
                        ForEach(0..<monthlyEvents.count, id: \.self) { index in
                            MonthCardView(event: $monthlyEvents[index])
                                .padding(.horizontal, cardPadding)
                                .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                    .frame(height: cardHeight + 40)
                    .onChange(of: currentMonthIndex) { newValue in
                        // Add haptic feedback when month changes
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }
                    
                    // Month navigation
                    HStack(spacing: 24) {
                        Button(action: {
                            withAnimation {
                                currentMonthIndex = max(0, currentMonthIndex - 1)
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title3)
                                .foregroundColor(currentMonthIndex > 0 ? .blue : .gray)
                                .frame(width: 44, height: 44)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(22)
                        }
                        .disabled(currentMonthIndex <= 0)
                        
                        Text(monthlyEvents[currentMonthIndex].month.rawValue)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .frame(minWidth: 120)
                        
                        Button(action: {
                            withAnimation {
                                currentMonthIndex = min(monthlyEvents.count - 1, currentMonthIndex + 1)
                            }
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.title3)
                                .foregroundColor(currentMonthIndex < monthlyEvents.count - 1 ? .blue : .gray)
                                .frame(width: 44, height: 44)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(22)
                        }
                        .disabled(currentMonthIndex >= monthlyEvents.count - 1)
                    }
                    .padding(.vertical, 8)
                    
                    // Event details section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Event Details")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                // Toggle editing mode for current event
                                isEditing.toggle()
                            }) {
                                Text(isEditing ? "Done" : "Edit")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Divider()
                        
                        if isEditing {
                            EditEventView(event: $monthlyEvents[currentMonthIndex], isEditing: $isEditing)
                        } else {
                            EventDetailsView(event: monthlyEvents[currentMonthIndex])
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .animation(.easeInOut, value: isEditing)
                    
                    Spacer()
                }
                .navigationTitle("Family Calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            // Reset the current month event to empty
                            monthlyEvents[currentMonthIndex] = MonthlyEvent.emptyEvent(for: monthlyEvents[currentMonthIndex].month)
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .disabled(monthlyEvents[currentMonthIndex].title == "No Event")
                    }
                }
            }
        }
    }
}

// Month card view component
struct MonthCardView: View {
    @Binding var event: MonthlyEvent
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack {
            ZStack {
                // Card background
                RoundedRectangle(cornerRadius: 16)
                    .fill(event.month.color)
                    .shadow(radius: 5)
                
                // Card content
                VStack(alignment: .leading, spacing: 12) {
                    // Header with month name
                    HStack {
                        Text(event.month.rawValue)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // If there's an event, show a checkmark
                        if event.title != "No Event" {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                                .font(.title3)
                        }
                    }
                    
                    // Event details or empty state
                    if event.title == "No Event" {
                        emptyStateView
                    } else {
                        eventDetailsView
                    }
                }
                .padding()
            }
            .frame(height: 220)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(event.month.rawValue) card with \(event.title == "No Event" ? "no event" : "event: \(event.title)")")
            .accessibilityHint("Tap to edit this month's event")
        }
    }
    
    // View for when there's no event
    var emptyStateView: some View {
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
            
            Text("Tap to add an event for \(event.month.rawValue)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // View for when there is an event
    var eventDetailsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Event title
            Text(event.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(2)
            
            Spacer()
            
            // Event details
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text(event.location)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                }
                
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("Day \(event.day)")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }
}

// View for displaying event details
struct EventDetailsView: View {
    let event: MonthlyEvent
    
    var body: some View {
        if event.title == "No Event" {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
                
                Text("No event planned for \(event.month.rawValue)")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("Tap Edit to add one")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                DetailsRow(icon: "calendar.badge.exclamationmark", title: "Month", value: event.month.rawValue)
                DetailsRow(icon: "calendar", title: "Day", value: "\(event.day)")
                DetailsRow(icon: "text.alignleft", title: "Event", value: event.title)
                DetailsRow(icon: "mappin.and.ellipse", title: "Location", value: event.location)
                
                if event.hasBeenEdited {
                    HStack {
                        Image(systemName: "pencil.circle")
                            .foregroundColor(.blue)
                        
                        Text("This event has been edited")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// Helper view for event details rows
struct DetailsRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(title + ":")
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .foregroundColor(.primary)
        }
    }
}

// View for editing an event
struct EditEventView: View {
    @Binding var event: MonthlyEvent
    @Binding var isEditing: Bool
    @State private var editedTitle: String
    @State private var editedLocation: String
    @State private var editedDay: Int
    
    init(event: Binding<MonthlyEvent>, isEditing: Binding<Bool>) {
        self._event = event
        self._isEditing = isEditing
        
        // Initialize the editing state with current values
        self._editedTitle = State(initialValue: event.wrappedValue.title == "No Event" ? "" : event.wrappedValue.title)
        self._editedLocation = State(initialValue: event.wrappedValue.location == "Add an event for \(event.wrappedValue.month.rawValue)" ? "" : event.wrappedValue.location)
        self._editedDay = State(initialValue: event.wrappedValue.day)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Title field
            VStack(alignment: .leading, spacing: 4) {
                Text("Event Title")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                TextField("Enter event title", text: $editedTitle)
                    .padding(10)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
            }
            
            // Location field
            VStack(alignment: .leading, spacing: 4) {
                Text("Location")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                TextField("Enter location", text: $editedLocation)
                    .padding(10)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
            }
            
            // Day picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Day of Month")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                Picker("Day", selection: $editedDay) {
                    ForEach(1...event.month.maxDays, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(height: 100)
                .clipped()
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
            
            // Save button
            Button(action: {
                saveChanges()
                isEditing = false
            }) {
                Text("Save Changes")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        isFormValid ?
                        LinearGradient(gradient: Gradient(colors: [.blue, .indigo]), startPoint: .leading, endPoint: .trailing) :
                        LinearGradient(gradient: Gradient(colors: [.gray]), startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(12)
            }
            .disabled(!isFormValid)
        }
    }
    
    private var isFormValid: Bool {
        return !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !editedLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveChanges() {
        event.title = editedTitle
        event.location = editedLocation
        event.day = editedDay
        event.hasBeenEdited = true
        
        // Add haptic feedback for save
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

#Preview {
    CalendarViewContainer()
}