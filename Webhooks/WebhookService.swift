import Foundation

/// Hands finished calls to the webhook and keeps every attempt in the index.
/// Rows are the queue: a transient failure queues the next attempt with a later `next_retry_at`,
/// and the timer picks up whatever is due.
@MainActor
@Observable
final class WebhookService {
    static let tickInterval: TimeInterval = 60
    nonisolated static let minimumAutomaticCallDuration: TimeInterval = 2400
    nonisolated static let minimumAutomaticSpeechDuration: TimeInterval = 30

    /// attempt N failed → wait this long before attempt N+1; nil ends the chain
    nonisolated static func retryDelay(afterAttempt attempt: Int) -> TimeInterval? {
        switch attempt {
        case 1:
            60
        case 2:
            300
        case 3:
            1800
        default:
            nil
        }
    }

    /// the journal in settings
    private(set) var recent: [StoredWebhookDelivery] = []
    /// the open call's attempts
    private(set) var selected: [StoredWebhookDelivery] = []
    /// call ids with a request in flight
    private(set) var sending: Set<String> = []
    private(set) var testResult: String?
    private(set) var isTesting = false

    @ObservationIgnored var log: (String) -> Void = { _ in }
    @ObservationIgnored private let store: CallStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let sender: WebhookSender
    @ObservationIgnored private var selectedCallID: String?
    @ObservationIgnored private var ticker: Timer?

    init(store: CallStore, settings: AppSettings, sender: WebhookSender = WebhookSender()) {
        self.store = store
        self.settings = settings
        self.sender = sender
    }

    func start() {
        // rows the last run was quit in the middle of: the request may or may not have landed,
        // and the server dedupes, so the next attempt is safe
        do {
            for row in try store.failInterruptedWebhookDeliveries(reason: "Interrupted before the app restarted") {
                log("Webhook \(row.callID) attempt \(row.attempt) interrupted")
                scheduleRetry(after: row)
            }
        } catch {
            log("Webhook cleanup failed: \(error.localizedDescription)")
        }
        deliverDue()
        ticker = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.deliverDue()
            }
        }
    }

    /// the automatic send after a transcript is ready; writes nothing while the webhook is off
    func enqueue(callID: String) {
        guard settings.webhookEnabled, WebhookSender.endpoint(from: settings.webhookURL) != nil else {
            log("Webhook off, skipped \(callID)")
            return
        }
        do {
            guard let call = try store.fetchCall(id: callID) else {
                log("Webhook skipped \(callID): call not in the index")
                return
            }
            let segments = try store.fetchSegments(callID: callID)
            guard Self.qualifiesForAutomaticSend(call: call, segments: segments) else {
                log("Webhook automatic send skipped \(callID): call does not meet duration and speech requirements")
                return
            }
        } catch {
            log("Webhook automatic send check failed for \(callID): \(error.localizedDescription)")
            return
        }
        queue(callID: callID, nextRetryAt: Date())
    }

    /// «Отправить» / «Повторить»: one more attempt right now
    func sendNow(callID: String) {
        queue(callID: callID, nextRetryAt: Date())
    }

    func showCall(id: String?) {
        selectedCallID = id
        refresh()
    }

    func refresh() {
        do {
            recent = try store.fetchRecentWebhookDeliveries()
            selected = try selectedCallID.map { try store.fetchWebhookDeliveries(callID: $0) } ?? []
        } catch {
            log("Webhook journal failed: \(error.localizedDescription)")
        }
    }

    /// a probe the server can tell apart and skip; nothing is written to the index
    func sendTest() {
        guard !isTesting else {
            return
        }
        guard let url = WebhookSender.endpoint(from: settings.webhookURL) else {
            testResult = "Адрес не похож на URL"
            return
        }
        isTesting = true
        testResult = nil
        Task { [weak self] in
            guard let self else {
                return
            }
            defer { self.isTesting = false }
            let startedAt = Date()
            let body: Data
            do {
                body = try WebhookPayload.test(now: startedAt).encoded()
            } catch {
                self.testResult = error.localizedDescription
                return
            }
            let outcome = await self.sender.send(
                body, to: url, secret: self.settings.webhookSecret,
                event: WebhookPayload.testEvent, deliveryID: UUID().uuidString
            )
            let elapsed = String(format: "%.1f", Date().timeIntervalSince(startedAt))
            switch outcome {
            case .delivered(let status, let action, _):
                self.testResult = "Сервис ответил \(status)\(action.map { " · \($0)" } ?? "") за \(elapsed) с"
            case .rejected(401, _):
                self.testResult = "Секрет не подошёл (401)"
            case .rejected(let status, _):
                self.testResult = "Сервис отклонил запрос: HTTP \(status)"
            case .failed(_, _, let error):
                self.testResult = error
            }
        }
    }

    private func queue(callID: String, nextRetryAt: Date) {
        do {
            guard let call = try store.fetchCall(id: callID) else {
                log("Webhook skipped \(callID): call not in the index")
                return
            }
            try store.insertWebhookDelivery(
                id: UUID().uuidString,
                callID: callID,
                callTitle: call.displayTitle,
                attempt: try store.webhookAttemptCount(callID: callID) + 1,
                event: WebhookPayload.transcriptEvent,
                url: settings.webhookURL,
                nextRetryAt: nextRetryAt
            )
        } catch {
            log("Webhook queue failed for \(callID): \(error.localizedDescription)")
            return
        }
        refresh()
        deliverDue()
    }

    private func scheduleRetry(after row: StoredWebhookDelivery) {
        guard let delay = Self.retryDelay(afterAttempt: row.attempt) else {
            log("Webhook \(row.callID) gave up after attempt \(row.attempt)")
            return
        }
        do {
            try store.insertWebhookDelivery(
                id: UUID().uuidString,
                callID: row.callID,
                callTitle: row.callTitle,
                attempt: row.attempt + 1,
                event: row.event,
                url: row.url,
                nextRetryAt: Date().addingTimeInterval(delay)
            )
            log("Webhook \(row.callID) attempt \(row.attempt + 1) in \(Int(delay)) s")
        } catch {
            log("Webhook retry queue failed for \(row.callID): \(error.localizedDescription)")
        }
    }

    private func deliverDue() {
        let due: [StoredWebhookDelivery]
        do {
            due = try store.fetchDueWebhookDeliveries(now: Date())
        } catch {
            log("Webhook queue read failed: \(error.localizedDescription)")
            return
        }
        for row in due where !sending.contains(row.callID) {
            sending.insert(row.callID)
            Task { [weak self] in
                await self?.deliver(row)
            }
        }
    }

    private func deliver(_ row: StoredWebhookDelivery) async {
        defer {
            sending.remove(row.callID)
            refresh()
        }
        // switched off or a broken address: the row waits instead of burning an attempt
        guard settings.webhookEnabled, let url = WebhookSender.endpoint(from: settings.webhookURL) else {
            return
        }
        let outcome: WebhookOutcome
        do {
            guard let call = try store.fetchCall(id: row.callID) else {
                try store.finishWebhookDelivery(
                    id: row.id, state: "failed", httpStatus: nil, responseAction: nil,
                    responseBody: nil, error: "call deleted"
                )
                return
            }
            let detail = StoredCallDetail(
                summary: call,
                segments: try store.fetchSegments(callID: row.callID),
                speakerNames: try store.fetchSpeakerNames(callID: row.callID),
                markdownText: nil,
                jobStats: nil
            )
            try store.markWebhookSending(id: row.id, url: url.absoluteString)
            refresh()
            let body = try WebhookPayload.make(detail: detail).encoded()
            outcome = await sender.send(
                body, to: url, secret: settings.webhookSecret, event: row.event, deliveryID: row.id
            )
            try store.finishWebhookDelivery(
                id: row.id,
                state: outcome.state,
                httpStatus: outcome.httpStatus,
                responseAction: outcome.responseAction,
                responseBody: outcome.responseBody,
                error: outcome.error
            )
        } catch {
            log("Webhook \(row.callID) attempt \(row.attempt) broke: \(error.localizedDescription)")
            return
        }
        log("Webhook \(row.callID) attempt \(row.attempt): \(outcome.state) \(outcome.detailForLog)")
        if outcome.isRetryable {
            scheduleRetry(after: row)
        }
    }

    nonisolated static func qualifiesForAutomaticSend(
        call: StoredCallSummary,
        segments: [StoredTranscriptSegment]
    ) -> Bool {
        guard let duration = call.durationSec,
              duration.isFinite,
              duration > minimumAutomaticCallDuration else {
            return false
        }

        let segmentsBySpeaker = Dictionary(grouping: segments) { $0.speaker }
        guard recognizedSpeechDuration(in: segmentsBySpeaker[TranscriptChannel.microphone.speakerID] ?? [])
                >= minimumAutomaticSpeechDuration else {
            return false
        }

        return segmentsBySpeaker.contains { speaker, speakerSegments in
            speaker != TranscriptChannel.microphone.speakerID
                && recognizedSpeechDuration(in: speakerSegments) >= minimumAutomaticSpeechDuration
        }
    }

    private nonisolated static func recognizedSpeechDuration(
        in segments: [StoredTranscriptSegment]
    ) -> TimeInterval {
        let intervals = segments.compactMap { segment -> (start: Double, end: Double)? in
            guard !segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  segment.startSec.isFinite,
                  let end = segment.endSec,
                  end.isFinite,
                  end > segment.startSec else {
                return nil
            }
            return (segment.startSec, end)
        }
        .sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }

        guard var current = intervals.first else {
            return 0
        }
        var duration: TimeInterval = 0
        for interval in intervals.dropFirst() {
            if interval.start <= current.end {
                current.end = max(current.end, interval.end)
            } else {
                duration += current.end - current.start
                current = interval
            }
        }
        return duration + current.end - current.start
    }
}

private extension WebhookOutcome {
    var detailForLog: String {
        [httpStatus.map { "HTTP \($0)" }, responseAction, error].compactMap { $0 }.joined(separator: " · ")
    }
}
