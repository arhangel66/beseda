import AVFAudio
import AppKit
import Foundation
import Observation

enum PermissionState: Equatable {
    case idle
    case checking
    case granted
    case denied(String)

    var isGranted: Bool {
        self == .granted
    }
}

/// The two permissions onboarding checks before the first real call.
@MainActor
@Observable
final class PermissionsModel {
    private(set) var microphone: PermissionState = .idle
    private(set) var systemAudio: PermissionState = .idle

    var allGranted: Bool {
        microphone.isGranted && systemAudio.isGranted
    }

    func refresh() {
        microphone = Self.microphoneState()
        if systemAudio == .granted {
            return
        }
        systemAudio = .idle
    }

    func requestMicrophone() async {
        if case .denied = Self.microphoneState() {
            openPrivacySettings(pane: "Privacy_Microphone")
            microphone = Self.microphoneState()
            return
        }

        microphone = .checking
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        microphone = granted ? .granted : .denied("Доступ к микрофону не выдан")
    }

    /// the only honest check is opening a tap: macOS grants system audio per app, silently
    func checkSystemAudio() async {
        guard #available(macOS 14.2, *) else {
            systemAudio = .denied("Системный звук требует macOS 14.2 или новее")
            return
        }

        systemAudio = .checking
        let result = await Task.detached(priority: .userInitiated) { () -> String? in
            let tap = SystemAudioTap()
            do {
                try tap.start(expectedDuration: 1)
                tap.cleanup()
                return nil
            } catch {
                tap.cleanup()
                return error.localizedDescription
            }
        }.value

        if let result {
            systemAudio = .denied(result)
            openPrivacySettings(pane: "Privacy_Microphone")
        } else {
            systemAudio = .granted
        }
    }

    private static func microphoneState() -> PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            .granted
        case .denied:
            .denied("Доступ к микрофону запрещён в системных настройках")
        default:
            .idle
        }
    }

    private func openPrivacySettings(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
