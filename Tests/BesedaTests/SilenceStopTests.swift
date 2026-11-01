import Foundation
import Testing

@testable import Beseda

// waiting for a client who has not joined yet is not the quiet after a call
@Test func waitingForTheOtherSideInSilenceDoesNotStopAfterAMinute() {
    let stops = DualCapture.isSilenceStopDue(silence: 5 * 60, otherSideHeard: false, limit: 60)

    #expect(!stops)
}

@Test func silenceStopsAfterAMinuteOnceTheOtherSideWasHeard() {
    let stops = DualCapture.isSilenceStopDue(silence: 61, otherSideHeard: true, limit: 60)

    #expect(stops)
}

@Test func aRecordingNobodyJoinedStopsAfterFifteenQuietMinutes() {
    let beforeLimit = DualCapture.isSilenceStopDue(silence: 14 * 60, otherSideHeard: false, limit: 60)
    let atLimit = DualCapture.isSilenceStopDue(silence: 15 * 60, otherSideHeard: false, limit: 60)

    #expect(!beforeLimit)
    #expect(atLimit)
}

@Test func aChannelCountsAsHeardOnlyAfterSoundAboveTheThreshold() {
    let tracker = AudioActivityTracker()

    tracker.observe(samples: Array(repeating: 0.0001, count: 480))
    let afterRoomNoise = tracker.hasHeardActivity
    tracker.observe(samples: Array(repeating: 0.2, count: 480))

    #expect(!afterRoomNoise)
    #expect(tracker.hasHeardActivity)
}
