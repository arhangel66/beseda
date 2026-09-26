import AppKit
import SwiftUI

@main
struct BesedaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings

    private var controller: AppController {
        appDelegate.controller
    }

    var body: some Scene {
        Window("Разговоры", id: "conversations") {
            ConversationsWindow(controller: controller)
                .onAppear {
                    controller.showMainWindow = { showConversations() }
                    #if DEBUG
                    // SwiftUI opens the first window at launch; a popover shot has no use for it
                    if ProcessInfo.processInfo.environment["BESEDA_PREVIEW_POPOVER"] != nil {
                        DispatchQueue.main.async {
                            NSApplication.shared.windows
                                .first { $0.identifier?.rawValue.contains("conversations") == true }?
                                .close()
                        }
                    }
                    #endif
                }
        }
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra {
            MenuBarPopover(controller: controller, openConversations: { showConversations() })
        } label: {
            HStack(spacing: 4) {
                Image(systemName: controller.menuBarSystemImage)
                if let label = controller.menuBarLabel {
                    Text(label)
                }
            }
            .onAppear {
                // the label is the one view that exists from launch, so first-run work starts here
                #if DEBUG
                // a screenshot run is launched hidden, and activation would take the owner's focus
                let isShotRun = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("BESEDA_PREVIEW") }
                #else
                let isShotRun = false
                #endif
                if !controller.settings.onboardingDone {
                    openWindow(id: "onboarding")
                    if !isShotRun {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
                #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                if let preview = environment["BESEDA_PREVIEW_POPOVER"] {
                    let stage = JobStage(title: "Расшифровка собеседников", index: 4, total: 5)
                    switch preview {
                    case "live":
                        controller.status = .callRecording
                        controller.liveTranscription = .preview()
                    case "processing":
                        controller.status = .working(stage)
                    case "warning":
                        controller.status = .working(stage)
                        controller.recordingWarning = AppController.recordingWarning(forWriteError: AudioCaptureError.fileFull(""))
                    default:
                        break
                    }
                    openWindow(id: "popover-preview")
                }
                if let section = environment["BESEDA_PREVIEW_SETTINGS"] {
                    controller.requestedSettingsSection = section
                    openSettings()
                }
                #endif
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindow(controller: controller)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("О Beseda") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
                if controller.updater.isAvailable {
                    Button("Проверить обновления…") {
                        controller.updater.checkForUpdates()
                    }
                }
            }
            // the menu items do not read app state: a commands builder is not guaranteed to
            // re-evaluate on observation changes, so each action decides at the moment it runs
            CommandGroup(after: .pasteboard) {
                Button("Скопировать расшифровку") {
                    controller.copyTranscript()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandMenu("Запись") {
                Button("Начать или остановить запись") {
                    controller.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Пауза или продолжить") {
                    controller.togglePause()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Toggle("Автозапись", isOn: Bindable(controller.settings).autoDetectEnabled)
            }
        }

        Window("Добро пожаловать в Beseda", id: "onboarding") {
            OnboardingWindow(controller: controller) {
                dismissWindow(id: "onboarding")
                showConversations()
            }
            // closing the window counts as finishing, as dismissing the old sheet did
            .onDisappear {
                controller.settings.onboardingDone = true
            }
        }
        .windowResizability(.contentSize)

        #if DEBUG
        // screenshots of the menu-bar window without clicking the status item, debug builds only;
        // opened at launch when BESEDA_PREVIEW_POPOVER is set; `live` shows a recording with canned live text
        Window("Popover preview", id: "popover-preview") {
            MenuBarPopover(controller: controller, openConversations: { showConversations() })
        }
        .windowResizability(.contentSize)
        #endif
    }

    private func showConversations() {
        // SwiftUI keeps a closed window alive but does not bring it back, so raise it directly
        if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue.contains("conversations") == true }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "conversations")
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    // the menu bar item is unreachable when the menu bar is full, so closing the window
    // must not take the app down with it
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        controller.showMainWindow?()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}
