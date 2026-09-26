import Foundation
import Observation

/// The live preview of one recording: the loop's lines and «Ключевые моменты» for the popover.
/// Nothing here is written to the call folder or the index; the post-call pipeline stays the truth.
@MainActor
@Observable
final class LiveTranscription {
    private(set) var lines: [LiveLine] = []
    private(set) var keyPoints = ""

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var keyPointsTask: Task<Void, Never>?
    @ObservationIgnored private var schedule = KeyPointsSchedule()
    /// the transcript so far in, 3–5 bullet points out
    @ObservationIgnored private let summarize: @MainActor (String) async throws -> String
    @ObservationIgnored private let log: @MainActor (String) -> Void

    static let keyPointsPrompt = """
    Ниже — расшифровка звонка, который ещё идёт. «Я» — владелец записи, «Собеседник» — остальные.
    Выдели 3–5 ключевых моментов того, что обсудили к этому моменту. Ответь только списком: \
    каждый пункт с новой строки, начинается с «• », коротко, по-русски.
    """

    init(summarize: @escaping @MainActor (String) async throws -> String, log: @escaping @MainActor (String) -> Void) {
        self.summarize = summarize
        self.log = log
    }

    func start(
        microphoneURL: URL,
        systemURL: URL,
        transcribe: @escaping @Sendable ([Float]) async throws -> [TranscriptWord],
        droppedBuffers: @escaping @Sendable () -> Int,
        isPaused: @escaping @Sendable () -> Bool
    ) {
        let log = log
        let loop = LiveTranscriptionLoop(
            microphoneURL: microphoneURL,
            systemURL: systemURL,
            transcribe: transcribe,
            droppedBuffers: droppedBuffers,
            isPaused: isPaused,
            log: { message in Task { @MainActor in log(message) } },
            update: { [weak self] lines, recordedSeconds in
                await self?.show(lines, recordedSeconds: recordedSeconds)
            }
        )
        // recording always wins: the chunks run below the capture and the UI
        loopTask = Task.detached(priority: .utility) {
            await loop.run()
        }
    }

    /// returns once no chunk is in flight: after this the transcriber belongs to the post-call pipeline
    func stop() async {
        loopTask?.cancel()
        keyPointsTask?.cancel()
        await loopTask?.value
        loopTask = nil
        keyPointsTask = nil
    }

    private func show(_ lines: [LiveLine], recordedSeconds: Double) {
        self.lines = lines
        let text = lines.map { "\($0.channel == .microphone ? "Я" : "Собеседник"): \($0.text)" }.joined(separator: "\n")
        guard schedule.startRound(recordedSeconds: recordedSeconds, textLength: text.count) else {
            return
        }
        keyPointsTask = Task { [weak self, summarize, log] in
            do {
                let points = try await summarize(text)
                self?.keyPoints = points.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                log("Key points skipped: \(error.localizedDescription)")
            }
            self?.schedule.roundFinished()
        }
    }
}

#if DEBUG
extension LiveTranscription {
    /// canned lines and key points for `BESEDA_PREVIEW_POPOVER=live` screenshots: no capture, model or LLM
    static func preview() -> LiveTranscription {
        let live = LiveTranscription(summarize: { _ in "" }, log: { _ in })
        let said: [(TranscriptChannel, String)] = [
            (.systemAudio, "Добрый день, слышно меня нормально?"),
            (.microphone, "Да, всё отлично слышно. Давайте начнём с релиза."),
            (.systemAudio, "Релиз переносим на четверг, тестировщики не успели пройти регресс."),
            (.microphone, "Хорошо, а что с оплатой через новый шлюз?"),
            (.systemAudio, "Шлюз подключили, но возвраты пока работают только вручную."),
            (.microphone, "Тогда возвраты я беру на себя, сделаю к среде."),
            (.systemAudio, "Отлично. Ещё клиент просил выгрузку отчётов в Excel."),
            (.microphone, "Это можно, но не раньше следующего спринта."),
            (.systemAudio, "Договорились, я ему так и передам."),
            (.microphone, "И пришлите, пожалуйста, список багов после регресса."),
        ]
        live.lines = said.enumerated().map { index, line in
            LiveLine(channel: line.0, start: Double(index) * 12, text: line.1)
        }
        live.keyPoints = """
        • Релиз переносится на четверг из-за регресса
        • Новый шлюз подключён, возвраты пока вручную
        • Автоматические возвраты — на мне, срок среда
        • Выгрузка в Excel — в следующем спринте
        """
        return live
    }
}
#endif
