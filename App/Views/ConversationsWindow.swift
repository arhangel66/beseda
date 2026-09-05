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
                    if controller.settings.calendarEnabled {
                        LinkEventButton(controller: controller, summary: detail.summary)
                    }
                    if controller.settings.webhookEnabled || !controller.webhooks.selected.isEmpty {
                        SendToWebhookButton(controller: controller, detail: detail)
                    }
                    CopyTranscriptButton(controller: controller)
                }
                recordingItem
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

    /// the one place in the window that says what the recorder is doing right now
    @ViewBuilder
    private var recordingItem: some View {
        if controller.isRecording {
            Button {
                controller.stopActiveRecording()
            } label: {
                Label(CallFormatting.mmss(controller.elapsedRecordingSeconds), systemImage: "stop.circle.fill")
                    .monospacedDigit()
                    .foregroundStyle(.red)
            }
            .keyboardShortcut("r", modifiers: .command)
            .help(controller.isPaused ? "Пауза. Остановить запись (⌘R)" : "Идёт запись. Остановить (⌘R)")
        } else {
            Button {
                controller.startCallRecording()
            } label: {
                Label("Записать", systemImage: "record.circle")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(controller.isBusy)
            .help(controller.isBusy ? "Дождитесь конца расшифровки" : "Начать запись (⌘R)")
        }
    }
}
