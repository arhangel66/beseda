import AppKit
import os

/// A run that is not the installed app: a copy under another bundle id, a copy launched with a temp
/// home, or a test. It shares his login keychain and TCC database, so anything that can put a system
/// dialog or a window in front of him is skipped and the permission reads as not granted.
enum IsolatedCopy {
    static let isActive: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return Bundle.main.bundleIdentifier != "app.beseda.Beseda"
            || environment["BESEDA_NO_KEYCHAIN"] != nil || environment["CFFIXED_USER_HOME"] != nil
    }()

    /// call sites that were skipped, so a test can see every dialog-capable path hit its guard
    static let skippedCallSites = OSAllocatedUnfairLock(initialState: [String]())

    /// true when `callSite` must not run; call it right before any API that can show a system dialog
    static func skips(_ callSite: String) -> Bool {
        guard isActive else {
            return false
        }
        skippedCallSites.withLock { $0.append(callSite) }
        return true
    }

    @MainActor
    static func activateApp() {
        if !skips("NSApp.activate") {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
