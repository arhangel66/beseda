import SwiftUI

struct CallSidebar: View {
    let controller: AppController

    private var selection: Binding<String?> {
        Binding(
            get: { controller.selectedCallDetail?.id },
            set: { controller.selectCall(id: $0) }
        )
    }

    var body: some View {
        List(selection: selection) {
            if !controller.upcomingEvents.isEmpty {
                UpcomingEvents(controller: controller)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }

            if controller.isRecording {
                LiveRecordingRow(controller: controller)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }

            if controller.groupedCalls.isEmpty && !controller.isRecording {
                emptyState
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            }

            ForEach(controller.groupedCalls) { group in
                Section(group.day.title) {
                    ForEach(group.calls) { call in
                        CallRow(
                            call: call,
                            query: controller.searchQuery,
                            stage: controller.processingCallID == call.id ? controller.jobStage : nil
                        )
                        .tag(call.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text(controller.storageLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.bar)
        }
    }

    private var emptyState: some View {
        Group {
            if controller.searchQuery.isEmpty {
                ContentUnavailableView {
                    Label("Разговоров пока нет", systemImage: "waveform")
                } description: {
                    Text(controller.settings.autoDetectEnabled
                         ? "Запись начнётся сама, когда пойдёт звонок."
                         : "Автозапись выключена. Нажмите «Записать» или включите её в настройках.")
                }
            } else {
                ContentUnavailableView.search(text: controller.searchQuery)
            }
        }
    }
}

/// What the calendar has until the end of tomorrow, with a guess at what will be recorded.
private struct UpcomingEvents: View {
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Дальше по календарю", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(controller.upcomingEvents.prefix(5)) { event in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(timeLabel(event))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)

                    Text(event.title)
                        .font(.callout)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(controller.willRecord(event) ? "запишется" : "пропустится")
                        .font(.caption)
                        .foregroundStyle(controller.willRecord(event) ? Color.green : Color.secondary)
                }
            }

            Text("«Запишется» — догадка по ссылке на созвон в событии. Запись всё равно включает звук звонка.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func timeLabel(_ event: CalendarEvent) -> String {
        Calendar.current.isDateInToday(event.startsAt) ? event.timeDescription : "завтра"
    }
}

private struct LiveRecordingRow: View {
    let controller: AppController

    var body: some View {
        HStack(spacing: 10) {
            PulsingDot(size: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.isPaused ? "Пауза" : "Идёт запись")
                    .font(.body.weight(.semibold))
                Text(CallFormatting.mmss(controller.elapsedRecordingSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct CallRow: View {
    let call: StoredCallSummary
    let query: String
    /// set only for the call being transcribed right now; it replaces the stale status line
    let stage: JobStage?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if call.isFromCalendar {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HighlightedText(text: call.displayTitle, query: query)
                    .lineLimit(1)
            }
            if let stage {
                Text(stage.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: stage.overall)
                    .controlSize(.small)
            } else {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    /// the channels are the same for every call, so a ready call does not repeat them
    private var subtitle: String {
        if call.isFailed || call.status != "ready" {
            return "\(call.clockDescription) · \(call.metaDescription)"
        }
        return "\(call.clockDescription) · \(call.durationDescription) · \(call.appLabel)"
    }
}
