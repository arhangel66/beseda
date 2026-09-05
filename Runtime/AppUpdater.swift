import AppKit
import Foundation
import Sparkle

/// Holds Sparkle's install callbacks until no call is being recorded.
final class UpdateInstallGate {
    private let isRecording: () -> Bool
    private var pending: [() -> Void] = []

    init(isRecording: @escaping () -> Bool) {
        self.isRecording = isRecording
    }

    /// runs the install now when idle, otherwise on the next `recordingDidStop()`
    func install(_ handler: @escaping () -> Void) {
        if isRecording() {
            pending.append(handler)
        } else {
            handler()
        }
    }

    func recordingDidStop() {
        let handlers = pending
        pending = []
        for handler in handlers {
            handler()
        }
    }
}

/// Sparkle wrapper for a menu bar agent that is never quit: installs staged updates
/// itself at a quiet moment instead of waiting for a termination that never comes.
@MainActor
final class AppUpdater: NSObject {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    private var gate: UpdateInstallGate?
    private var controller: SPUStandardUpdaterController?

    /// only a release bundle carries a feed; starting Sparkle without one shows an error alert
    var isAvailable: Bool {
        controller != nil
    }

    /// starts Sparkle's hourly checks; a dev bundle without a feed stays quiet
    func start(isRecording: @escaping () -> Bool) {
        gate = UpdateInstallGate(isRecording: isRecording)
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    var lastCheckDate: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    func checkForUpdates() {
        // an LSUIElement agent is not active, so Sparkle's panel would open behind other windows
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func recordingDidStop() {
        gate?.recordingDidStop()
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    // the silent path: the update is downloaded and staged, Sparkle hands over the install
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        gate?.install(immediateInstallHandler)
        return true
    }

    // the manual path: a person pressed "Install and Relaunch" in Sparkle's panel
    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        gate?.install(installHandler)
        return true
    }
}
