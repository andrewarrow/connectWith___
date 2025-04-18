import Foundation

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