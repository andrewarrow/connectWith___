import SwiftUI
import CoreData

struct EventEditView: View {
    // Environment and presentation properties
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.sizeCategory) private var sizeCategory
    @Environment(\.managedObjectContext) private var viewContext
    
    // Event-related properties
    let month: Month
    let event: Event?
    var onSave: ((String, String, Int) -> Void)?
    var onDelete: (() -> Void)?
    
    // Form state
    @State private var title: String
    @State private var location: String
    @State private var day: Int
    @State private var showDeleteConfirmation = false
    @State private var showPreview = true
    
    // Form validation
    @State private var titleError: String?
    @State private var locationError: String?
    
    // Initialization with defaults from existing event or empty values
    init(month: Month, event: Event?, onSave: ((String, String, Int) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
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
                // Event details section
                Section(header: Text("Event Details")
                    .accessibilityAddTraits(.isHeader)) {
                    
                    // Title field with validation
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Event Title", text: $title)
                            .onChange(of: title) { newValue in
                                validateTitle(newValue)
                            }
                            .accessibilityLabel("Event Title")
                            .accessibilityHint("Enter a title for this event")
                            .submitLabel(.next)
                        
                        if let error = titleError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .accessibilityLabel("Title error: \(error)")
                        }
                    }
                    
                    // Location field with validation
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Location", text: $location)
                            .onChange(of: location) { newValue in
                                validateLocation(newValue)
                            }
                            .accessibilityLabel("Location")
                            .accessibilityHint("Enter the location for this event")
                            .submitLabel(.next)
                        
                        if let error = locationError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .accessibilityLabel("Location error: \(error)")
                        }
                    }
                    
                    // Day picker
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
                
                // Preview section
                if showPreview {
                    Section(header: Text("Preview")
                        .accessibilityAddTraits(.isHeader)) {
                        
                        VStack(alignment: .center) {
                            EventCardPreview(
                                title: title,
                                location: location,
                                day: day,
                                month: month
                            )
                            .padding(.vertical, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Preview of the event card for \(month.rawValue)")
                    }
                }
                
                // Delete button section (only for existing events)
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
                // Cancel button
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        presentationMode.wrappedValue.dismiss()
                    }
                    .accessibilityHint("Dismisses this form without saving changes")
                }
                
                // Save button
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        
                        // Validate before saving
                        if validateForm() {
                            if let saveHandler = onSave {
                                saveHandler(title, location, day)
                            } else {
                                saveEvent()
                            }
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    .disabled(!isFormValid())
                    .accessibilityLabel(isFormValid() ? "Save" : "Save (Disabled)")
                    .accessibilityHint(isFormValid() ? 
                        "Saves the event details and returns to the calendar view" : 
                        "Cannot save until title and location are filled in")
                }
            }
            .alert(isPresented: $showDeleteConfirmation) {
                Alert(
                    title: Text("Delete Event"),
                    message: Text("Are you sure you want to delete this event? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        if let deleteHandler = onDelete {
                            deleteHandler()
                        } else {
                            deleteEvent()
                        }
                        presentationMode.wrappedValue.dismiss()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .onAppear(perform: validateForm)
        .accessibilityAction(.escape) {
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    // MARK: - Form Validation
    
    // Validate title field
    private func validateTitle(_ value: String) {
        if value.isEmpty {
            titleError = "Title is required"
        } else if value.count > 50 {
            titleError = "Title must be 50 characters or less"
        } else {
            titleError = nil
        }
    }
    
    // Validate location field
    private func validateLocation(_ value: String) {
        if value.isEmpty {
            locationError = "Location is required"
        } else if value.count > 100 {
            locationError = "Location must be 100 characters or less"
        } else {
            locationError = nil
        }
    }
    
    // Validate entire form
    private func validateForm() -> Bool {
        validateTitle(title)
        validateLocation(location)
        return isFormValid()
    }
    
    // Check if form is valid
    private func isFormValid() -> Bool {
        return !title.isEmpty && !location.isEmpty && titleError == nil && locationError == nil
    }
    
    // MARK: - Event CRUD Operations
    
    // Save the event to CoreData
    private func saveEvent() {
        if let event = event {
            // Create edit history record
            let history = EditHistory.create(in: viewContext, for: event)
            history.recordChanges(
                previousTitle: event.title,
                newTitle: title,
                previousLocation: event.location,
                newLocation: location,
                previousDay: Int(event.day),
                newDay: day
            )
            
            // Update existing event
            event.title = title
            event.location = location
            event.day = Int16(day)
            event.lastModifiedAt = Date()
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
            let nsError = error as NSError
            print("Error saving event: \(nsError), \(nsError.userInfo)")
            // In a production app, we would want to show this error to the user
        }
    }
    
    // Delete the event from CoreData
    private func deleteEvent() {
        if let event = event {
            viewContext.delete(event)
            
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                print("Error deleting event: \(nsError), \(nsError.userInfo)")
                // In a production app, we would want to show this error to the user
            }
        }
    }
}

// MARK: - Preview Component

// Card preview component
struct EventCardPreview: View {
    let title: String
    let location: String
    let day: Int
    let month: Month
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.sizeCategory) var sizeCategory
    
    private var displayTitle: String {
        return title.isEmpty ? "[Title]" : title
    }
    
    private var displayLocation: String {
        return location.isEmpty ? "[Location]" : location
    }
    
    // Card color from month
    private var cardColor: Color {
        Color(month.color)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with month name
            Text(month.rawValue)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            // Event title with prominent display
            Text(displayTitle)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            
            Spacer()
            
            // Event details with smaller text
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(.white.opacity(0.9))
                    .imageScale(sizeCategory.isAccessibilityCategory ? .large : .small)
                
                Text(displayLocation)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            
            // Date with icon
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .foregroundColor(.white.opacity(0.9))
                    .imageScale(sizeCategory.isAccessibilityCategory ? .large : .small)
                
                Text("Day \(day)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(12)
        .frame(width: 250, height: 150)
        .background(cardColor)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Previews

struct EventEditView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.shared.container.viewContext
        
        // Create a sample event for preview
        let sampleEvent = Event.create(
            in: context,
            title: "Family Reunion",
            location: "Grandma's House",
            day: 15,
            month: .july
        )
        
        return Group {
            // Preview add new event
            EventEditView(month: .march, event: nil)
                .environment(\.managedObjectContext, context)
                .previewDisplayName("Add New Event")
            
            // Preview edit existing event
            EventEditView(month: .july, event: sampleEvent)
                .environment(\.managedObjectContext, context)
                .previewDisplayName("Edit Existing Event")
                .preferredColorScheme(.dark)
        }
    }
}