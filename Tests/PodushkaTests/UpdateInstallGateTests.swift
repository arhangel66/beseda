import Testing

@testable import Podushka

@Test func installRunsAtOnceWhenNothingIsRecording() {
    let gate = UpdateInstallGate(isRecording: { false })
    var installs = 0

    gate.install { installs += 1 }

    #expect(installs == 1)
}

@Test func installWaitsWhileRecordingAndRunsOnceWhenItStops() {
    var recording = true
    let gate = UpdateInstallGate(isRecording: { recording })
    var installs = 0

    gate.install { installs += 1 }
    #expect(installs == 0)
    recording = false
    gate.recordingDidStop()
    gate.recordingDidStop()

    #expect(installs == 1)
}

@Test func recordingStopWithNothingPendingDoesNothing() {
    let gate = UpdateInstallGate(isRecording: { false })

    gate.recordingDidStop()
}
