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
                    Section(header: HStack {
                        Text("Preview")
                            .accessibilityAddTraits(.isHeader)
                        
                        Spacer()
                        
                        // Toggle button to hide/show preview
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showPreview.toggle()
                            }
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }) {
                            Image(systemName: "eye.slash")
                                .foregroundColor(.secondary)
                                .imageScale(.small)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .accessibilityLabel("Hide preview")
                    }) {
                        VStack(alignment: .center, spacing: 8) {
                            // Preview card
                            EventCardPreview(
                                title: title,
                                location: location,
                                day: day,
                                month: month
                            )
                            .padding(.vertical, 8)
                            
                            // Validation status
                            if let titleError = titleError {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                    Text(titleError)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                            }
                            
                            if let locationError = locationError {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                    Text(locationError)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                            }
                            
                            // Card information
                            Text("This is how your event will look on the calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Preview of the event card for \(month.rawValue)")
                    }
                } else {
                    // Collapsed preview section
                    Section {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showPreview.toggle()
                            }
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }) {
                            HStack {
                                Image(systemName: "eye")
                                    .foregroundColor(.blue)
                                
                                Text("Show Preview")
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                        }
                        .accessibilityLabel("Show preview")
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
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            titleError = "Title is required"
        } else if trimmedValue.count < 3 {
            titleError = "Title must be at least 3 characters"
        } else if trimmedValue.count > 50 {
            titleError = "Title must be 50 characters or less"
        } else if !trimmedValue.first!.isLetter {
            titleError = "Title must start with a letter"
        } else {
            titleError = nil
        }
    }
    
    // Validate location field
    private func validateLocation(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue.isEmpty {
            locationError = "Location is required"
        } else if trimmedValue.count < 3 {
            locationError = "Location must be at least 3 characters"
        } else if trimmedValue.count > 100 {
            locationError = "Location must be 100 characters or less"
        } else {
            locationError = nil
        }
    }
    
    // Validate day selection for the current month
    private func validateDay(_ day: Int) -> Bool {
        return day > 0 && day <= month.maxDays
    }
    
    // Validate entire form
    private func validateForm() -> Bool {
        validateTitle(title)
        validateLocation(location)
        return isFormValid()
    }
    
    // Check if form is valid
    private func isFormValid() -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedTitle.isEmpty && !trimmedLocation.isEmpty && 
               titleError == nil && locationError == nil && 
               validateDay(day)
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
    
    // States for animation
    @State private var isAnimating = false
    @State private var showValidation = false
    
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
    
    // Validation status
    private var isValid: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return !trimmedTitle.isEmpty && trimmedTitle.count >= 3 && 
               trimmedTitle.count <= 50 && trimmedTitle.first?.isLetter == true &&
               !trimmedLocation.isEmpty && trimmedLocation.count >= 3 &&
               trimmedLocation.count <= 100 && day > 0 && day <= month.maxDays
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with month name and validation status
            HStack {
                Text(month.rawValue)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
                
                if showValidation {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(isValid ? .green : .yellow)
                        .imageScale(.large)
                        .opacity(isAnimating ? 1.0 : 0.5)
                        .animation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
                        .onAppear {
                            if !isValid {
                                isAnimating = true
                            }
                        }
                        .onChange(of: isValid) { newValue in
                            isAnimating = !newValue
                        }
                }
            }
            
            // Event title with prominent display
            Text(displayTitle)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 4)
            
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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(showValidation ? (isValid ? Color.green.opacity(0.4) : Color.yellow.opacity(0.6)) : Color.clear, lineWidth: 2)
        )
        .onAppear {
            // Show validation status after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showValidation = true
                }
            }
        }
        // Update validation when any input changes
        .onChange(of: title) { _ in updateValidation() }
        .onChange(of: location) { _ in updateValidation() }
        .onChange(of: day) { _ in updateValidation() }
    }
    
    // Function to update validation with animation
    private func updateValidation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            // This triggers the onChange of isValid
            let _ = isValid
        }
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
        
        // Create an invalid sample event to showcase validation
        let invalidSampleEvent = Event.create(
            in: context,
            title: "A",  // Too short - will trigger validation error
            location: "H", // Too short - will trigger validation error
            day: 15,
            month: .february
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
            
            // Preview with validation errors
            EventEditView(month: .february, event: invalidSampleEvent)
                .environment(\.managedObjectContext, context)
                .previewDisplayName("With Validation Errors")
        }
    }
}

// Preview for just the card
struct EventCardPreview_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Valid event preview
            EventCardPreview(
                title: "Family Reunion",
                location: "Grandma's House",
                day: 15,
                month: .july
            )
            
            // Invalid event preview
            EventCardPreview(
                title: "A",
                location: "B",
                day: 35, // Invalid day
                month: .february
            )
            
            // Empty event preview
            EventCardPreview(
                title: "",
                location: "",
                day: 1,
                month: .december
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}