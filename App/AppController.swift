import AppKit
import Foundation
import Observation

/// what the retry button in the summary error card should do about it
enum SummaryRecovery: Equatable {
    case startServer
    case openSettings
}

@MainActor
@Observable
final class AppController {
    enum Status: Equatable {
        case idle
        case recording(TimeInterval)
        case callRecording
        case autoRecording(String)
        /// every step between a finished recording and a finished transcript
        case working(JobStage)
        case completed
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .idle, .completed, .failed:
                false
            case .recording, .callRecording, .autoRecording, .working:
                true
            }
        }

        var canStop: Bool {
            switch self {
            case .recording, .callRecording, .autoRecording:
                true
            default:
                false
            }
        }

        var title: String {
            switch self {
            case .idle:
                "Жду"
            case .recording(let duration):
                "Записываю \(Int(duration)) с"
            case .callRecording:
                "Записываю звонок"
            case .autoRecording(let app):
                "Записываю \(app)"
            case .working(let stage):
                stage.title
            case .completed:
                "Готово"
            case .failed:
                "Не получилось"
            }
        }

        var systemImage: String {
            switch self {
            case .idle:
                "waveform"
            case .recording, .callRecording, .autoRecording:
                "record.circle"
            case .working:
                "text.bubble"
            case .completed:
                "checkmark.circle"
            case .failed:
                "exclamationmark.triangle"
            }
        }
    }

    var status: Status = .idle
    var workerDescription = "ASR worker not started"
    var lastTranscript: TranscriptResult?
    var lastDualTranscript: DualTranscriptResult?
    var lastError: String?
    var recentCalls: [StoredCallSummary] = []
    var callBrowserCalls: [StoredCallSummary] = []
    var selectedCallDetail: StoredCallDetail?
    var callBrowserError: String?
    var logMessages: [String] = []
    var elapsedRecordingSeconds: TimeInterval = 0
    var isPaused = false
    var microphoneLevel: Double = 0
    var systemAudioLevel: Double = 0
    var lastReadyCallID: String?
    /// the call the pipeline is working on right now, so its row and pane can say so
    var processingCallID: String?
    /// the call a summary is being written for, so the spinner belongs to a call and not to the app
    var summarizingCallID: String?
    var summaryError: String?
    var summaryRecovery: SummaryRecovery?
    /// when the current summary request started, so the view can count seconds
    var summaryStartedAt: Date?
    var isStartingLocalModelServer = false
    /// Settings → Обработка: server status, its models, and the last «Проверить» result
    var summaryServerStatus: String?
    /// true only when discovery ran and found no running server — never set for a manual server URL
    var isServerDown = false
    var summaryModels: [String] = []
    var summaryCheckResult: String?
    var isCheckingSummary = false
    var searchQuery = "" {
        didSet {
            refreshTranscriptMatches()
        }
    }
    var upcomingEvents: [CalendarEvent] = []
    var eventCoverage: (matched: Int, total: Int) = (0, 0)
    var storageUsage = StorageUsage()
    var expiredAudioBytes: Int64 = 0
    var toast: String?
    /// a SettingsLink is a dead end, so the view that offers it names the section to land on
    var requestedSettingsSection: String?

    @ObservationIgnored private let fileManager = FileManager.default
    @ObservationIgnored private let transcriber = LocalTranscriber(paths: AppPaths.current)
    @ObservationIgnored private let diarizer = Diarizer()
    @ObservationIgnored private let callStore = CallStore()
    @ObservationIgnored private let callDetector = CallDetector()
    @ObservationIgnored private let notifier = CallNotifier()
    @ObservationIgnored let calendarService = CalendarService()
    /// a call with no event nearby would otherwise be looked up again on every refresh
    @ObservationIgnored private var eventMatchAttempted: Set<String> = []
    @ObservationIgnored let settings = AppSettings()
    @ObservationIgnored let webhooks: WebhookService
    @ObservationIgnored let runtime: RuntimeInstaller
    @ObservationIgnored let updater = AppUpdater()
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var activeDualCapture: DualCapture?
    @ObservationIgnored private var cancelRequested = false
    @ObservationIgnored private var liveTicker: Timer?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private let janitor = StorageJanitor(callsDirectory: AppPaths.current.callsDirectory)
    @ObservationIgnored private var transcriptMatchIDs: Set<String>?
    @ObservationIgnored private var dailySweep: Timer?
    /// set by the app scene: a notification callback has no `openWindow` environment value
    @ObservationIgnored var showMainWindow: (() -> Void)?

    /// an auto-started recording shorter than this is a misfire — a voice message or dictation, not a call
    private static let minimumAutoRecordingDuration: TimeInterval = 10

    deinit {
        transcriber.stop()
    }

    /// called on the way out: the speech model must be freed before the process exits
    func shutdown() {
        transcriber.shutdown()
    }

    var menuBarSystemImage: String {
        isPaused && isRecording ? "pause.circle" : status.systemImage
    }

    /// mm:ss while recording, an ellipsis while the transcript is being built
    var menuBarLabel: String? {
        switch status {
        case .recording, .callRecording, .autoRecording:
            CallFormatting.mmss(elapsedRecordingSeconds)
        case .working:
            "···"
        default:
            nil
        }
    }

    var isRecording: Bool {
        status.canStop
    }

    var jobStage: JobStage? {
        guard case .working(let stage) = status else {
            return nil
        }
        return stage
    }

    var isBusy: Bool {
        status.isBusy
    }

    var callsDirectory: URL {
        AppPaths.current.callsDirectory
    }

    var latestMarkdownURL: URL? {
        lastDualTranscript?.markdownURL ?? lastTranscript?.markdownURL
    }

    var latestTranscriptText: String? {
        lastDualTranscript?.text ?? lastTranscript?.text
    }

    init() {
        // before anything logs or opens the index: the folder may still carry the old name
        let migration = Result { try LegacyDataMigration.run(from: AppPaths.legacyDataDirectory, to: AppPaths.current) }
        webhooks = WebhookService(store: callStore, settings: settings)
        let transcriber = transcriber
        let selectedModel = settings.speechModel
        transcriber.select(selectedModel)
        runtime = RuntimeInstaller(paths: AppPaths.current, model: selectedModel) {
            _ = try await transcriber.start()
        }
        transcriber.diagnosticsHandler = { [weak self] message in
            Task { @MainActor in
                self?.appendLog(message)
            }
        }
        transcriber.progressHandler = { [weak self] fraction in
            Task { @MainActor in
                self?.advanceStage(to: fraction)
            }
        }

        wireCallDetector()
        wireNotifier()
        webhooks.log = { [weak self] message in
            self?.appendLog(message)
        }
        runtime.log = { [weak self] message in
            self?.appendLog(message)
        }
        updater.start { [unowned self] in self.isRecording }
        applyAutoDetectSettings()
        observeAutoDetectSettings()

        switch migration {
        case .success(true):
            appendLog("Moved \(AppPaths.legacyDataDirectory.path) to \(AppPaths.current.dataDirectory.path)")
        case .failure(let error):
            appendLog("Legacy data left in place: \(error.localizedDescription)")
        default:
            break
        }

        let freed = PythonRuntimeCleanup.run(AppPaths.current)
        if freed > 0 {
            appendLog("Removed the old Python engine, freed \(freed.byteSizeDescription)")
        }

        do {
            try callStore.prepare()
            let sweptCalls = try callStore.failInterruptedCalls(reason: "Interrupted before the app restarted")
            if sweptCalls > 0 {
                appendLog("Marked \(sweptCalls) interrupted call(s) as failed")
            }
            webhooks.start()
            refreshRecentCalls()
            appendLog("Call index ready: \(AppPaths.current.callIndexURL.path)")
        } catch {
            appendLog("Call index unavailable: \(error.localizedDescription)")
        }


        startDailySweep()
    }

    func stopActiveRecording() {
        guard let capture = activeDualCapture else {
            return
        }
        appendLog("Manual stop")
        capture.stop()
    }

    func startCallRecording(
        maxDuration: TimeInterval = 4 * 60 * 60,
        autoStartedApp: String? = nil
    ) {
        guard !status.isBusy else {
            return
        }

        let silenceStop: TimeInterval? = settings.stopOnSilence ? 60 : nil
        activeTask = Task { [weak self] in
            await self?.runDualRecording(
                maxDuration: maxDuration,
                autoStopSilenceDuration: silenceStop,
                autoStartedApp: autoStartedApp
            )
        }
    }

    /// the ⌘R menu command: one key starts a recording or stops the running one
    func toggleRecording() {
        if isRecording {
            stopActiveRecording()
        } else {
            startCallRecording()
        }
    }

    func togglePause() {
        guard let capture = activeDualCapture else {
            return
        }
        isPaused.toggle()
        capture.setPaused(isPaused)
    }

    // MARK: - Conversations list

    var visibleCalls: [StoredCallSummary] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return callBrowserCalls
        }
        return callBrowserCalls.filter { call in
            call.searchableText.contains(query) || transcriptMatchIDs?.contains(call.id) == true
        }
    }

    var groupedCalls: [CallGroup] {
        var groups: [CallDayGroup: [StoredCallSummary]] = [:]
        for call in visibleCalls {
            groups[call.dayGroup, default: []].append(call)
        }
        return groups
            .sorted { $0.key < $1.key }
            .map { CallGroup(day: $0.key, calls: $0.value) }
    }

    var storageLine: String {
        let calls = CallFormatting.plural(callBrowserCalls.count, "разговор", "разговора", "разговоров")
        return "Локально · \(calls) · \(storageUsage.audioBytes.byteSizeDescription) аудио"
    }

    func selectCall(_ call: StoredCallSummary) {
        selectCall(id: call.id)
    }

    /// a format given here also becomes the default, as the menu under the button promises
    func copyTranscript(format: TranscriptCopyFormat? = nil) {
        guard let detail = selectedCallDetail else {
            return
        }
        if let format {
            settings.copyFormat = format
        }
        let text = TranscriptCopy.render(detail, format: settings.copyFormat)
        guard !text.isEmpty else {
            flash("Расшифровки пока нет")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash("Скопировано: \(settings.copyFormat.title.lowercased())")
    }

    // MARK: - Calendar

    /// turning the switch on is also when access is asked for: nothing happens before that
    func setCalendarEnabled(_ enabled: Bool) {
        settings.calendarEnabled = enabled
        eventMatchAttempted = []
        guard enabled else {
            upcomingEvents = []
            return
        }
        Task { [weak self] in
            guard let self else {
                return
            }
            if !calendarService.isAuthorized {
                _ = await calendarService.requestAccess()
            }
            refreshCalendar()
        }
    }

    func refreshCalendar() {
        guard settings.calendarEnabled, calendarService.isAuthorized else {
            upcomingEvents = []
            return
        }
        matchCalendarEvents()
        refreshUpcomingEvents()
        eventCoverage = (try? callStore.eventCoverage()) ?? (0, 0)
    }

    /// events near the call's start, for the picker in the detail header
    func eventCandidates(for call: StoredCallSummary) -> [CalendarEvent] {
        guard settings.calendarEnabled, calendarService.isAuthorized, let start = call.startedDate else {
            return []
        }
        return calendarService.events(
            from: start.addingTimeInterval(-2 * 60 * 60),
            to: start.addingTimeInterval(2 * 60 * 60),
            identifiers: settings.calendarIdentifiers
        )
    }

    /// nil means "Без события": the name falls back to the transcript and stays pinned there
    func assignEvent(_ event: CalendarEvent?, to call: StoredCallSummary) {
        do {
            try callStore.setEvent(callID: call.id, title: event?.title, eventID: event?.id, pinned: true)
            eventMatchAttempted.insert(call.id)
            refreshCallBrowser()
            eventCoverage = (try? callStore.eventCoverage()) ?? eventCoverage
        } catch {
            appendLog("Event link failed: \(error.localizedDescription)")
        }
    }

    /// the guess behind «запишу» in the sidebar: auto-record is on and the event carries a call link
    func willRecord(_ event: CalendarEvent) -> Bool {
        settings.autoDetectEnabled && event.hasConferenceLink
    }

    private func refreshUpcomingEvents() {
        let now = Date()
        guard let endOfTomorrow = Calendar.current.date(
            byAdding: .day,
            value: 2,
            to: Calendar.current.startOfDay(for: now)
        ) else {
            return
        }
        upcomingEvents = calendarService.events(
            from: now,
            to: endOfTomorrow,
            identifiers: settings.calendarIdentifiers
        )
    }

    private func matchCalendarEvents() {
        let pending = callBrowserCalls.filter {
            !$0.eventPinned && $0.eventTitle == nil && !eventMatchAttempted.contains($0.id)
        }
        guard let earliest = pending.compactMap(\.startedDate).min(),
              let latest = pending.compactMap(\.startedDate).max() else {
            return
        }
        let events = calendarService.events(
            from: earliest.addingTimeInterval(-60 * 60),
            to: latest.addingTimeInterval(60 * 60),
            identifiers: settings.calendarIdentifiers
        )
        var matched = false
        for call in pending {
            eventMatchAttempted.insert(call.id)
            guard let start = call.startedDate,
                  let event = CalendarService.match(events: events, callStart: start) else {
                continue
            }
            do {
                try callStore.setEvent(callID: call.id, title: event.title, eventID: event.id, pinned: false)
                matched = true
            } catch {
                appendLog("Event match failed: \(error.localizedDescription)")
            }
        }
        if matched {
            callBrowserCalls = (try? callStore.fetchCalls(limit: 200)) ?? callBrowserCalls
        }
    }

    // MARK: - Storage

    /// walks the calls folder, so it is called on demand and never from a view body
    func refreshStorageUsage() {
        storageUsage = janitor.measure()
        guard let protected = protectedAudioDirectories() else {
            expiredAudioBytes = 0
            return
        }
        expiredAudioBytes = janitor.expiredBytes(rules: settings.retentionRules, protecting: protected)
    }

    func runCleanupNow() {
        guard let protected = protectedAudioDirectories() else {
            appendLog("Cleanup skipped: the call index is unavailable")
            flash("Уборка не вышла: индекс звонков недоступен")
            return
        }
        let freed = janitor.sweep(rules: settings.retentionRules, protecting: protected)
        refreshStorageUsage()
        appendLog("Cleanup freed \(freed.byteSizeDescription)")
        flash(freed > 0 ? "Освободилось \(freed.byteSizeDescription)" : "Удалять нечего")
    }

    /// nil means we could not tell which calls still need their audio, and then nothing may be swept
    private func protectedAudioDirectories() -> Set<String>? {
        try? callStore.protectedAudioDirectories()
    }

    // MARK: - Speech engine

    /// Makes a model the active one, downloading it first when it is not on disk yet.
    func selectSpeechModel(_ model: SpeechModel) {
        guard !isBusy else {
            flash("Дождитесь конца расшифровки")
            return
        }
        settings.speechModelID = model.id
        transcriber.stop()
        transcriber.select(model)
        runtime.select(model)
        if !runtime.isReady {
            runtime.install()
        }
    }

    func removeSpeechModel(_ model: SpeechModel) {
        guard !isBusy else {
            flash("Дождитесь конца расшифровки")
            return
        }
        transcriber.stop()
        do {
            try runtime.remove(model)
        } catch {
            flash("Не получилось удалить: \(error.localizedDescription)")
        }
    }

    // MARK: - Toast

    func flash(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.9))
            guard !Task.isCancelled else {
                return
            }
            self?.toast = nil
        }
    }

    private func wireCallDetector() {
        callDetector.isManualRecordingActive = { [weak self] in
            switch self?.status {
            case .recording, .callRecording:
                true
            default:
                false
            }
        }
        callDetector.onShouldStart = { [weak self] detection in
            self?.startDetectedCall(detection)
        }
        callDetector.onShouldStop = { [weak self] in
            self?.activeDualCapture?.stop()
        }
        callDetector.onDiagnostics = { [weak self] message in
            self?.appendLog(message)
        }
    }

    private func wireNotifier() {
        notifier.onCancelAutoRecording = { [weak self] in
            self?.cancelAutoRecording()
        }
        notifier.onOpenCalls = { [weak self] in
            self?.showMainWindow?()
        }
        notifier.onDiagnostics = { [weak self] message in
            self?.appendLog(message)
        }
        notifier.start()
    }

    private func cancelAutoRecording() {
        // only stops the capture here; `runDualRecording` discards the call through the junk-guard path
        guard case .autoRecording = status, let capture = activeDualCapture else {
            return
        }
        cancelRequested = true
        appendLog("Cancel and delete requested")
        capture.stop()
    }

    private func applyAutoDetectSettings() {
        callDetector.allowedBundleIDs = settings.enabledCallApps
        guard settings.autoDetectEnabled != callDetector.isRunning else {
            return
        }
        if settings.autoDetectEnabled {
            callDetector.start()
            appendLog("Auto-detect on")
        } else {
            callDetector.stop()
            appendLog("Auto-detect off")
        }
    }

    private func observeAutoDetectSettings() {
        withObservationTracking {
            _ = settings.autoDetectEnabled
            _ = settings.enabledCallApps
        } onChange: { [weak self] in
            // onChange fires before the new value lands, so read it on the next turn and re-arm
            Task { @MainActor in
                self?.applyAutoDetectSettings()
                self?.observeAutoDetectSettings()
            }
        }
    }

    private func startDetectedCall(_ detection: CallDetector.Detection) {
        guard !status.isBusy else {
            // still transcribing an earlier call: release the policy so it can offer this call again
            appendLog("Auto-detect: busy, skipped \(detection.appName)")
            callDetector.recordingEnded()
            return
        }
        startCallRecording(autoStartedApp: detection.appName)
    }

    func restartWorker() {
        transcriber.stop()
        workerDescription = "ASR worker stopped"
        appendLog("ASR worker stopped")
        if !status.isBusy {
            status = .idle
        }
    }

    func quit() {
        transcriber.stop()
        NSApplication.shared.terminate(nil)
    }

    func openCallsFolder() {
        do {
            try fileManager.createDirectory(at: callsDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(callsDirectory)
        } catch {
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
        }
    }

    func openCall(_ call: StoredCallSummary) {
        if let transcriptURL = call.transcriptURL, fileManager.fileExists(atPath: transcriptURL.path) {
            NSWorkspace.shared.open(transcriptURL)
            return
        }
        NSWorkspace.shared.open(call.audioDirectoryURL)
    }

    func revealCall(_ call: StoredCallSummary) {
        if let transcriptURL = call.transcriptURL, fileManager.fileExists(atPath: transcriptURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([transcriptURL])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([call.audioDirectoryURL])
    }

    func refreshRecentCalls() {
        do {
            recentCalls = try callStore.fetchRecentCalls(limit: 10)
            if !callBrowserCalls.isEmpty {
                callBrowserCalls = try callStore.fetchCalls(limit: 200)
            }
            // the open pane held the summary from before the retry, failure banner and all
            if let selected = selectedCallDetail,
               let fresh = (callBrowserCalls + recentCalls).first(where: { $0.id == selected.id }),
               fresh.status != selected.summary.status {
                loadCallDetail(fresh)
            }
        } catch {
            appendLog("Recent calls failed: \(error.localizedDescription)")
        }
    }

    func refreshCallBrowser(selectFirstIfNeeded: Bool = false) {
        do {
            callBrowserError = nil
            callBrowserCalls = try callStore.fetchCalls(limit: 200)
            if settings.calendarEnabled, calendarService.isAuthorized {
                matchCalendarEvents()
            }

            if let selectedCallDetail,
               let selectedCall = callBrowserCalls.first(where: { $0.id == selectedCallDetail.id }) {
                loadCallDetail(selectedCall)
            } else if selectFirstIfNeeded, let firstCall = callBrowserCalls.first {
                loadCallDetail(firstCall)
            } else if callBrowserCalls.isEmpty {
                selectedCallDetail = nil
            }
        } catch {
            callBrowserError = error.localizedDescription
            appendLog("Calls browser failed: \(error.localizedDescription)")
        }
    }

    func retryCall(_ summary: StoredCallSummary) {
        guard !status.isBusy else {
            return
        }

        activeTask = Task { [weak self] in
            await self?.runRetry(for: summary)
        }
    }

    func selectCall(id: String?) {
        guard let id else {
            selectedCallDetail = nil
            webhooks.showCall(id: nil)
            return
        }

        do {
            callBrowserError = nil
            summaryError = nil
            summaryRecovery = nil
            if let call = callBrowserCalls.first(where: { $0.id == id }) {
                loadCallDetail(call)
                return
            }

            if let call = try callStore.fetchCall(id: id) {
                loadCallDetail(call)
            }
        } catch {
            callBrowserError = error.localizedDescription
            appendLog("Call detail failed: \(error.localizedDescription)")
        }
    }

    private func runDualRecording(
        maxDuration: TimeInterval,
        autoStopSilenceDuration: TimeInterval?,
        autoStartedApp: String? = nil
    ) async {
        defer { processingCallID = nil }
        let callID = Date.fileStamp
        let sessionDir = callsDirectory.appendingPathComponent(callID, isDirectory: true)
        let microphoneRawURL = sessionDir.appendingPathComponent("me.raw.wav")
        let systemRawURL = sessionDir.appendingPathComponent("them.raw.wav")
        let microphoneNormalizedURL = sessionDir.appendingPathComponent("me.asr.wav")
        let systemNormalizedURL = sessionDir.appendingPathComponent("them.asr.wav")
        let microphoneASRJSONURL = sessionDir.appendingPathComponent("me.asr.json")
        let systemASRJSONURL = sessionDir.appendingPathComponent("them.asr.json")
        let transcriptURL = sessionDir.appendingPathComponent("transcript.md")
        let startedAt = Date()

        do {
            lastError = nil
            lastTranscript = nil
            lastDualTranscript = nil
            cancelRequested = false
            try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            updateCallIndex {
                try persistCall(
                    id: callID,
                    kind: "dual",
                    startedAt: startedAt,
                    endedAt: nil,
                    durationSec: nil,
                    status: "recording",
                    transcriptURL: nil,
                    audioDirectoryURL: sessionDir,
                    error: nil,
                    appName: autoStartedApp
                )
            }

            if let autoStartedApp {
                status = .autoRecording(autoStartedApp)
                notifier.autoRecordingStarted(appName: autoStartedApp)
            } else if autoStopSilenceDuration != nil {
                status = .callRecording
            } else {
                status = .recording(maxDuration)
            }
            if let autoStopSilenceDuration {
                appendLog("Recording microphone and system audio to \(sessionDir.path); auto-stop after \(Int(autoStopSilenceDuration))s silence")
            } else {
                appendLog("Recording microphone and system audio to \(sessionDir.path)")
            }
            let capture = DualCapture()
            activeDualCapture = capture
            defer {
                activeDualCapture = nil
                stopLiveTicker()
                updater.recordingDidStop()
            }
            startLiveTicker()
            let captureOutput = try await capture.record(
                duration: maxDuration,
                sessionDirectory: sessionDir,
                autoStopSilenceDuration: autoStopSilenceDuration
            )
            stopLiveTicker()
            callDetector.recordingEnded()
            appendLog(
                "Recorded mic \(captureOutput.microphone.frameCount) frames, system \(captureOutput.system.frameCount) frames (\(captureOutput.stopReason.rawValue))"
            )
            if autoStartedApp != nil,
               cancelRequested || captureOutput.durationSec < Self.minimumAutoRecordingDuration {
                discardCall(id: callID, sessionDirectory: sessionDir, durationSec: captureOutput.durationSec)
                return
            }
            updateCallIndex {
                try persistCall(
                    id: callID,
                    kind: "dual",
                    startedAt: captureOutput.startedAt,
                    endedAt: captureOutput.endedAt,
                    durationSec: captureOutput.durationSec,
                    status: "normalizing",
                    transcriptURL: nil,
                    audioDirectoryURL: sessionDir,
                    error: nil
                )
            }

            processingCallID = callID
            beginStage("Подготовка записи", 1, of: 5)
            async let microphoneNormalized = AudioNormalizer.normalize(
                inputURL: microphoneRawURL,
                outputURL: microphoneNormalizedURL
            )
            async let systemNormalized = AudioNormalizer.normalize(
                inputURL: systemRawURL,
                outputURL: systemNormalizedURL
            )
            let normalizedURLs = try await (microphoneNormalized, systemNormalized)
            appendLog("Normalized dual audio")

            beginStage("Запуск распознавания", 2, of: 5)
            let ready = try await transcriber.start()
            workerDescription = "\(ready.model) \(ready.version)"
            appendLog("ASR ready: \(ready.model) \(ready.version)")

            beginStage("Расшифровка вашего голоса", 3, of: 5)
            updateCallIndex {
                try persistCall(
                    id: callID,
                    kind: "dual",
                    startedAt: captureOutput.startedAt,
                    endedAt: captureOutput.endedAt,
                    durationSec: captureOutput.durationSec,
                    status: "transcribing",
                    transcriptURL: nil,
                    audioDirectoryURL: sessionDir,
                    error: nil
                )
            }
            appendLog("Transcribing microphone")
            let microphoneTranscription = try await transcriber.transcribe(audioURL: normalizedURLs.0)
            try writeASRTranscription(microphoneTranscription, to: microphoneASRJSONURL)
            updateCallIndex {
                try callStore.upsertTranscriptJob(
                    id: microphoneTranscription.id,
                    callID: callID,
                    speaker: TranscriptChannel.microphone.speakerID,
                    status: "ready",
                    audioURL: normalizedURLs.0,
                    asrJSONURL: microphoneASRJSONURL,
                    audioDurationSec: microphoneTranscription.audioDurationSec,
                    wallTimeSec: microphoneTranscription.wallTimeSec,
                    realTimeFactor: microphoneTranscription.realTimeFactor,
                    model: settings.speechModelID,
                    error: nil
                )
            }
            appendLog("Transcribing system audio")
            beginStage("Расшифровка собеседников", 4, of: 5)
            let systemTranscription = try await transcriber.transcribe(audioURL: normalizedURLs.1)
            try writeASRTranscription(systemTranscription, to: systemASRJSONURL)
            updateCallIndex {
                try callStore.upsertTranscriptJob(
                    id: systemTranscription.id,
                    callID: callID,
                    speaker: TranscriptChannel.systemAudio.speakerID,
                    status: "ready",
                    audioURL: normalizedURLs.1,
                    asrJSONURL: systemASRJSONURL,
                    audioDurationSec: systemTranscription.audioDurationSec,
                    wallTimeSec: systemTranscription.wallTimeSec,
                    realTimeFactor: systemTranscription.realTimeFactor,
                    model: settings.speechModelID,
                    error: nil
                )
            }

            let remoteTurns = await diarizedTurns(
                audioURL: normalizedURLs.1,
                segments: systemTranscription.segments,
                step: 5,
                of: 5
            )

            let createdAt = Date()
            let microphoneResult = makeTranscriptResult(
                transcription: microphoneTranscription,
                createdAt: createdAt,
                sessionDirectory: sessionDir,
                rawAudioURL: microphoneRawURL,
                normalizedAudioURL: normalizedURLs.0,
                markdownURL: transcriptURL
            )
            let systemResult = makeTranscriptResult(
                transcription: systemTranscription,
                createdAt: createdAt,
                sessionDirectory: sessionDir,
                rawAudioURL: systemRawURL,
                normalizedAudioURL: normalizedURLs.1,
                markdownURL: transcriptURL
            )
            let dualResult = DualTranscriptResult(
                id: UUID().uuidString,
                createdAt: createdAt,
                sessionDirectory: sessionDir,
                markdownURL: transcriptURL,
                microphone: microphoneResult,
                systemAudio: systemResult,
                remoteTurns: remoteTurns
            )

            try TranscriptMerger.writeDualTranscript(dualResult, to: transcriptURL)
            updateCallIndex {
                try callStore.replaceSegments(callID: callID, segments: storedSegments(for: dualResult))
                try persistCall(
                    id: callID,
                    kind: "dual",
                    startedAt: captureOutput.startedAt,
                    endedAt: captureOutput.endedAt,
                    durationSec: captureOutput.durationSec,
                    status: "ready",
                    transcriptURL: transcriptURL,
                    audioDirectoryURL: sessionDir,
                    error: nil
                )
            }
            cleanupAudioIfNeeded(
                in: sessionDir,
                files: [
                    microphoneRawURL,
                    systemRawURL,
                    normalizedURLs.0,
                    normalizedURLs.1
                ]
            )
            lastDualTranscript = dualResult
            lastReadyCallID = callID
            status = .completed
            webhooks.enqueue(callID: callID)
            if settings.notifyWhenReady {
                notifier.transcriptReady(callDescription: autoStartedApp.map { "Звонок · \($0)" } ?? "Разговор записан")
            }
            appendLog("Wrote dual transcript to \(transcriptURL.path)")
        } catch {
            callDetector.recordingEnded()
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
            updateCallIndex {
                try persistCall(
                    id: callID,
                    kind: "dual",
                    startedAt: startedAt,
                    endedAt: Date(),
                    durationSec: Date().timeIntervalSince(startedAt),
                    status: "failed",
                    transcriptURL: nil,
                    audioDirectoryURL: sessionDir,
                    error: error.localizedDescription
                )
            }
            appendLog("Failed: \(error.localizedDescription)")
        }
    }

    private func runRetry(for summary: StoredCallSummary) async {
        defer { processingCallID = nil }
        processingCallID = summary.id
        let callID = summary.id
        let sessionDir = summary.audioDirectoryURL
        let transcriptURL = sessionDir.appendingPathComponent("transcript.md")
        let parsedStartedAt = parseISO8601(summary.startedAt) ?? Date()
        let parsedEndedAt = summary.endedAt.flatMap(parseISO8601)

        appendLog("Retrying call \(callID)")
        lastError = nil

        do {
            switch summary.kind {
            case "mic":
                let normalizedURL = sessionDir.appendingPathComponent("mic.16k-mono.wav")
                try requireFile(at: normalizedURL)
                let asrJSONURL = sessionDir.appendingPathComponent("mic.asr.json")
                let rawURL = sessionDir.appendingPathComponent("mic.raw.wav")

                updateCallIndex {
                    try persistCall(
                        id: callID,
                        kind: "mic",
                        startedAt: parsedStartedAt,
                        endedAt: parsedEndedAt,
                        durationSec: summary.durationSec,
                        status: "transcribing",
                        transcriptURL: nil,
                        audioDirectoryURL: sessionDir,
                        error: nil
                    )
                }

                beginStage("Запуск распознавания", 1, of: 2)
                let ready = try await transcriber.start()
                workerDescription = "\(ready.model) \(ready.version)"

                beginStage("Расшифровка записи", 2, of: 2)
                let transcription = try await transcriber.transcribe(audioURL: normalizedURL)
                try writeASRTranscription(transcription, to: asrJSONURL)
                updateCallIndex {
                    try callStore.upsertTranscriptJob(
                        id: transcription.id,
                        callID: callID,
                        speaker: TranscriptChannel.microphone.speakerID,
                        status: "ready",
                        audioURL: normalizedURL,
                        asrJSONURL: asrJSONURL,
                        audioDurationSec: transcription.audioDurationSec,
                        wallTimeSec: transcription.wallTimeSec,
                        realTimeFactor: transcription.realTimeFactor,
                        model: settings.speechModelID,
                        error: nil
                    )
                }

                let result = TranscriptResult(
                    id: transcription.id,
                    createdAt: Date(),
                    sessionDirectory: sessionDir,
                    rawAudioURL: rawURL,
                    normalizedAudioURL: normalizedURL,
                    markdownURL: transcriptURL,
                    text: transcription.text,
                    segments: transcription.segments,
                    audioDurationSec: transcription.audioDurationSec,
                    wallTimeSec: transcription.wallTimeSec,
                    realTimeFactor: transcription.realTimeFactor
                )
                try TranscriptMerger.writeMicrophoneTranscript(result, to: transcriptURL)
                updateCallIndex {
                    try callStore.replaceSegments(callID: callID, segments: storedSegments(for: result))
                    try persistCall(
                        id: callID,
                        kind: "mic",
                        startedAt: parsedStartedAt,
                        endedAt: parsedEndedAt,
                        durationSec: summary.durationSec,
                        status: "ready",
                        transcriptURL: transcriptURL,
                        audioDirectoryURL: sessionDir,
                        error: nil
                    )
                }
                cleanupAudioIfNeeded(in: sessionDir, files: [rawURL, normalizedURL])
                lastTranscript = result
                lastDualTranscript = nil
                status = .completed
                webhooks.enqueue(callID: callID)
                appendLog("Retry succeeded for \(callID)")

            case "dual":
                let micNormalized = sessionDir.appendingPathComponent("me.asr.wav")
                let systemNormalized = sessionDir.appendingPathComponent("them.asr.wav")
                try requireFile(at: micNormalized)
                try requireFile(at: systemNormalized)
                let micRaw = sessionDir.appendingPathComponent("me.raw.wav")
                let systemRaw = sessionDir.appendingPathComponent("them.raw.wav")
                let micASRJSON = sessionDir.appendingPathComponent("me.asr.json")
                let systemASRJSON = sessionDir.appendingPathComponent("them.asr.json")

                updateCallIndex {
                    try persistCall(
                        id: callID,
                        kind: "dual",
                        startedAt: parsedStartedAt,
                        endedAt: parsedEndedAt,
                        durationSec: summary.durationSec,
                        status: "transcribing",
                        transcriptURL: nil,
                        audioDirectoryURL: sessionDir,
                        error: nil
                    )
                }

                beginStage("Запуск распознавания", 1, of: 4)
                let ready = try await transcriber.start()
                workerDescription = "\(ready.model) \(ready.version)"

                beginStage("Расшифровка вашего голоса", 2, of: 4)
                let micTranscription = try await transcriber.transcribe(audioURL: micNormalized)
                try writeASRTranscription(micTranscription, to: micASRJSON)
                updateCallIndex {
                    try callStore.upsertTranscriptJob(
                        id: micTranscription.id,
                        callID: callID,
                        speaker: TranscriptChannel.microphone.speakerID,
                        status: "ready",
                        audioURL: micNormalized,
                        asrJSONURL: micASRJSON,
                        audioDurationSec: micTranscription.audioDurationSec,
                        wallTimeSec: micTranscription.wallTimeSec,
                        realTimeFactor: micTranscription.realTimeFactor,
                        model: settings.speechModelID,
                        error: nil
                    )
                }

                beginStage("Расшифровка собеседников", 3, of: 4)
                let systemTranscription = try await transcriber.transcribe(audioURL: systemNormalized)
                try writeASRTranscription(systemTranscription, to: systemASRJSON)
                updateCallIndex {
                    try callStore.upsertTranscriptJob(
                        id: systemTranscription.id,
                        callID: callID,
                        speaker: TranscriptChannel.systemAudio.speakerID,
                        status: "ready",
                        audioURL: systemNormalized,
                        asrJSONURL: systemASRJSON,
                        audioDurationSec: systemTranscription.audioDurationSec,
                        wallTimeSec: systemTranscription.wallTimeSec,
                        realTimeFactor: systemTranscription.realTimeFactor,
                        model: settings.speechModelID,
                        error: nil
                    )
                }

                let remoteTurns = await diarizedTurns(
                    audioURL: systemNormalized,
                    segments: systemTranscription.segments,
                    step: 4,
                    of: 4
                )

                let createdAt = Date()
                let micResult = makeTranscriptResult(
                    transcription: micTranscription,
                    createdAt: createdAt,
                    sessionDirectory: sessionDir,
                    rawAudioURL: micRaw,
                    normalizedAudioURL: micNormalized,
                    markdownURL: transcriptURL
                )
                let systemResult = makeTranscriptResult(
                    transcription: systemTranscription,
                    createdAt: createdAt,
                    sessionDirectory: sessionDir,
                    rawAudioURL: systemRaw,
                    normalizedAudioURL: systemNormalized,
                    markdownURL: transcriptURL
                )
                let dualResult = DualTranscriptResult(
                    id: UUID().uuidString,
                    createdAt: createdAt,
                    sessionDirectory: sessionDir,
                    markdownURL: transcriptURL,
                    microphone: micResult,
                    systemAudio: systemResult,
                    remoteTurns: remoteTurns
                )

                try TranscriptMerger.writeDualTranscript(dualResult, to: transcriptURL)
                updateCallIndex {
                    try callStore.replaceSegments(callID: callID, segments: storedSegments(for: dualResult))
                    try persistCall(
                        id: callID,
                        kind: "dual",
                        startedAt: parsedStartedAt,
                        endedAt: parsedEndedAt,
                        durationSec: summary.durationSec,
                        status: "ready",
                        transcriptURL: transcriptURL,
                        audioDirectoryURL: sessionDir,
                        error: nil
                    )
                }
                cleanupAudioIfNeeded(
                    in: sessionDir,
                    files: [micRaw, systemRaw, micNormalized, systemNormalized]
                )
                lastDualTranscript = dualResult
                lastTranscript = nil
                status = .completed
                webhooks.enqueue(callID: callID)
                appendLog("Retry succeeded for \(callID)")

            default:
                throw BesedaError.processFailed("Unsupported call kind: \(summary.kind)")
            }
        } catch {
            lastError = error.localizedDescription
            status = .failed(error.localizedDescription)
            updateCallIndex {
                try persistCall(
                    id: callID,
                    kind: summary.kind,
                    startedAt: parsedStartedAt,
                    endedAt: parsedEndedAt ?? Date(),
                    durationSec: summary.durationSec,
                    status: "failed",
                    transcriptURL: nil,
                    audioDirectoryURL: sessionDir,
                    error: error.localizedDescription
                )
            }
            appendLog("Retry failed: \(error.localizedDescription)")
        }
    }

    private func beginStage(_ title: String, _ index: Int, of total: Int) {
        status = .working(JobStage(title: title, index: index, total: total))
    }

    private func advanceStage(to fraction: Double) {
        guard case .working(var stage) = status else {
            return
        }
        stage.fraction = fraction
        status = .working(stage)
    }

    private func requireFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw BesedaError.processFailed("Missing audio file: \(url.lastPathComponent)")
        }
    }

    private func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// remote speaker turns for the system channel; empty keeps today's single `them` label
    private func diarizedTurns(
        audioURL: URL,
        segments: [TranscriptSegment],
        step: Int,
        of total: Int
    ) async -> [SpeakerTurn] {
        do {
            appendLog("Diarizing system audio")
            let started = Date()
            // the first run downloads and compiles the models: the longest wait of them all,
            // and the one that reports nothing, so at least it says its own name
            beginStage("Подготовка разбора голосов", step, of: total)
            try await diarizer.prepareModels()
            beginStage("Разбор голосов", step, of: total)
            let timeline = try await diarizer.timeline(for: audioURL) { [weak self] fraction in
                Task { @MainActor in
                    self?.advanceStage(to: fraction)
                }
            }
            let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)
            let elapsed = Int(Date().timeIntervalSince(started))
            appendLog("Diarized system audio in \(elapsed)s: \(Set(turns.map(\.speaker)).count) remote speakers")
            return turns
        } catch {
            appendLog("Diarization skipped: \(error.localizedDescription)")
            return []
        }
    }

    private func makeTranscriptResult(
        transcription: ASRTranscription,
        createdAt: Date,
        sessionDirectory: URL,
        rawAudioURL: URL,
        normalizedAudioURL: URL,
        markdownURL: URL
    ) -> TranscriptResult {
        TranscriptResult(
            id: transcription.id,
            createdAt: createdAt,
            sessionDirectory: sessionDirectory,
            rawAudioURL: rawAudioURL,
            normalizedAudioURL: normalizedAudioURL,
            markdownURL: markdownURL,
            text: transcription.text,
            segments: transcription.segments,
            audioDurationSec: transcription.audioDurationSec,
            wallTimeSec: transcription.wallTimeSec,
            realTimeFactor: transcription.realTimeFactor
        )
    }

    private func writeASRTranscription(_ transcription: ASRTranscription, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(transcription).write(to: url)
    }

    /// an empty name drops the rename and puts the speaker back to its default
    func renameSpeaker(_ speaker: String, to name: String) {
        guard let detail = selectedCallDetail else {
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try callStore.setSpeakerName(
                callID: detail.id,
                speakerKey: speaker,
                displayName: trimmed.isEmpty ? nil : trimmed
            )
            let names = try callStore.fetchSpeakerNames(callID: detail.id)
            if let transcriptURL = detail.summary.transcriptURL {
                try TranscriptMerger.rewriteDialogue(in: transcriptURL, segments: detail.segments, names: names)
            }
            loadCallDetail(detail.summary)
        } catch {
            callBrowserError = error.localizedDescription
            appendLog("Rename failed: \(error.localizedDescription)")
        }
    }

    /// «Заново» goes through here as well: the fresh text overwrites the old one, and a
    /// failed retry leaves the previous summary in place instead of an empty pane.
    func generateSummary() {
        guard let detail = selectedCallDetail, summarizingCallID == nil else {
            return
        }
        summaryError = nil
        summaryRecovery = nil
        summarizingCallID = detail.id
        summaryStartedAt = Date()
        Task { [weak self] in
            await self?.runSummary(for: detail)
        }
    }

    /// starts LM Studio when it stopped answering, then picks up the summary that failed on it
    func startLocalModelServer() {
        guard !isStartingLocalModelServer else {
            return
        }
        isStartingLocalModelServer = true
        Task { [weak self] in
            defer { self?.isStartingLocalModelServer = false }
            do {
                try await LocalModelSupport.startServer()
                self?.summaryError = nil
                self?.summaryRecovery = nil
                self?.generateSummary()
            } catch {
                self?.summaryError = error.localizedDescription
            }
        }
    }

    /// discovers the running server and lists its chat models, for the Server card in Settings
    func refreshSummaryModels() {
        Task { [weak self] in
            guard let self else {
                return
            }
            let serverURL = self.settings.summaryServerURL
            guard serverURL.isEmpty else {
                self.isServerDown = false
                guard let baseURL = URL(string: serverURL) else {
                    self.summaryServerStatus = "Адрес сервера не похож на URL"
                    self.summaryModels = []
                    return
                }
                self.summaryServerStatus = "Сервер: \(Self.hostAndPort(baseURL))"
                do {
                    self.summaryModels = try await LocalModelSupport.chatModels(at: baseURL)
                } catch {
                    self.summaryServerStatus = error.localizedDescription
                    self.summaryModels = []
                }
                return
            }
            do {
                guard let baseURL = try await LocalModelSupport.discoverServer() else {
                    self.isServerDown = true
                    self.summaryServerStatus = "LM Studio не запущен"
                    self.summaryModels = []
                    return
                }
                self.isServerDown = false
                self.summaryServerStatus = "LM Studio запущен на порту \(baseURL.port ?? 1234)"
                self.summaryModels = try await LocalModelSupport.chatModels(at: baseURL)
            } catch {
                self.isServerDown = false
                self.summaryServerStatus = error.localizedDescription
                self.summaryModels = []
            }
        }
    }

    private static func hostAndPort(_ url: URL) -> String {
        "\(url.host ?? "localhost"):\(url.port ?? 1234)"
    }

    /// sends a one-line prompt through the real provider so Settings can show the round trip works
    func checkSummaryConnection() {
        guard !isCheckingSummary else {
            return
        }
        isCheckingSummary = true
        summaryCheckResult = nil
        Task { [weak self] in
            guard let self else {
                return
            }
            defer { self.isCheckingSummary = false }
            let startedAt = Date()
            do {
                let connection = try await LocalModelSupport.resolve(
                    serverURL: self.settings.summaryServerURL,
                    model: self.settings.summaryModel
                )
                let provider = LocalModelProvider(
                    baseURL: connection.baseURL,
                    model: connection.model,
                    prompt: self.settings.summaryPrompt.isEmpty ? LocalModelProvider.defaultPrompt : self.settings.summaryPrompt
                )
                _ = try await provider.summarize(text: "Скажи «готово»")
                let elapsed = Date().timeIntervalSince(startedAt)
                self.summaryCheckResult = "Ответила за \(String(format: "%.1f", elapsed)) с"
            } catch {
                self.summaryCheckResult = error.localizedDescription
            }
        }
    }

    private func runSummary(for detail: StoredCallDetail) async {
        defer {
            summarizingCallID = nil
            summaryStartedAt = nil
        }
        do {
            let connection = try await LocalModelSupport.resolve(
                serverURL: settings.summaryServerURL,
                model: settings.summaryModel
            )
            let provider = LocalModelProvider(
                baseURL: connection.baseURL,
                model: connection.model,
                prompt: settings.summaryPrompt.isEmpty ? LocalModelProvider.defaultPrompt : settings.summaryPrompt
            )
            let text = try await SummarizationService(provider: provider).summarize(detail)
            try callStore.setSummary(callID: detail.id, text: text)
            // the summary lives on the call row, which loadCallDetail takes as given: re-read it
            // or the text is stored and never shown. The guard keeps a slow summary from
            // dragging the user back to the call they left.
            if selectedCallDetail?.id == detail.id, let fresh = try callStore.fetchCall(id: detail.id) {
                loadCallDetail(fresh)
            }
        } catch {
            appendLog("Summary failed: \(error.localizedDescription)")
            if selectedCallDetail?.id == detail.id {
                summaryError = error.localizedDescription
                summaryRecovery = Self.summaryRecovery(for: error)
            }
        }
    }

    /// an empty transcript has nothing to do with settings, so only «Повторить» stays for it;
    /// "server down" errors offer to start LM Studio when it is installed, everything else sends to Settings
    private static func summaryRecovery(for error: Error) -> SummaryRecovery? {
        guard let summarizationError = error as? SummarizationError else {
            return .openSettings
        }
        switch summarizationError {
        case .emptyTranscript:
            return nil
        case .unavailable(let message):
            let isServerDown = message.hasPrefix("LM Studio не запущен") || message.hasPrefix("LM Studio не отвечает на")
            return isServerDown && LocalModelSupport.isInstalled ? .startServer : .openSettings
        }
    }

    private func loadCallDetail(_ call: StoredCallSummary) {
        do {
            // switching calls used to stall; the number keeps a future slowdown from being a feeling
            let startedAt = Date()
            let segments = try callStore.fetchSegments(callID: call.id)
            let markdownText = try readMarkdownIfAvailable(for: call)
            let jobStats = try callStore.fetchJobStats(callID: call.id)
            appendLog("Loaded \(segments.count) lines of \(call.id) in \(Int(Date().timeIntervalSince(startedAt) * 1000)) ms")
            selectedCallDetail = StoredCallDetail(
                summary: call,
                segments: segments,
                speakerNames: try callStore.fetchSpeakerNames(callID: call.id),
                markdownText: markdownText,
                jobStats: jobStats
            )
            webhooks.showCall(id: call.id)
        } catch {
            callBrowserError = error.localizedDescription
            appendLog("Call detail failed: \(error.localizedDescription)")
        }
    }

    private func readMarkdownIfAvailable(for call: StoredCallSummary) throws -> String? {
        guard let transcriptURL = call.transcriptURL,
              fileManager.fileExists(atPath: transcriptURL.path) else {
            return nil
        }
        return try String(contentsOf: transcriptURL, encoding: .utf8)
    }

    private func storedSegments(for result: TranscriptResult) -> [StoredTranscriptSegment] {
        result.segments.enumerated().map { index, segment in
            StoredTranscriptSegment(
                speaker: TranscriptChannel.microphone.speakerID,
                startSec: segment.start,
                endSec: segment.end,
                text: segment.text,
                orderIndex: index
            )
        }
    }

    private func storedSegments(for result: DualTranscriptResult) -> [StoredTranscriptSegment] {
        result.speakerSegments.enumerated().map { index, item in
            StoredTranscriptSegment(
                speaker: item.speaker,
                startSec: item.segment.start,
                endSec: item.segment.end,
                text: item.segment.text,
                orderIndex: index
            )
        }
    }

    private func persistCall(
        id: String,
        kind: String,
        startedAt: Date,
        endedAt: Date?,
        durationSec: Double?,
        status: String,
        transcriptURL: URL?,
        audioDirectoryURL: URL,
        error: String?,
        appName: String? = nil
    ) throws {
        try callStore.upsertCall(
            id: id,
            kind: kind,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSec: durationSec,
            status: status,
            transcriptURL: transcriptURL,
            audioDirectoryURL: audioDirectoryURL,
            error: error,
            appName: appName
        )
    }

    private func discardCall(id: String, sessionDirectory: URL, durationSec: TimeInterval) {
        // the row is written when recording starts, so a discarded call has to be deleted, not skipped
        do {
            try callStore.deleteCall(id: id)
            try fileManager.removeItem(at: sessionDirectory)
            refreshRecentCalls()
            appendLog("Discarded \(Int(durationSec))s auto recording")
        } catch {
            appendLog("Discard failed: \(error.localizedDescription)")
        }
        status = .idle
    }

    /// removes only what the rules say goes immediately; anything with a deadline waits for the sweep
    private func cleanupAudioIfNeeded(in sessionDirectory: URL, files: [URL]) {
        let rules = settings.retentionRules
        for url in files {
            guard fileManager.fileExists(atPath: url.path),
                  let kind = StorageJanitor.kind(ofFileNamed: url.lastPathComponent),
                  StorageJanitor.isExpired(kind: kind, age: 0, rules: rules) else {
                continue
            }
            do {
                try fileManager.removeItem(at: url)
                appendLog("Removed audio \(url.lastPathComponent)")
            } catch {
                appendLog("Audio cleanup failed: \(url.lastPathComponent) — \(error.localizedDescription)")
            }
        }
        refreshStorageUsage()
    }

    private func updateCallIndex(_ operation: () throws -> Void) {
        do {
            try operation()
            refreshRecentCalls()
        } catch {
            appendLog("Call index failed: \(error.localizedDescription)")
        }
    }

    private func refreshTranscriptMatches() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            transcriptMatchIDs = nil
            return
        }
        transcriptMatchIDs = try? callStore.searchCallIDs(matching: query)
    }

    /// drives the recording clock and the two level meters while a capture is open
    private func startLiveTicker() {
        liveTicker?.invalidate()
        elapsedRecordingSeconds = 0
        let startedAt = Date()
        liveTicker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let capture = self.activeDualCapture else {
                    return
                }
                if !self.isPaused {
                    self.elapsedRecordingSeconds = Date().timeIntervalSince(startedAt)
                }
                self.microphoneLevel = capture.microphoneLevel
                self.systemAudioLevel = capture.systemAudioLevel
            }
        }
    }

    private func stopLiveTicker() {
        liveTicker?.invalidate()
        liveTicker = nil
        isPaused = false
        microphoneLevel = 0
        systemAudioLevel = 0
    }

    private func startDailySweep() {
        sweepExpiredAudio()
        dailySweep = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sweepExpiredAudio()
            }
        }
    }

    private func sweepExpiredAudio() {
        guard let protected = protectedAudioDirectories() else {
            appendLog("Daily cleanup skipped: the call index is unavailable")
            return
        }
        let freed = janitor.sweep(rules: settings.retentionRules, protecting: protected)
        if freed > 0 {
            appendLog("Daily cleanup freed \(freed.byteSizeDescription)")
        }
        refreshStorageUsage()
    }

    private func appendLog(_ message: String) {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return
        }
        logMessages.append("[\(Date.logStamp)] \(cleaned)")
        if logMessages.count > 80 {
            logMessages.removeFirst(logMessages.count - 80)
        }
        writeLogLine(cleaned)
    }

    private func writeLogLine(_ message: String) {
        do {
            try fileManager.createDirectory(
                at: AppPaths.current.appLogURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let line = "[\(Date().formatted(date: .numeric, time: .standard))] \(message)\n"
            if !fileManager.fileExists(atPath: AppPaths.current.appLogURL.path) {
                try line.write(to: AppPaths.current.appLogURL, atomically: true, encoding: .utf8)
                return
            }

            let handle = try FileHandle(forWritingTo: AppPaths.current.appLogURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            fputs("Beseda log write failed: \(error)\n", stderr)
        }
    }
}

private extension Date {
    static var fileStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    static var logStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
