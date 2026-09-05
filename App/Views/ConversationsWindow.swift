import SwiftUI

struct ConversationsWindow: View {
    let controller: AppController

    @State private var player = CallPlayer()

    var body: some View {
        NavigationSplitView {
            CallSidebar(controller: controller)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            CallDetailView(controller: controller, player: player)
        }
        .navigationTitle("Разговоры")
        .searchable(
            text: Bindable(controller).searchQuery,
            placement: .sidebar,
            prompt: "Искать в разговорах"
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let detail = controller.selectedCallDetail {
                    if controller.settings.calendarEnabled, controller.calendarService.isAuthorized {
                        LinkEventButton(controller: controller, summary: detail.summary)
                    }
                    if controller.settings.webhookEnabled || !controller.webhooks.selected.isEmpty {
                        SendToWebhookButton(controller: controller, detail: detail)
                    }
                    CopyTranscriptButton(controller: controller)
                }
                RecordingToolbarButton(controller: controller)
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .overlay(alignment: .bottom) {
            if let toast = controller.toast {
                ToastOverlay(text: toast)
                    .padding(.bottom, 88)
            }
        }
        .animation(.easeOut(duration: 0.18), value: controller.toast)
        .onAppear {
            controller.refreshCallBrowser(selectFirstIfNeeded: true)
            controller.refreshStorageUsage()
            controller.refreshCalendar()
        }
    }

}

/// The one place in the window that says what the recorder is doing. Its own view, so the
/// 10 Hz timer behind `elapsedRecordingSeconds` re-renders this button and not the window.
private struct RecordingToolbarButton: View {
    let controller: AppController

    var body: some View {
        if controller.isRecording {
            Button {
                controller.stopActiveRecording()
            } label: {
                Label(CallFormatting.mmss(controller.elapsedRecordingSeconds), systemImage: "stop.circle.fill")
                    .monospacedDigit()
                    .foregroundStyle(.red)
            }
            .help(controller.isPaused ? "Пауза. Остановить запись (⌘R)" : "Идёт запись. Остановить (⌘R)")
        } else {
            Button {
                controller.startCallRecording()
            } label: {
                Label("Записать", systemImage: "record.circle")
            }
            .disabled(controller.isBusy)
            .help(controller.isBusy ? "Дождитесь конца расшифровки" : "Начать запись (⌘R)")
        }
    }
}
