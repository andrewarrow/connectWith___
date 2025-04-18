import SwiftUI
import CoreData

struct FamilyCalendarView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var currentMonthIndex = Calendar.current.component(.month, from: Date()) - 1 // 0-based index
    @State private var isEditingEvent = false
    @State private var selectedMonth: Month?
    @State private var selectedEvent: Event?
    
    @FetchRequest(
        entity: Event.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.month, ascending: true)],
        animation: .default)
    private var events: FetchedResults<Event>
    
    // Get the current month's events organized by month
    private var eventsByMonth: [Month: Event] {
        var result: [Month: Event] = [:]
        
        for event in events {
            // Only include the most recently modified event for each month
            if let month = event.monthEnum {
                if let existingEvent = result[month] {
                    // Keep the more recently modified event
                    if event.lastModifiedAt > existingEvent.lastModifiedAt {
                        result[month] = event
                    }
                } else {
                    result[month] = event
                }
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Month carousel
                    TabView(selection: $currentMonthIndex) {
                        ForEach(0..<12) { index in
                            let month = Month.allCases[index]
                            MonthCardContainer(
                                month: month,
                                event: eventsByMonth[month],
                                onTap: {
                                    selectedMonth = month
                                    selectedEvent = eventsByMonth[month]
                                    isEditingEvent = true
                                }
                            )
                            .tag(index)
                            .id("monthCard-\(index)") // Provide stable ID for focus
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                    .frame(height: 260)
                    .accessibilityAction(.escape) {
                        // Allow escape key to leave carousel
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Monthly event cards")
                    .accessibilityHint("Swipe left or right to navigate between months")
                    
                    // Month selector with text and buttons
                    HStack(spacing: 24) {
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            
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
                        .accessibilityLabel("Previous month")
                        .accessibilityHint("Navigate to \(currentMonthIndex > 0 ? Month.allCases[currentMonthIndex - 1].rawValue : "no previous month")")
                        
                        Text(Month.allCases[currentMonthIndex].rawValue)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .frame(minWidth: 120)
                            .accessibilityAddTraits(.isHeader)
                        
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            
                            withAnimation {
                                currentMonthIndex = min(11, currentMonthIndex + 1)
                            }
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.title3)
                                .foregroundColor(currentMonthIndex < 11 ? .blue : .gray)
                                .frame(width: 44, height: 44)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(22)
                        }
                        .disabled(currentMonthIndex >= 11)
                        .accessibilityLabel("Next month")
                        .accessibilityHint("Navigate to \(currentMonthIndex < 11 ? Month.allCases[currentMonthIndex + 1].rawValue : "no next month")")
                    }
                    .padding(.horizontal)
                    
                    // Month summary
                    monthSummaryView
                    
                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("Family Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isEditingEvent) {
                if let month = selectedMonth {
                    EventEditView(
                        month: month,
                        event: selectedEvent,
                        onSave: { title, location, day in
                            saveEvent(
                                month: month,
                                title: title,
                                location: location,
                                day: day,
                                existingEvent: selectedEvent
                            )
                        },
                        onDelete: {
                            if let event = selectedEvent {
                                deleteEvent(event)
                            }
                        }
                    )
                    .environment(\.managedObjectContext, viewContext)
                }
            }
        }
    }
    
    // View that shows a summary of the current month's event
    private var monthSummaryView: some View {
        let currentMonth = Month.allCases[currentMonthIndex]
        let currentEvent = eventsByMonth[currentMonth]
        
        return VStack(alignment: .leading, spacing: 10) {
            Text("Event Details")
                .font(.headline)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)
            
            VStack(alignment: .leading, spacing: 12) {
                if let event = currentEvent {
                    // Display event details
                    DetailsRow(icon: "text.alignleft", title: "Event", value: event.title)
                    
                    if let location = event.location {
                        DetailsRow(icon: "mappin.and.ellipse", title: "Location", value: location)
                    }
                    
                    DetailsRow(icon: "calendar", title: "Date", value: "Day \(event.day)")
                    
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        
                        selectedMonth = currentMonth
                        selectedEvent = event
                        isEditingEvent = true
                    }) {
                        Text("Edit Event")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .accessibilityHint("Opens a form to edit the \(currentMonth.rawValue) event")
                    .padding(.top, 8)
                } else {
                    // Empty state
                    HStack {
                        Spacer()
                        
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 32))
                                .foregroundColor(.gray)
                                .accessibility(hidden: true) // Hide from VoiceOver since it's decorative
                            
                            Text("No event planned for \(currentMonth.rawValue)")
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .accessibilityLabel("No event planned for \(currentMonth.rawValue)")
                            
                            Button(action: {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                
                                selectedMonth = currentMonth
                                selectedEvent = nil
                                isEditingEvent = true
                            }) {
                                Text("Add Event")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 120)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                            .accessibilityHint("Opens a form to add an event for \(currentMonth.rawValue)")
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            .accessibilityElement(children: .contain)  // Keep child elements accessible to VoiceOver
        }
    }
    
    // MARK: - Event CRUD Operations
    
    private func saveEvent(month: Month, title: String, location: String, day: Int, existingEvent: Event?) {
        withAnimation {
            if let event = existingEvent {
                // Update existing event
                event.title = title
                event.location = location
                event.day = Int16(day)
                event.lastModifiedAt = Date()
                // This should be replaced with actual device ID when available
                event.lastModifiedBy = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            } else {
                // Create new event
                let newEvent = Event.create(
                    in: viewContext,
                    title: title,
                    location: location,
                    day: day,
                    month: month
                )
                // Create initial edit history
                let history = EditHistory.create(in: viewContext, for: newEvent)
                history.recordChanges(
                    previousTitle: nil,
                    newTitle: title,
                    previousLocation: nil,
                    newLocation: location,
                    previousDay: nil,
                    newDay: day
                )
            }
            
            do {
                try viewContext.save()
            } catch {
                // Replace this with real error handling
                let nsError = error as NSError
                print("Error saving context: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func deleteEvent(_ event: Event) {
        withAnimation {
            viewContext.delete(event)
            
            do {
                try viewContext.save()
            } catch {
                // Replace this with real error handling
                let nsError = error as NSError
                print("Error deleting event: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

// MARK: - Supporting Views

// Container for a single month's card
struct MonthCardContainer: View {
    let month: Month
    let event: Event?
    let onTap: () -> Void
    
    var body: some View {
        VStack {
            EventCardView(
                event: event,
                month: month,
                onTap: onTap
            )
            .padding(.horizontal)
            // Ensure proper keyboard focus navigation
            .focusable(true)
        }
    }
}

// Details row helper view
struct DetailsRow: View {
    let icon: String
    let title: String
    let value: String
    @Environment(\.sizeCategory) var sizeCategory
    
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
                .imageScale(sizeCategory.isAccessibilityCategory ? .large : .medium)
                .accessibility(hidden: true) // Hide icon from VoiceOver
            
            Text(title + ":")
                .foregroundColor(.secondary)
                .frame(width: sizeCategory.isAccessibilityCategory ? 90 : 70, alignment: .leading)
                .minimumScaleFactor(0.8)
            
            Text(value)
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .padding(.vertical, 2) // Extra padding for touch targets
    }
}

// Event Edit Sheet
struct EventEditSheet: View {
    let month: Month
    let event: Event?
    let onSave: (String, String, Int) -> Void
    let onDelete: () -> Void
    
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var title: String
    @State private var location: String
    @State private var day: Int
    @State private var showDeleteConfirmation = false
    
    init(month: Month, event: Event?, onSave: @escaping (String, String, Int) -> Void, onDelete: @escaping () -> Void) {
        self.month = month
        self.event = event
        self.onSave = onSave
        self.onDelete = onDelete
        
        // Initialize state
        _title = State(initialValue: event?.title ?? "")
        _location = State(initialValue: event?.location ?? "")
        _day = State(initialValue: Int(event?.day ?? 1))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Event Details")
                    .accessibilityAddTraits(.isHeader)) {
                    
                    TextField("Event Title", text: $title)
                        .accessibilityLabel("Event Title")
                        .accessibilityHint("Enter a title for this event")
                        .submitLabel(.next)
                    
                    TextField("Location", text: $location)
                        .accessibilityLabel("Location")
                        .accessibilityHint("Enter the location for this event")
                        .submitLabel(.next)
                    
                    VStack(alignment: .leading) {
                        Text("Day")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        
                        Picker("Day", selection: $day) {
                            ForEach(1...month.maxDays, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .accessibilityLabel("Day of month")
                        .accessibilityHint("Select the day in \(month.rawValue) for this event")
                    }
                }
                
                if event != nil {
                    Section {
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .heavy)
                            generator.impactOccurred()
                            showDeleteConfirmation = true
                        }) {
                            HStack {
                                Spacer()
                                Text("Delete Event")
                                    .foregroundColor(.red)
                                    .padding(.vertical, 8) // Larger touch target
                                Spacer()
                            }
                        }
                        .accessibilityLabel("Delete Event")
                        .accessibilityHint("Deletes this event from the \(month.rawValue) card")
                    }
                }
            }
            .navigationTitle("\(event == nil ? "Add" : "Edit") \(month.rawValue) Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .accessibilityHint("Dismisses this form without saving changes")
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        onSave(title, location, day)
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(title.isEmpty || location.isEmpty)
                    .accessibilityLabel(title.isEmpty || location.isEmpty ? "Save (Disabled)" : "Save")
                    .accessibilityHint(title.isEmpty || location.isEmpty ? 
                        "Cannot save until title and location are filled in" : 
                        "Saves the event details and returns to the calendar view")
                }
            }
            .alert(isPresented: $showDeleteConfirmation) {
                Alert(
                    title: Text("Delete Event"),
                    message: Text("Are you sure you want to delete this event? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        onDelete()
                        presentationMode.wrappedValue.dismiss()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .accessibilityAction(.escape) {
            presentationMode.wrappedValue.dismiss()
        }
    }
}

// Extension to Month for convenience
extension Month {
    // Maximum days in each month (simplified)
    var maxDays: Int {
        switch self {
        case .february: 
            // Account for leap years, but since we don't track the year, use maximum
            return 29
        case .april, .june, .september, .november:
            return 30
        default:
            return 31
        }
    }
}

#Preview {
    FamilyCalendarView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}