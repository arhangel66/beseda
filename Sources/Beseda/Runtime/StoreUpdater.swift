#if BESEDA_STORE
import Foundation

@MainActor
final class AppUpdater {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    func start(isRecording: @escaping () -> Bool) {}
    func recordingDidStop() {}
}
#endif
