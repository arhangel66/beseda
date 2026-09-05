import SwiftUI

struct CallSidebar: View {
    let controller: AppController

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !controller.upcomingEvents.isEmpty {
                        UpcomingEvents(controller: controller)
                            .padding(.bottom, 12)
                    }

                    if controller.isRecording {
                        LiveRecordingRow(controller: controller)
                            .padding(.bottom, 6)
                    }

                    ForEach(controller.groupedCalls) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            SectionCaption(text: group.day.title)
                                .padding(.horizontal, 10)
                                .padding(.top, 6)
                                .padding(.bottom, 4)

                            ForEach(group.calls) { call in
                                CallRow(
                                    call: call,
                                    query: controller.searchQuery,
                                    isSelected: controller.selectedCallDetail?.id == call.id,
                                    stage: controller.processingCallID == call.id ? controller.jobStage : nil,
                                    onSelect: { controller.selectCall(call) }
                                )
                            }
                        }
                        .padding(.bottom, 10)
                    }

                    if controller.groupedCalls.isEmpty && !controller.isRecording {
                        emptyState
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }

            Divider().overlay(Palette.separator)

            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: 11))
                Text(controller.storageLine)
                    .lineLimit(1)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Metrics.sidebarWidth)
        .background(Palette.sidebarBackground)
    }

    private var emptyState: some View {
        Text(controller.searchQuery.isEmpty
             ? "Пока ни одного разговора.\nЗапись начнётся сама, когда пойдёт звонок."
             : "Ничего не нашлось.\nПоиск идёт по темам, участникам и тексту разговоров.")
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.textTertiary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 40)
    }
}

/// What the calendar has until the end of tomorrow, with a guess at what will be recorded.
private struct UpcomingEvents: View {
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                Text("Дальше по календарю")
            }
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(Palette.textQuaternary)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(controller.upcomingEvents.prefix(5)) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(timeLabel(event))
                            .font(.system(size: 11.5))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 52, alignment: .trailing)

                        Text(event.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(controller.willRecord(event) ? "запишу" : "пропущу")
                            .font(.system(size: 10.5))
                            .foregroundStyle(controller.willRecord(event) ? Palette.okText : Palette.textQuaternary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Text("«Запишу» — догадка по ссылке на созвон в событии. Запись всё равно включает звук звонка.")
                .font(.system(size: 10.5))
                .lineSpacing(1)
                .foregroundStyle(Palette.textQuaternary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(Palette.fillHover, in: .rect(cornerRadius: 9))
    }

    private func timeLabel(_ event: CalendarEvent) -> String {
        Calendar.current.isDateInToday(event.startsAt) ? event.timeDescription : "завтра"
    }
}

private struct LiveRecordingRow: View {
    let controller: AppController

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Palette.recording)
                .frame(width: 9, height: 9)
                .opacity(isPulsing ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.isPaused ? "Пауза" : "Записываю звонок")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(CallFormatting.mmss(controller.elapsedRecordingSeconds))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Palette.recording.opacity(0.12), in: .rect(cornerRadius: Metrics.rowCorner))
    }
}

private struct CallRow: View {
    let call: StoredCallSummary
    let query: String
    let isSelected: Bool
    /// set only for the call being transcribed right now; it replaces the stale status line
    let stage: JobStage?
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(call.clockDescription)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                Text(call.durationDescription)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(secondaryStyle)
            }
            .frame(width: 52, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if call.isFromCalendar {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                            .opacity(0.6)
                    }
                    HighlightedText(text: call.displayTitle, query: query, isSelected: isSelected)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                }
                if let stage {
                    Text(stage.title)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryStyle)
                        .lineLimit(1)
                    ProgressTrack(value: stage.overall, tint: isSelected ? .white : Palette.accent)
                        .padding(.top, 2)
                } else {
                    Text(call.metaDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(secondaryStyle)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? Color.white : Palette.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Palette.accent : .clear, in: .rect(cornerRadius: Metrics.rowCorner))
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
    }

    private var secondaryStyle: Color {
        isSelected ? Color.white.opacity(0.78) : Palette.textSecondary
    }
}
