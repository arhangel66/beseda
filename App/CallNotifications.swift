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

    private let center = UNUserNotificationCenter.current()

    func start() {
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.autoRecordingCategory,
                actions: [
                    UNNotificationAction(
                        identifier: Self.cancelActionID,
                        title: "Cancel and delete",
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
        content.title = "Recording your \(appName) call"
        content.body = "Beseda started on its own."
        content.categoryIdentifier = Self.autoRecordingCategory
        post(content)
    }

    func transcriptReady(callDescription: String) {
        let content = UNMutableNotificationContent()
        content.title = "Transcript ready"
        content.body = callDescription
        post(content)
    }

    private func post(_ content: UNMutableNotificationContent) {
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
