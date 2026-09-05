import Foundation

/// The sidebar's day headings, in the order the prototype lists them.
enum CallDayGroup: Int, CaseIterable, Comparable {
    case today
    case yesterday
    case thisWeek
    case earlier

    var title: String {
        switch self {
        case .today:
            "Сегодня"
        case .yesterday:
            "Вчера"
        case .thisWeek:
            "На этой неделе"
        case .earlier:
            "Ранее"
        }
    }

    static func of(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> CallDayGroup {
        if calendar.isDate(date, inSameDayAs: now) {
            return .today
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        let days = calendar.dateComponents([.day], from: date, to: now).day ?? .max
        return days < 7 ? .thisWeek : .earlier
    }

    static func < (lhs: CallDayGroup, rhs: CallDayGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct CallGroup: Identifiable {
    let day: CallDayGroup
    let calls: [StoredCallSummary]

    var id: Int {
        day.rawValue
    }
}

enum CallFormatting {
    static let locale = Locale(identifier: "ru_RU")

    static func mmss(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func hms(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "42 сек" / "3 мин" / "1 ч 5 мин", as in the prototype's call rows
    static func humanDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        if total < 60 {
            return "\(total) сек"
        }
        let minutes = Int((Double(total) / 60).rounded())
        if minutes < 60 {
            return "\(minutes) мин"
        }
        return "\(minutes / 60) ч \(minutes % 60) мин"
    }

    /// "14:08" — the start time on its own, the sidebar's leading column
    static func clock(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "сегодня, 16:20" / "вчера, 19:04" / "27 авг, 14:47"
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = timeFormatter.string(from: date)
        switch CallDayGroup.of(date, now: now, calendar: calendar) {
        case .today:
            return "сегодня, \(time)"
        case .yesterday:
            return "вчера, \(time)"
        case .thisWeek, .earlier:
            // ru "d MMM" ends in a period ("19 авг."), which reads badly before the comma
            let day = dayFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
            return "\(day), \(time)"
        }
    }

    /// 1 разговор, 2 разговора, 5 разговоров
    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if lastTwo >= 11 && lastTwo <= 14 {
            return "\(count) \(many)"
        }
        switch last {
        case 1:
            return "\(count) \(one)"
        case 2, 3, 4:
            return "\(count) \(few)"
        default:
            return "\(count) \(many)"
        }
    }

    static func parseISO8601(_ value: String) -> Date? {
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractions.date(from: value) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}
