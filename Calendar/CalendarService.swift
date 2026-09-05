import EventKit
import Foundation
import Observation

/// One event, flattened out of EventKit so nothing above this file touches EKEvent.
struct CalendarEvent: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let startsAt: Date
    let endsAt: Date
    /// a Zoom / Meet / Teams / Telegram link somewhere on the event
    let hasConferenceLink: Bool

    var timeDescription: String {
        CallFormatting.clock(startsAt)
    }
}

/// Reads the Mac's calendars to name conversations and to show what is coming up.
/// It never starts a recording — that still comes from the sound of a call app.
@MainActor
@Observable
final class CalendarService {
    private(set) var authorization = EKEventStore.authorizationStatus(for: .event)

    @ObservationIgnored private let store = EKEventStore()

    var isAuthorized: Bool {
        authorization == .fullAccess
    }

    func requestAccess() async -> Bool {
        // macOS 14 split calendar access in two, and reading events needs the full kind
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authorization = EKEventStore.authorizationStatus(for: .event)
        return granted
    }

    /// title and identifier of every calendar the user could pick from
    func availableCalendars() -> [(id: String, title: String)] {
        guard isAuthorized else {
            return []
        }
        return store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { (id: $0.calendarIdentifier, title: $0.title) }
    }

    /// one fetch over a range; matching and grouping happen in memory afterwards
    func events(from start: Date, to end: Date, identifiers: Set<String>) -> [CalendarEvent] {
        guard isAuthorized, end > start else {
            return []
        }
        let all = store.calendars(for: .event)
        let calendars = identifiers.isEmpty ? all : all.filter { identifiers.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            return []
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .compactMap(Self.makeEvent)
            .sorted { $0.startsAt < $1.startsAt }
    }

    /// The event that *began* when the recording did, give or take a few minutes — people join
    /// early and the recording starts with the first sound. Merely overlapping is not enough:
    /// a flight, a "Busy" block or a day-long hold would swallow every call inside it.
    /// The length floor drops the reminders and buffers nobody talks through.
    /// With several candidates the one starting nearest the call wins.
    nonisolated static func match(
        events: [CalendarEvent],
        callStart: Date,
        tolerance: TimeInterval = 5 * 60,
        minimumLength: TimeInterval = 15 * 60
    ) -> CalendarEvent? {
        events
            .filter { $0.endsAt.timeIntervalSince($0.startsAt) > minimumLength }
            .filter { abs($0.startsAt.timeIntervalSince(callStart)) <= tolerance }
            .min { abs($0.startsAt.timeIntervalSince(callStart)) < abs($1.startsAt.timeIntervalSince(callStart)) }
    }

    private nonisolated static func makeEvent(_ event: EKEvent) -> CalendarEvent? {
        guard let start = event.startDate, let end = event.endDate else {
            return nil
        }
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return nil
        }
        let haystack = [event.url?.absoluteString, event.location, event.notes]
            .compactMap { $0 }
            .joined(separator: " ")
        return CalendarEvent(
            id: event.eventIdentifier ?? "\(title)-\(start.timeIntervalSince1970)",
            title: title,
            startsAt: start,
            endsAt: end,
            hasConferenceLink: Self.carriesConferenceLink(haystack)
        )
    }

    /// a guess, and the sidebar says so: an event with a call link is one we would record
    nonisolated static func carriesConferenceLink(_ text: String) -> Bool {
        let markers = ["zoom.us", "meet.google", "teams.microsoft", "teams.live", "t.me", "telemost", "whereby", "discord.gg"]
        let lowered = text.lowercased()
        return markers.contains { lowered.contains($0) }
    }
}
