import Foundation

// Old model - keeping for reference
struct EventItem: Identifiable {
    var id = UUID()
    var title: String
    var location: String
    var day: Int
    var month: Month
    
    static let defaultEvents = Month.allCases.map { month in
        EventItem(title: "Event", location: "Home", day: 1, month: month)
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
    
    static func from(monthNumber: Int16) -> Month? {
        switch monthNumber {
        case 1: return .january
        case 2: return .february
        case 3: return .march
        case 4: return .april
        case 5: return .may
        case 6: return .june
        case 7: return .july
        case 8: return .august
        case 9: return .september
        case 10: return .october
        case 11: return .november
        case 12: return .december
        default: return nil
        }
    }
    
    var monthNumber: Int16 {
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
}