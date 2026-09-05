import Foundation
import Testing

@testable import Beseda

private let callStart = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 29, hour: 14, minute: 8))!

private func makeEvent(id: String, startMinutes: Int, lengthMinutes: Int) -> CalendarEvent {
    let start = callStart.addingTimeInterval(TimeInterval(startMinutes * 60))
    return CalendarEvent(
        id: id,
        title: id,
        startsAt: start,
        endsAt: start.addingTimeInterval(TimeInterval(lengthMinutes * 60)),
        hasConferenceLink: false
    )
}

@Test func theEventStartingWithTheCallWins() {
    let events = [makeEvent(id: "sync", startMinutes: -3, lengthMinutes: 30)]

    #expect(CalendarService.match(events: events, callStart: callStart)?.id == "sync")
}

@Test func anEventStartingFourMinutesLaterStillCounts() {
    let events = [makeEvent(id: "sync", startMinutes: 4, lengthMinutes: 30)]

    #expect(CalendarService.match(events: events, callStart: callStart)?.id == "sync")
}

@Test func anEventStartingSixMinutesLaterDoesNot() {
    let events = [makeEvent(id: "sync", startMinutes: 6, lengthMinutes: 30)]

    #expect(CalendarService.match(events: events, callStart: callStart) == nil)
}

@Test func aLongEventTheCallMerelyFallsInsideIsNotTheName() {
    let events = [makeEvent(id: "flight", startMinutes: -55, lengthMinutes: 120)]

    #expect(CalendarService.match(events: events, callStart: callStart) == nil)
}

@Test func aShortEventIsNotTheName() {
    let events = [makeEvent(id: "reminder", startMinutes: 0, lengthMinutes: 10)]

    #expect(CalendarService.match(events: events, callStart: callStart) == nil)
}

@Test func aQuarterHourEventIsAlreadyTooShort() {
    let events = [makeEvent(id: "buffer", startMinutes: 0, lengthMinutes: 15)]

    #expect(CalendarService.match(events: events, callStart: callStart) == nil)
}

@Test func withTwoEventsStartingNearbyTheNearerOneWins() {
    let events = [
        makeEvent(id: "earlier", startMinutes: -4, lengthMinutes: 30),
        makeEvent(id: "near", startMinutes: 1, lengthMinutes: 60)
    ]

    #expect(CalendarService.match(events: events, callStart: callStart)?.id == "near")
}

@Test func anEmptyCalendarMatchesNothing() {
    #expect(CalendarService.match(events: [], callStart: callStart) == nil)
}

@Test func aZoomLinkInTheEventCountsAsACall() {
    #expect(CalendarService.carriesConferenceLink("https://us02web.zoom.us/j/123"))
    #expect(CalendarService.carriesConferenceLink("Переговорка на третьем этаже") == false)
}
