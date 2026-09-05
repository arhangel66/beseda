import AppKit
import SwiftUI

@main
struct BesedaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    private var controller: AppController {
        appDelegate.controller
    }

    var body: some Scene {
        Window("Разговоры", id: "conversations") {
            ConversationsWindow(controller: controller)
                .sheet(isPresented: Bindable(controller.settings).showOnboarding) {
                    OnboardingWindow(controller: controller) {
                        controller.settings.onboardingDone = true
                    }
                }
                .onAppear {
                    controller.showMainWindow = { showConversations() }
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
                if ProcessInfo.processInfo.environment["BESEDA_PREVIEW_POPOVER"] != nil {
                    openWindow(id: "popover-preview")
                }
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
        }

        // screenshots of the menu-bar window without clicking the status item;
        // opened at launch when BESEDA_PREVIEW_POPOVER is set
        Window("Popover preview", id: "popover-preview") {
            MenuBarPopover(controller: controller, openConversations: { showConversations() })
        }
        .windowResizability(.contentSize)
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
