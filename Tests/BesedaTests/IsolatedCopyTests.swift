import Testing

@testable import Beseda

@MainActor
@Test func isolatedCopyNeverReachesAPermissionDialog() async {
    #expect(IsolatedCopy.isActive)

    await CalendarService().requestAccess()
    CallNotifier().start()
    await PermissionsModel().requestMicrophone()
    await #expect(throws: AudioCaptureError.self) { try await MicrophoneCapture(activityTracker: AudioActivityTracker()).start() }
    #expect(throws: AudioCaptureError.self) { try SystemAudioTap().start() }
    IsolatedCopy.activateApp()

    let skipped = Set(IsolatedCopy.skippedCallSites.withLock { $0 })
    #expect(skipped.isSuperset(of: [
        "EKEventStore.requestFullAccessToEvents",
        "UNUserNotificationCenter.requestAuthorization",
        "AVAudioApplication.requestRecordPermission",
        "AVAudioEngine.start (microphone)",
        "AudioHardwareCreateProcessTap",
        "NSApp.activate",
    ]))
}
