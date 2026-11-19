import Foundation
import os

/// The sidebar's headings: a day of its own for the recent days, a month further back.
enum CallDayGroup: Hashable, Comparable {
    case day(Date)
    case month(Date)

    /// how far back a call still gets a heading with its own day
    static let daysListedSeparately = 10

    static func of(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> CallDayGroup {
        let startOfDay = calendar.startOfDay(for: date)
        let daysBack = calendar.dateComponents([.day], from: startOfDay, to: calendar.startOfDay(for: now)).day ?? .max
        if daysBack < daysListedSeparately {
            return .day(startOfDay)
        }
        return .month(calendar.dateInterval(of: .month, for: date)?.start ?? startOfDay)
    }

    /// "Сегодня, пятница" · "Вчера, четверг" · "Понедельник, 17 ноября" · "Октябрь 2026"
    func title(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch self {
        case .day(let day):
            let weekday = CallFormatting.weekday(day, locale: locale)
            if calendar.isDate(day, inSameDayAs: now) {
                return ArchiveText.format("Сегодня, %@", weekday, locale: locale)
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
               calendar.isDate(day, inSameDayAs: yesterday) {
                return ArchiveText.format("Вчера, %@", weekday, locale: locale)
            }
            return CallFormatting.startingWithACapital("\(weekday), \(CallFormatting.dayAndMonth(day, locale: locale))")
        case .month(let month):
            return CallFormatting.startingWithACapital(CallFormatting.monthAndYear(month, locale: locale))
        }
    }

    var start: Date {
        switch self {
        case .day(let start), .month(let start):
            return start
        }
    }

    var isDay: Bool {
        if case .day = self {
            return true
        }
        return false
    }

    /// the sidebar lists the newest group first
    static func < (lhs: CallDayGroup, rhs: CallDayGroup) -> Bool {
        lhs.start > rhs.start
    }
}

struct CallGroup: Identifiable {
    let day: CallDayGroup
    let calls: [StoredCallSummary]

    var id: Date {
        day.start
    }
}

enum CallFormatting {
    static var locale: Locale { .current }
    private static let logger = Logger(subsystem: "app.beseda.Beseda", category: "dates")

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

    static func humanDuration(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let total = Int(max(0, seconds).rounded())
        let minutes = Int((Double(total) / 60).rounded())
        if locale.language.languageCode?.identifier == "ru" {
            if total < 60 { return "\(total) сек" }
            if minutes < 60 { return "\(minutes) мин" }
            return "\(minutes / 60) ч \(minutes % 60) мин"
        }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = total < 60 ? [.second] : minutes < 60 ? [.minute] : [.hour, .minute]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: TimeInterval(total < 60 ? total : minutes * 60)) ?? ""
    }

    /// "14:08" — the start time on its own, the sidebar's leading column
    static func clock(_ date: Date) -> String {
        timeFormatter(locale: .current).string(from: date)
    }

    /// "сегодня, 16:20" / "вчера, 19:04" / "27 авг, 14:47"
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = timeFormatter(locale: locale).string(from: date)
        let russian = locale.language.languageCode?.identifier == "ru"
        if calendar.isDate(date, inSameDayAs: now) {
            return "\(russian ? "сегодня" : "today"), \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "\(russian ? "вчера" : "yesterday"), \(time)"
        }
        // ru "d MMM" ends in a period ("19 авг."), which reads badly before the comma
        let formatted = dayFormatter(locale: locale).string(from: date)
        let day = russian ? formatted.replacingOccurrences(of: ".", with: "") : formatted
        return "\(day), \(time)"
    }

    /// "пятница" — the weekday on its own, for the sidebar's day headings
    static func weekday(_ date: Date, locale: Locale = .current) -> String {
        templateFormatter("EEEE", locale: locale).string(from: date)
    }

    /// "17 ноября" — the day inside its month, for a heading that is neither today nor yesterday
    static func dayAndMonth(_ date: Date, locale: Locale = .current) -> String {
        templateFormatter("dMMMM", locale: locale).string(from: date)
    }

    /// "октябрь 2026" — the heading the older calls fall into
    static func monthAndYear(_ date: Date, locale: Locale = .current) -> String {
        // ru "LLLL yyyy 'г'." ends in a narrow space and "г.", which a heading does not need
        templateFormatter("LLLLyyyy", locale: locale)
            .string(from: date)
            .replacingOccurrences(of: "\\s*г\\.$", with: "", options: .regularExpression)
    }

    static func startingWithACapital(_ text: String) -> String {
        "\(text.prefix(1).uppercased())\(text.dropFirst())"
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
        if let date = plain.date(from: value) {
            return date
        }
        logger.error("Unparseable stored date: \(value, privacy: .public)")
        return nil
    }

    private static func timeFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static func dayFormatter(locale: Locale) -> DateFormatter {
        templateFormatter("dMMM", locale: locale)
    }

    private static func templateFormatter(_ template: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
