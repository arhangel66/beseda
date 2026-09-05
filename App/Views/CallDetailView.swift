import SwiftUI

enum CallDetailTab: String, CaseIterable, Identifiable {
    case transcript
    case summary
    case info

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .transcript:
            "Расшифровка"
        case .summary:
            "Саммари"
        case .info:
            "Инфо"
        }
    }
}

struct CallDetailView: View {
    let controller: AppController
    let player: CallPlayer
    /// with the list hidden the reading column centres itself, as in the prototype
    var isReadingCentred = false

    @State private var tab = CallDetailTab.transcript
    @State private var isLogOpen = false

    private var detail: StoredCallDetail? {
        controller.selectedCallDetail
    }

    var body: some View {
        VStack(spacing: 0) {
            if let detail {
                header(detail)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let stage = controller.jobStage, controller.processingCallID == detail.id {
                            ProgressBanner(stage: stage)
                        } else if detail.summary.isFailed {
                            FailureBanner(controller: controller, summary: detail.summary)
                        }

                        switch tab {
                        case .transcript:
                            TranscriptLines(
                                controller: controller,
                                detail: detail,
                                query: controller.searchQuery,
                                player: player
                            )
                        case .summary:
                            CallSummaryView(
                                text: detail.summary.summaryText,
                                isRunning: controller.summarizingCallID == detail.id,
                                error: controller.summaryError,
                                startedAt: controller.summaryStartedAt,
                                recovery: controller.summaryRecovery,
                                onGenerate: { controller.generateSummary() },
                                onRecover: { controller.startLocalModelServer() },
                                controller: controller
                            )
                        case .info:
                            CallInfo(detail: detail, isLogOpen: $isLogOpen, controller: controller)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: isReadingCentred ? .center : .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }

                PlayerBar(controller: controller, detail: detail, player: player)
            } else {
                ContentUnavailableView("Разговор не выбран", systemImage: "waveform")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.windowBackground)
        .onChange(of: controller.selectedCallDetail?.id) { _, _ in
            isLogOpen = false
            player.load(controller.selectedCallDetail?.summary)
            if controller.selectedCallDetail?.summary.isFailed == true {
                tab = .info
            }
        }
        .onAppear {
            player.load(controller.selectedCallDetail?.summary)
        }
    }

    private func header(_ detail: StoredCallDetail) -> some View {
        let summary = detail.summary
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(summary.whenHeadline)
                        .font(.system(size: 21, weight: .semibold))
                        .monospacedDigit()
                        .tracking(-0.3)

                    NameLine(controller: controller, summary: summary)

                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Avatar(initials: nil, fallbackSymbol: summary.isDual ? "person.2" : "mic", size: 20)
                            Text(summary.isDual ? "Вы и собеседник" : "Микрофон")
                        }
                        separatorDot
                        Text(summary.appLabel)

                        if summary.isDual {
                            HStack(spacing: 5) {
                                Image(systemName: "mic")
                                    .font(.system(size: 9))
                                Text("два канала")
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(Palette.fillSubtle, in: .rect(cornerRadius: 5))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                }

                Spacer(minLength: 0)

                if controller.settings.webhookEnabled || !controller.webhooks.selected.isEmpty {
                    SendToWebhookButton(controller: controller, detail: detail)
                }
                CopyTranscriptButton(controller: controller)
            }

            SegmentedTabs(tabs: CallDetailTab.allCases, selection: $tab) { $0.title }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var separatorDot: some View {
        Text("·").opacity(0.4)
    }
}

/// The name of the conversation, where it came from, and the way to change it.
private struct NameLine: View {
    let controller: AppController
    let summary: StoredCallSummary

    @State private var isPickerOpen = false

    var body: some View {
        HStack(spacing: 8) {
            if summary.isFromCalendar {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .opacity(0.55)
            }

            Text(summary.displayTitle)
                .font(.system(size: 14.5, weight: .medium))
                .lineLimit(2)

            Text(summary.titleSource)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(Palette.fillSubtle, in: .rect(cornerRadius: 5))

            if controller.settings.calendarEnabled {
                Button {
                    isPickerOpen = true
                } label: {
                    Text(summary.isFromCalendar ? "Изменить" : "Привязать событие")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
                    EventPicker(controller: controller, summary: summary, isOpen: $isPickerOpen)
                }
            }
        }
    }
}

private struct EventPicker: View {
    let controller: AppController
    let summary: StoredCallSummary
    @Binding var isOpen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("События рядом с \(summary.whenDescription)")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 4)

            ForEach(controller.eventCandidates(for: summary)) { event in
                row(title: event.title, meta: event.timeDescription, isChosen: event.title == summary.eventTitle) {
                    controller.assignEvent(event, to: summary)
                }
            }

            row(title: "Без события", meta: "название останется по теме разговора", isChosen: !summary.isFromCalendar) {
                controller.assignEvent(nil, to: summary)
            }
        }
        .padding(5)
        .frame(width: 320)
    }

    private func row(title: String, meta: String, isChosen: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            isOpen = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 13)
                    .opacity(isChosen ? 1 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                    Text(meta)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Krisp's «Send to Webhook»: the left half sends, the right half opens the attempt history.
/// The icon carries the last outcome so the row stays one line.
private struct SendToWebhookButton: View {
    let controller: AppController
    let detail: StoredCallDetail

    @State private var isHistoryOpen = false
    @State private var isHovering = false

    private var deliveries: [StoredWebhookDelivery] {
        controller.webhooks.selected
    }

    private var isSending: Bool {
        controller.webhooks.sending.contains(detail.id)
    }

    private var canSend: Bool {
        controller.settings.webhookEnabled && !isSending && !detail.segments.isEmpty
    }

    var body: some View {
        HStack(spacing: 1) {
            Button {
                controller.webhooks.sendNow(callID: detail.id)
            } label: {
                HStack(spacing: 8) {
                    if isSending {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundStyle(iconColor)
                    }
                    Text(deliveries.first?.state == "failed" ? "Повторить на вебхук" : "Отправить на вебхук")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(canSend ? Palette.textPrimary : Palette.textQuaternary)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(fill, in: .rect(topLeadingRadius: 9, bottomLeadingRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help(statusLine)

            Button {
                isHistoryOpen = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 28, height: 34)
                    .background(fill, in: .rect(bottomTrailingRadius: 9, topTrailingRadius: 9))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isHistoryOpen, arrowEdge: .bottom) {
                history
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Palette.controlBorder, lineWidth: 0.5)
        }
        .fixedSize()
        .onHover { isHovering = $0 }
    }

    private var fill: Color {
        isHovering ? Palette.fillHover : Palette.fillRaised
    }

    private var icon: String {
        switch deliveries.first?.state {
        case "delivered":
            "checkmark.circle.fill"
        case "failed":
            "exclamationmark.triangle.fill"
        case "queued":
            "clock"
        default:
            "paperplane"
        }
    }

    private var iconColor: Color {
        switch deliveries.first?.state {
        case "delivered":
            Palette.okText
        case "failed":
            Palette.recording
        default:
            canSend ? Palette.textPrimary : Palette.textQuaternary
        }
    }

    private var statusLine: String {
        guard let latest = deliveries.first else {
            return controller.settings.webhookEnabled ? "Ещё не отправлялся" : "Вебхук выключен в настройках"
        }
        return [latest.stateLabel, latest.detailLine].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Доставки")
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.bottom, 2)
            if deliveries.isEmpty {
                Text(statusLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
            }
            ForEach(deliveries) { delivery in
                WebhookDeliveryRow(delivery: delivery, inJournal: false, controller: controller)
            }
        }
        .padding(12)
        .frame(width: 340)
    }
}

/// The split button from the prototype: the left half copies, the right half picks the format.
private struct CopyTranscriptButton: View {
    let controller: AppController

    @State private var isMenuOpen = false

    var body: some View {
        HStack(spacing: 1) {
            Button {
                controller.copyTranscript()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                    Text("Скопировать расшифровку")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .frame(height: 34)
                .background(Palette.accent, in: .rect(topLeadingRadius: 9, bottomLeadingRadius: 9))
            }
            .buttonStyle(.plain)

            Button {
                isMenuOpen = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 34)
                    .background(Palette.accent, in: .rect(bottomTrailingRadius: 9, topTrailingRadius: 9))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isMenuOpen, arrowEdge: .bottom) {
                menu
            }
        }
        .fixedSize()
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(TranscriptCopyFormat.allCases) { format in
                Button {
                    controller.copyTranscript(format: format)
                    isMenuOpen = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 13)
                            .opacity(controller.settings.copyFormat == format ? 1 : 0)
                        Text(format.title)
                            .font(.system(size: 12.5))
                        Spacer(minLength: 12)
                        Text(format.sample)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textQuaternary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(Palette.separator).padding(.horizontal, 6)

            Text("Выбранный формат станет форматом по умолчанию и для ⌘C.")
                .font(.system(size: 11))
                .lineSpacing(1)
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, 8)
                .padding(.top, 3)
                .padding(.bottom, 5)
        }
        .padding(5)
        .frame(width: 292)
    }
}

/// What is happening to this call right now. The retry button used to grey out and leave
/// the pane exactly as it was, which reads as nothing having happened at all.
private struct ProgressBanner: View {
    let stage: JobStage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(stage.title)
                    .font(.system(size: 13, weight: .semibold))

                Text(stage.caption())
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)

                ProgressTrack(value: stage.overall)
                    .frame(maxWidth: 420)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.accent.opacity(0.09), in: .rect(cornerRadius: Metrics.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCorner)
                .strokeBorder(Palette.accent.opacity(0.3), lineWidth: 0.5)
        }
    }
}

private struct FailureBanner: View {
    let controller: AppController
    let summary: StoredCallSummary

    private var isRuntimeMissing: Bool {
        summary.error == BesedaError.runtimeMissingMessage && !controller.runtime.isReady
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15))
                .foregroundStyle(Palette.recording)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(isRuntimeMissing ? "Расшифровка не собралась: модель не скачана" : "Расшифровка не собралась")
                    .font(.system(size: 13, weight: .semibold))

                Text(bodyText)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: 520, alignment: .leading)

                if isRuntimeMissing {
                    SpeechModelList(controller: controller)
                        .frame(maxWidth: 520)
                }

                HStack(spacing: 8) {

                    OutlineButton(height: 24) {
                        controller.retryCall(summary)
                    } label: {
                        Text("Расшифровать снова")
                    }
                    .disabled(controller.isBusy)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.recording.opacity(0.09), in: .rect(cornerRadius: Metrics.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCorner)
                .strokeBorder(Palette.recording.opacity(0.3), lineWidth: 0.5)
        }
    }

    private var bodyText: String {
        let audio = "Аудио записано и лежит на месте — \(summary.durationDescription)\(summary.isDual ? " в двух каналах" : "")."
        if isRuntimeMissing {
            return "\(audio) Как только движок скачается, нажмите «Расшифровать снова»."
        }
        return "\(audio) \(summary.error ?? "")"
    }
}

/// Reads the player itself: a tick then repaints this list, not the whole detail pane.
private struct TranscriptLines: View {
    let controller: AppController
    let detail: StoredCallDetail
    let query: String
    let player: CallPlayer

    @State private var renamedSpeaker: String?
    @State private var draftName = ""

    private var activeIndex: Int? {
        guard player.isPlaying || player.currentTime > 0 else {
            return nil
        }
        return detail.segments.lastIndex { $0.startSec <= player.currentTime }
    }

    var body: some View {
        if detail.segments.isEmpty {
            Text(detail.markdownText ?? "Расшифровки пока нет.")
                .font(.system(size: 14))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
        } else {
            let active = activeIndex
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(detail.segments.enumerated()), id: \.element.id) { index, segment in
                    TranscriptLine(
                        segment: segment,
                        name: SpeakerNaming.name(for: segment.speaker, overrides: detail.speakerNames),
                        initial: SpeakerNaming.initial(for: segment.speaker, overrides: detail.speakerNames),
                        query: query,
                        isActive: index == active,
                        onSeek: { player.seek(to: segment.startSec) },
                        onRename: { startRenaming(segment.speaker) }
                    )
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .alert("Как зовут участника?", isPresented: isRenaming) {
                TextField("Имя", text: $draftName)
                Button("Отмена", role: .cancel) { renamedSpeaker = nil }
                Button("Сохранить") { commitRename() }
            } message: {
                Text("Имя видно только в этом разговоре.")
            }
        }
    }
}

private extension TranscriptLines {
    var isRenaming: Binding<Bool> {
        Binding(get: { renamedSpeaker != nil }, set: { if !$0 { renamedSpeaker = nil } })
    }

    func startRenaming(_ speaker: String) {
        draftName = detail.speakerNames[speaker] ?? ""
        renamedSpeaker = speaker
    }

    func commitRename() {
        if let renamedSpeaker {
            controller.renameSpeaker(renamedSpeaker, to: draftName)
        }
        renamedSpeaker = nil
    }
}

private struct TranscriptLine: View {
    let segment: StoredTranscriptSegment
    let name: String
    let initial: String
    let query: String
    let isActive: Bool
    let onSeek: () -> Void
    let onRename: () -> Void

    private var style: SpeakerStyle {
        .of(speaker: segment.speaker)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(initial)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(style.ink)
                    .frame(width: 20, height: 20)
                    .background(style.soft, in: .circle)

                Text(name)
                    .font(.system(size: 12.5, weight: .semibold))

                Text(CallFormatting.mmss(segment.startSec))
                    .font(.system(size: 11.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? Palette.accent : Palette.textQuaternary)
            }

            HighlightedText(text: segment.text, query: query)
                .font(.system(size: 14))
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(style.bar)
                        .frame(width: 2)
                }
                .padding(.leading, 9)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? Palette.activeLine : .clear, in: .rect(cornerRadius: Metrics.rowCorner))
        .contentShape(.rect)
        .onTapGesture(perform: onSeek)
        .contextMenu {
            Button("Переименовать участника…", action: onRename)
        }
    }
}

private struct CallInfo: View {
    let detail: StoredCallDetail
    @Binding var isLogOpen: Bool
    let controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                ForEach(rows, id: \.key) { row in
                    GridRow {
                        Text(row.key)
                            .foregroundStyle(Palette.textTertiary)
                            .gridColumnAlignment(.leading)
                            .frame(width: 168, alignment: .leading)
                        Text(row.value)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .font(.system(size: 12.5))

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    isLogOpen.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(isLogOpen ? 90 : 0))
                        Text("Технический лог")
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)

                if isLogOpen {
                    Text(logText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .lineSpacing(5)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Palette.fillSubtle, in: .rect(cornerRadius: Metrics.rowCorner))
                }
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var rows: [(key: String, value: String)] {
        let summary = detail.summary
        var rows: [(String, String)] = [
            ("Записан", summary.whenDescription),
            ("Каналы", summary.isDual ? "микрофон + системный звук" : "микрофон"),
            ("Длительность", CallFormatting.hms(summary.duration)),
            ("Состояние", summary.status)
        ]
        if let eventTitle = summary.eventTitle {
            rows.append(("Событие календаря", eventTitle))
        }
        if let stats = detail.jobStats {
            rows.append(("Скорость", stats.description))
            rows.append(("Модель", stats.model.flatMap { SpeechModel.named($0)?.title } ?? stats.model ?? "неизвестно"))
        }
        rows.append(("Вебхук", webhookLine))
        rows.append(("Папка", summary.audioDirectoryPath))
        if let error = summary.error, !error.isEmpty {
            rows.append(("Ошибка", error))
        }
        return rows.map { (key: $0.0, value: $0.1) }
    }

    private var webhookLine: String {
        guard let latest = controller.webhooks.selected.first else {
            return controller.settings.webhookEnabled ? "не отправлялся" : "выключен"
        }
        return [latest.stateLabel, latest.detailLine].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// the capture writes session.json next to the audio: the only per-call technical record
    private var logText: String {
        let sessionURL = detail.summary.audioDirectoryURL.appendingPathComponent("session.json")
        guard let text = try? String(contentsOf: sessionURL, encoding: .utf8) else {
            return "session.json не найден в папке разговора"
        }
        return text
    }
}
