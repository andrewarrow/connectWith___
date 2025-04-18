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
    @State private var showSaveConfirmation = false
    @State private var showPreview = true
    
    // Feedback state
    @State private var showSaveSuccess = false
    @State private var showSaveError = false
    @State private var errorMessage = ""
    
    // Form validation
    @State private var titleError: String?
    @State private var locationError: String?
    
    // Data manager for CoreData operations
    private let dataManager = DataManager.shared
    
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
                        
                        // If we've made changes, show confirmation
                        if hasChanges() {
                            confirmCancel()
                        } else {
                            presentationMode.wrappedValue.dismiss()
                        }
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
                            showSaveConfirmation = true
                        }
                    }
                    .disabled(!isFormValid())
                    .accessibilityLabel(isFormValid() ? "Save" : "Save (Disabled)")
                    .accessibilityHint(isFormValid() ? 
                        "Saves the event details and returns to the calendar view" : 
                        "Cannot save until title and location are filled in")
                }
            }
            // Save confirmation dialog
            .alert("Save Changes", isPresented: $showSaveConfirmation) {
                Button("Save", role: .default) {
                    saveEventWithFeedback()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to save these changes? This will update the event for all family members.")
            }
            // Delete confirmation alert
            .alert(isPresented: $showDeleteConfirmation) {
                Alert(
                    title: Text("Delete Event"),
                    message: Text("Are you sure you want to delete this event? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        if let deleteHandler = onDelete {
                            deleteHandler()
                        } else {
                            deleteEventWithFeedback()
                        }
                        presentationMode.wrappedValue.dismiss()
                    },
                    secondaryButton: .cancel()
                )
            }
            // Success toast
            .overlay(
                ToastView(message: "Event saved successfully", systemImage: "checkmark.circle.fill", isShowing: $showSaveSuccess)
                    .transition(.move(edge: .top))
            )
            // Error toast
            .overlay(
                ToastView(message: errorMessage.isEmpty ? "Error saving event" : errorMessage, 
                          systemImage: "exclamationmark.circle.fill", 
                          isShowing: $showSaveError,
                          color: .red)
                    .transition(.move(edge: .top))
            )
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
    
    // Check if form has changes compared to original event
    private func hasChanges() -> Bool {
        if let originalEvent = event {
            return originalEvent.title != title ||
                   originalEvent.location != location ||
                   Int(originalEvent.day) != day
        } else {
            // For new events, consider any entered data as changes
            return !title.isEmpty || !location.isEmpty || day != 1
        }
    }
    
    // Confirm cancellation if there are unsaved changes
    private func confirmCancel() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Use UIKit alert controller for cancel confirmation because SwiftUI's alert doesn't support
        // multiple alerts on the same view in iOS 14/15
        let alert = UIAlertController(title: "Discard Changes", 
                                     message: "Are you sure you want to discard your unsaved changes?", 
                                     preferredStyle: .alert)
        
        let discardAction = UIAlertAction(title: "Discard", style: .destructive) { _ in
            presentationMode.wrappedValue.dismiss()
        }
        
        let cancelAction = UIAlertAction(title: "Keep Editing", style: .cancel)
        
        alert.addAction(discardAction)
        alert.addAction(cancelAction)
        
        // Get the current UIWindow to present the alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            // Find the presented view controller
            var currentVC = rootVC
            while let presentedVC = currentVC.presentedViewController {
                currentVC = presentedVC
            }
            currentVC.present(alert, animated: true)
        }
    }
    
    // MARK: - Event CRUD Operations
    
    // Save the event to CoreData with error handling and feedback
    private func saveEventWithFeedback() {
        if let saveHandler = onSave {
            // Use custom save handler if provided
            saveHandler(title, location, day)
            presentationMode.wrappedValue.dismiss()
            return
        }
        
        do {
            // Use EventRepository from DataManager to ensure transactional integrity
            let eventRepository = EventRepository(context: viewContext)
            
            if let event = event {
                // Update existing event with transaction
                try eventRepository.updateEventWithTransaction(event, title: title, location: location, day: day)
            } else {
                // Create new event
                let newEvent = eventRepository.createEvent(title: title, location: location, day: day, month: month)
                
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
                
                try viewContext.save()
            }
            
            // Show success feedback
            withAnimation {
                showSaveSuccess = true
            }
            
            // Hide success message after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSaveSuccess = false
                    presentationMode.wrappedValue.dismiss()
                }
            }
        } catch {
            // Show error feedback
            let nsError = error as NSError
            errorMessage = nsError.localizedDescription
            
            withAnimation {
                showSaveError = true
            }
            
            // Log detailed error
            print("Error saving event: \(nsError), \(nsError.userInfo)")
            
            // Hide error message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    showSaveError = false
                }
            }
        }
    }
    
    // Legacy save method (kept for backward compatibility)
    private func saveEvent() {
        // Call the new method with feedback
        saveEventWithFeedback()
    }
    
    // Delete the event from CoreData with error handling and feedback
    private func deleteEventWithFeedback() {
        guard let event = event else { return }
        
        do {
            // Use EventRepository to perform proper transaction
            let eventRepository = EventRepository(context: viewContext)
            
            // Delete event and its history in a single transaction
            try eventRepository.deleteEventWithHistory(event)
            
            // Success feedback would go here if we weren't dismissing immediately
        } catch {
            // If there's an error but we're already dismissing, show a global alert
            let nsError = error as NSError
            print("Error deleting event: \(nsError), \(nsError.userInfo)")
            
            // In a production app, we might want to use a global error handler here
            // since we're already dismissing the view
        }
    }
    
    // Legacy delete method (kept for backward compatibility)
    private func deleteEvent() {
        deleteEventWithFeedback()
    }
}

// MARK: - Toast View

// Simple toast notification view for feedback
struct ToastView: View {
    let message: String
    let systemImage: String
    @Binding var isShowing: Bool
    var color: Color = .green
    
    var body: some View {
        if isShowing {
            VStack {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .foregroundColor(color)
                    
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            isShowing = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                            .imageScale(.small)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
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