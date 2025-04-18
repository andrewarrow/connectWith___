import SwiftUI

// Month and Event models
struct Event: Identifiable {
    var id = UUID()
    var title: String
    var location: String
    var day: Int
    var month: Month
    
    static let defaultEvents = Month.allCases.map { month in
        Event(title: "Event", location: "Home", day: 1, month: month)
    }
}

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
    
    var color: String {
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
}

// Card view for a single event
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

// Main calendar view container
struct CalendarViewContainer: View {
    @State private var events = Event.defaultEvents
    @State private var currentIndex: Int = 0
    @Environment(\.presentationMode) private var presentationMode
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .padding()
                    
                    Spacer()
                }
                
                Text("Family Calendar")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Swipe to browse your events")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
                
                TabView(selection: $currentIndex) {
                    ForEach(Array(events.indices), id: \.self) { index in
                        EventCardView(event: $events[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                .frame(height: 240)
                .padding(.vertical)
                
                Spacer()
                
                VStack(alignment: .leading) {
                    Text("Current Event: \(events[currentIndex].month.rawValue)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.horizontal)
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Title: \(events[currentIndex].title)", systemImage: "pencil")
                            Label("Location: \(events[currentIndex].location)", systemImage: "mappin.and.ellipse")
                            Label("Date: \(events[currentIndex].day) \(events[currentIndex].month.rawValue)", systemImage: "calendar")
                        }
                        .padding()
                        
                        Spacer()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding()
            }
        }
    }
}

#Preview {
    CalendarViewContainer()
}