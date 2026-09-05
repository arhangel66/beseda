import Foundation
import Testing

@testable import Beseda

private let zoom = CallDetector.Detection(bundleID: "us.zoom.xos", appName: "Zoom")
private let telegram = CallDetector.Detection(bundleID: "com.tdesktop.Telegram", appName: "Telegram")
private let epoch = Date(timeIntervalSince1970: 1_000_000)

@Test func startsOnlyAfterTheDebounceElapsed() {
    var policy = CallRecordingPolicy()

    let onMicrophone = policy.update(holder: zoom, manualRecordingActive: false, now: epoch)
    let debounced = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 5)

    #expect(onMicrophone == nil)
    #expect(debounced == .start(zoom))
}

@Test func doesNotStartWhileAManualRecordingIsRunning() {
    var policy = CallRecordingPolicy()

    _ = policy.update(holder: zoom, manualRecordingActive: true, now: epoch)
    let debounced = policy.update(holder: zoom, manualRecordingActive: true, now: epoch + 5)

    #expect(debounced == nil)
    #expect(!policy.isRecording)
}

@Test func doesNotStartTwiceWhileAlreadyRecording() {
    var policy = CallRecordingPolicy()
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch)
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 5)

    let again = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 20)

    #expect(again == nil)
}

@Test func stopsWhenTheMicrophoneIsReleased() {
    var policy = CallRecordingPolicy()
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch)
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 5)

    let released = policy.update(holder: nil, manualRecordingActive: false, now: epoch + 300)

    #expect(released == .stop)
    #expect(!policy.isRecording)
}

@Test func releaseBeforeTheDebounceRecordsNothing() {
    var policy = CallRecordingPolicy()

    let onMicrophone = policy.update(holder: zoom, manualRecordingActive: false, now: epoch)
    let released = policy.update(holder: nil, manualRecordingActive: false, now: epoch + 1)

    #expect(onMicrophone == nil)
    #expect(released == nil)
}

@Test func minimumGapSuppressesAnImmediateRestart() {
    var policy = CallRecordingPolicy()
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch)
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 5)
    _ = policy.update(holder: nil, manualRecordingActive: false, now: epoch + 300)

    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 305)
    let insideGap = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 310)
    let afterGap = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 365)

    #expect(insideGap == nil)
    #expect(afterGap == .start(zoom))
}

@Test func silenceStopDoesNotRestartUntilTheMicrophoneIsTakenAgain() {
    var policy = CallRecordingPolicy()
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch)
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 5)
    policy.recordingEnded(now: epoch + 100)

    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 300)
    let stillTheSameCall = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 400)

    _ = policy.update(holder: nil, manualRecordingActive: false, now: epoch + 500)
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 505)
    let afterANewAcquisition = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 510)

    #expect(stillTheSameCall == nil)
    #expect(afterANewAcquisition == .start(zoom))
}

@Test func anotherAppTakingTheMicrophoneStartsItsOwnRecording() {
    var policy = CallRecordingPolicy()
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch)
    _ = policy.update(holder: zoom, manualRecordingActive: false, now: epoch + 5)
    policy.recordingEnded(now: epoch + 100)

    _ = policy.update(holder: telegram, manualRecordingActive: false, now: epoch + 200)
    let started = policy.update(holder: telegram, manualRecordingActive: false, now: epoch + 205)

    #expect(started == .start(telegram))
}
