import Foundation
import Testing

@testable import Beseda

@Test func previousCallContentShowsDateAndDigestAsStored() throws {
    let now = try #require(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()))
    let call = PreviousRelatedCall(callID: "call-1", startedAt: now.addingTimeInterval(-60), digest: "**Главное**\nДоговорились")

    let content = try #require(PreviousCallContent(call, now: now))

    #expect(content.callID == "call-1")
    #expect(content.dateLine == CallFormatting.when(call.startedAt, now: now))
    #expect(content.dateLine.hasPrefix("сегодня"))
    #expect(content.digest == "**Главное**\nДоговорились")
}

@Test func previousCallContentIsHiddenWithoutCallOrDigest() {
    let blank = PreviousRelatedCall(callID: "call-1", startedAt: Date(), digest: " \n")

    #expect(PreviousCallContent(nil) == nil)
    #expect(PreviousCallContent(blank) == nil)
}
