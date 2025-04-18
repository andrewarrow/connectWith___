import SwiftUI

struct EventCardView: View {
    @Binding var event: Event
    @State private var isEditing = false
    @State private var title: String
    @State private var location: String
    @State private var day: Int
    
    init(event: Binding<Event>) {
        self._event = event
        self._title = State(initialValue: event.wrappedValue.title)
        self._location = State(initialValue: event.wrappedValue.location)
        self._day = State(initialValue: event.wrappedValue.day)
    }
    
    var body: some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(event.month.color))
                    .shadow(radius: 5)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(event.month.rawValue)
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            isEditing.toggle()
                        }) {
                            Image(systemName: isEditing ? "checkmark.circle" : "pencil.circle")
                                .foregroundColor(.white)
                                .font(.title2)
                        }
                    }
                    
                    if isEditing {
                        editingView
                    } else {
                        displayView
                    }
                }
                .padding()
            }
            .frame(height: 180)
            .padding(.horizontal)
        }
    }
    
    var displayView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(event.title)
                .font(.title)
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(event.location)
                .font(.body)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            
            Spacer()
            
            HStack {
                Text("Day: \(event.day)")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
            }
        }
    }
    
    var editingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $title)
                .font(.title3)
                .foregroundColor(.white)
                .background(Color.white.opacity(0.2))
                .cornerRadius(8)
                .padding(5)
                .onChange(of: title) { newValue in
                    event.title = newValue
                }
            
            TextField("Location", text: $location)
                .font(.body)
                .foregroundColor(.white)
                .background(Color.white.opacity(0.2))
                .cornerRadius(8)
                .padding(5)
                .onChange(of: location) { newValue in
                    event.location = newValue
                }
            
            Stepper("Day: \(day)", value: $day, in: 1...31)
                .foregroundColor(.white)
                .onChange(of: day) { newValue in
                    event.day = newValue
                }
        }
    }
}

#Preview {
    EventCardView(event: .constant(Event(title: "Birthday Party", location: "Home", day: 15, month: .april)))
}