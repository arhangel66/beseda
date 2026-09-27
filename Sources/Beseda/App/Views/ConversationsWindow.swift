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
                    if controller.settings.sendsWebhooks || !controller.webhooks.selected.isEmpty {
                        SendToWebhookButton(controller: controller, detail: detail)
                    }
                    CopyTranscriptButton(controller: controller)
                    Button("Удалить", systemImage: "trash") {
                        controller.callPendingDeletion = detail.summary
                    }
                    .disabled(!controller.canDelete(detail.summary))
                    .help("Удалить разговор со всеми файлами")
                    .accessibilityLabel("Удалить разговор")
                }
                RecordingToolbarButton(controller: controller)
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .confirmationDialog(
            "Удалить «\(controller.callPendingDeletion?.displayTitle ?? "")»?",
            isPresented: Binding(
                get: { controller.callPendingDeletion != nil },
                set: { if !$0 { controller.callPendingDeletion = nil } }
            ),
            presenting: controller.callPendingDeletion
        ) { call in
            Button("Удалить", role: .destructive) {
                controller.deleteCall(call)
            }
            // the app has no Russian localization, so the system's own button would read «Cancel»
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text("Запись, расшифровка, итоги и копия в папке экспорта удалятся с этого Mac. Вернуть их не получится.")
        }
        .alert(
            "Не удалось удалить разговор",
            isPresented: Binding(
                get: { controller.deleteError != nil },
                set: { if !$0 { controller.deleteError = nil } }
            )
        ) {
            Button("ОК") {}
        } message: {
            Text(controller.deleteError ?? "")
        }
        .alert(
            "Не удалось прочитать разговоры",
            isPresented: Binding(
                get: { controller.callBrowserError != nil },
                set: { if !$0 { controller.callBrowserError = nil } }
            )
        ) {
            Button("ОК") {}
        } message: {
            Text(controller.callBrowserError ?? "")
        }
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
            #if DEBUG
            // screenshots: BESEDA_PREVIEW_CALL opens a call by id, BESEDA_PREVIEW_DELETE asks to delete it
            let environment = ProcessInfo.processInfo.environment
            if let id = environment["BESEDA_PREVIEW_CALL"] {
                controller.selectCall(id: id)
            }
            if environment["BESEDA_PREVIEW_DELETE"] != nil {
                controller.callPendingDeletion = controller.selectedCallDetail?.summary
            }
            #endif
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
            .accessibilityLabel("Остановить запись")
            .accessibilityValue((controller.isPaused ? "Пауза, " : "Идёт запись, ") + CallFormatting.mmss(controller.elapsedRecordingSeconds))
        } else {
            Button {
                controller.startCallRecording()
            } label: {
                Label("Записать", systemImage: "record.circle")
            }
            .disabled(controller.isBusy)
            .help(controller.isBusy ? "Дождитесь конца расшифровки" : "Начать запись (⌘R)")
            .accessibilityLabel("Начать запись")
        }
    }
}
