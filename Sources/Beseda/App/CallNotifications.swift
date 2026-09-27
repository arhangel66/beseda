import Foundation
import UserNotifications

/// Tells the owner after the fact: a banner when an automatic recording starts, one when a transcript is ready.
@MainActor
final class CallNotifier: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    private static let autoRecordingCategory = "app.beseda.autoRecording"
    private static let cancelActionID = "app.beseda.cancelAndDelete"

    var onCancelAutoRecording: (() -> Void)?
    var onOpenCalls: (() -> Void)?
    var onDiagnostics: ((String) -> Void)?

    private lazy var center = UNUserNotificationCenter.current()

    func start() {
        // outside an app bundle (swift test, swift run) the notification center raises on first use
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return
        }
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.autoRecordingCategory,
                actions: [
                    UNNotificationAction(
                        identifier: Self.cancelActionID,
                        title: "Отменить и удалить",
                        options: [.destructive]
                    )
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
        Task {
            do {
                if try await center.requestAuthorization(options: [.alert]) == false {
                    onDiagnostics?("Notifications not allowed")
                }
            } catch {
                onDiagnostics?("Notifications unavailable: \(error.localizedDescription)")
            }
        }
    }

    func autoRecordingStarted(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Идёт запись звонка в \(appName)"
        content.body = "Beseda включила запись сама."
        content.categoryIdentifier = Self.autoRecordingCategory
        post(content)
    }

    func transcriptReady(callDescription: String) {
        let content = UNMutableNotificationContent()
        content.title = "Расшифровка готова"
        content.body = callDescription
        post(content)
    }

    func recordingStopped(reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "Запись остановлена"
        content.body = reason
        post(content)
    }

    private func post(_ content: UNMutableNotificationContent) {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            do {
                try await center.add(request)
            } catch {
                onDiagnostics?("Notification failed: \(error.localizedDescription)")
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case Self.cancelActionID:
            onCancelAutoRecording?()
        case UNNotificationDefaultActionIdentifier:
            onOpenCalls?()
        default:
            break
        }
    }
}
