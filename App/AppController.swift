import AppKit
import Foundation
import Observation

/// what the retry button in the summary error card should do about it
enum SummaryRecovery: Equatable {
    case startServer
    case downloadModel
    case openSettings
}

@MainActor
@Observable
final class AppController {
    enum Status: Equatable {
        case idle
        case recording
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
    var recentCalls: [StoredCallSummary] = []
    var callBrowserCalls: [StoredCallSummary] = []
    var selectedCallDetail: StoredCallDetail?
    /// looked up once per selection and per calendar refresh: each lookup scans the stored calls
    var previousCallForSelected: PreviousRelatedCall?
    var previousCallByEventID: [String: PreviousRelatedCall] = [:]
    var callBrowserError: String?
    /// asked to delete and waiting for the confirmation dialog
    var callPendingDeletion: StoredCallSummary?
    var deleteError: String?
    var elapsedRecordingSeconds: TimeInterval = 0
    var isPaused = false
    /// why the running or last recording lost audio: a failed write stops it, the popover says so
    var recordingWarning: String?
    /// the running recording's live preview, only while the setting is on
    var liveTranscription: LiveTranscription?
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
    @ObservationIgnored let bundledSummary: BundledSummaryInstaller
    @ObservationIgnored private let llamaServer = LlamaServer(paths: AppPaths.current)
    @ObservationIgnored let updater = AppUpdater()
    @ObservationIgnored private lazy var processingQueue = SerialQueue<(StoredCallDetail, CallType?)> { [unowned self] job in
        await self.runQueuedProcessing(of: job.0, as: job.1)
    }
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

    private static let maximumRecordingDuration: TimeInterval = 4 * 60 * 60
    /// an auto-started recording shorter than this is a misfire — a voice message or dictation, not a call
    private static let minimumAutoRecordingDuration: TimeInterval = 10

    /// ≈100k tokens at 3 chars/token, under the context of any model worth sending a call to
    private static let cloudCharacterBudget = 300_000
    /// half that: the built-in model is served with a 64k context and needs room for the answer
    private static let builtInCharacterBudget = 150_000
    /// a local model chews through a long call for minutes; the cloud answers in under one
    private static let localTimeout: TimeInterval = 900

    deinit {
        transcriber.stop()
    }

    /// called on the way out: the speech model must be freed before the process exits, and the
    /// summary server is a child process that would otherwise outlive the app
    func shutdown() {
        transcriber.shutdown()
        llamaServer.stop()
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
        let llamaServer = llamaServer
        bundledSummary = BundledSummaryInstaller(paths: AppPaths.current) {
            _ = try await llamaServer.ensureRunning()
            llamaServer.stop()
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
        bundledSummary.log = { [weak self] message in
            self?.appendLog(message)
        }
        llamaServer.log = { [weak self] message in
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

        StorageProtection.apply(to: AppPaths.current.dataDirectory)

        let freed = PythonRuntimeCleanup.run(AppPaths.current)
        if freed > 0 {
            appendLog("Removed the old Python engine, freed \(freed.byteSizeDescription)")
        }

        do {
            try callStore.prepare()
            let sweptDirectories = try callStore.failInterruptedCalls(reason: "Interrupted before the app restarted")
            if !sweptDirectories.isEmpty {
                appendLog("Marked \(sweptDirectories.count) interrupted call(s) as failed")
            }
            for directory in sweptDirectories {
                for name in [DualFiles.microphoneRaw, DualFiles.systemRaw] {
                    try? PCMFloatRecorder.repairWAVHeader(at: URL(fileURLWithPath: directory).appendingPathComponent(name))
                }
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

    func startCallRecording(autoStartedApp: String? = nil) {
        guard !status.isBusy else {
            return
        }

        let silenceStop: TimeInterval? = settings.stopOnSilence ? 60 : nil
        activeTask = Task { [weak self] in
            await self?.runDualRecording(
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
                await calendarService.requestAccess()
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
            try callStore.setEvent(callID: call.id, title: event?.title, eventID: event?.id, pinned: true,
                                   seriesID: event?.seriesID, participants: event?.participants ?? [])
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
        previousCallByEventID = upcomingEvents.prefix(5).reduce(into: [:]) { found, event in
            found[event.id] = try? callStore.previousRelatedCall(to: event)
        }
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
                try callStore.setEvent(callID: call.id, title: event.title, eventID: event.id, pinned: false,
                                       seriesID: event.seriesID, participants: event.participants)
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

    func quit() {
        transcriber.stop()
        NSApplication.shared.terminate(nil)
    }

    func openCallsFolder() {
        do {
            try fileManager.createDirectory(at: callsDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(callsDirectory)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func refreshRecentCalls() {
        do {
            recentCalls = try callStore.fetchCalls(limit: 10)
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

    private func runDualRecording(autoStopSilenceDuration: TimeInterval?, autoStartedApp: String?) async {
        defer { processingCallID = nil }
        let callID = Date.fileStamp
        let sessionDir = callsDirectory.appendingPathComponent(callID, isDirectory: true)
        let startedAt = Date()

        do {
            cancelRequested = false
            recordingWarning = nil
            try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            saveCall(callID, kind: "dual", in: sessionDir, startedAt: startedAt, status: "recording", appName: autoStartedApp)

            if let autoStartedApp {
                status = .autoRecording(autoStartedApp)
                notifier.autoRecordingStarted(appName: autoStartedApp)
            } else if autoStopSilenceDuration != nil {
                status = .callRecording
            } else {
                status = .recording
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
            if settings.transcribesDuringCall {
                startLiveTranscription(in: sessionDir, capture: capture)
            }
            let captureOutput: DualCaptureOutput
            do {
                captureOutput = try await capture.record(
                    duration: Self.maximumRecordingDuration,
                    sessionDirectory: sessionDir,
                    autoStopSilenceDuration: autoStopSilenceDuration
                )
            } catch {
                await stopLiveTranscription()
                throw error
            }
            // before normalization: the post-call pipeline must never share the transcriber with it
            await stopLiveTranscription()
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
            let persist = { [unowned self] (status: String, transcriptURL: URL?) in
                saveCall(
                    callID, kind: "dual", in: sessionDir,
                    startedAt: captureOutput.startedAt, endedAt: captureOutput.endedAt,
                    durationSec: captureOutput.durationSec, status: status, transcriptURL: transcriptURL
                )
            }
            persist("normalizing", nil)

            processingCallID = callID
            beginStage("Подготовка записи", 1, of: 5)
            async let microphoneNormalized = AudioNormalizer.normalize(
                inputURL: sessionDir.appendingPathComponent(DualFiles.microphoneRaw),
                outputURL: sessionDir.appendingPathComponent(DualFiles.microphoneASR)
            )
            async let systemNormalized = AudioNormalizer.normalize(
                inputURL: sessionDir.appendingPathComponent(DualFiles.systemRaw),
                outputURL: sessionDir.appendingPathComponent(DualFiles.systemASR)
            )
            _ = try await (microphoneNormalized, systemNormalized)
            appendLog("Normalized dual audio")

            try await transcribeDualCall(callID, in: sessionDir, stages: 5, persist: persist)
            lastReadyCallID = callID
            if settings.notifyWhenReady {
                notifier.transcriptReady(callDescription: autoStartedApp.map { "Звонок · \($0)" } ?? "Разговор записан")
            }
        } catch {
            callDetector.recordingEnded()
            status = .failed(error.localizedDescription)
            saveCall(
                callID, kind: "dual", in: sessionDir, startedAt: startedAt, endedAt: Date(),
                durationSec: Date().timeIntervalSince(startedAt), status: "failed", error: error.localizedDescription
            )
            appendLog("Failed: \(error.localizedDescription)")
        }
    }

    private func startLiveTranscription(in sessionDir: URL, capture: DualCapture) {
        let live = LiveTranscription(
            summarize: { [unowned self] text in
                defer { llamaServer.noteIdle() }
                var (provider, characterBudget) = try await makeSummaryProvider()
                provider.prompt = LiveTranscription.keyPointsPrompt
                return try await provider.summarize(text: String(text.suffix(characterBudget)))
            },
            log: { [weak self] in self?.appendLog($0) }
        )
        let transcriber = transcriber
        live.start(
            microphoneURL: sessionDir.appendingPathComponent(DualFiles.microphoneRaw),
            systemURL: sessionDir.appendingPathComponent(DualFiles.systemRaw),
            transcribe: { samples in
                try await transcriber.transcribe(samples: samples).segments.flatMap { $0.words ?? [] }
            },
            droppedBuffers: { capture.droppedBufferCount },
            isPaused: { capture.isPaused }
        )
        liveTranscription = live
        appendLog("Live transcription started")
    }

    private func stopLiveTranscription() async {
        guard let live = liveTranscription else {
            return
        }
        await live.stop()
        liveTranscription = nil
        appendLog("Live transcription stopped")
    }

    private func runRetry(for summary: StoredCallSummary) async {
        defer { processingCallID = nil }
        processingCallID = summary.id
        let callID = summary.id
        let sessionDir = summary.audioDirectoryURL
        let startedAt = summary.startedDate ?? Date()
        let endedAt = summary.endedAt.flatMap(CallFormatting.parseISO8601)
        let persist = { [unowned self] (status: String, transcriptURL: URL?) in
            saveCall(
                callID, kind: summary.kind, in: sessionDir, startedAt: startedAt, endedAt: endedAt,
                durationSec: summary.durationSec, status: status, transcriptURL: transcriptURL
            )
        }

        appendLog("Retrying call \(callID)")

        do {
            switch summary.kind {
            case "mic":
                let normalizedURL = sessionDir.appendingPathComponent("mic.16k-mono.wav")
                let rawURL = sessionDir.appendingPathComponent("mic.raw.wav")
                try requireFile(at: normalizedURL)
                try await startTranscriber(stage: 1, of: 2)
                persist("transcribing", nil)

                beginStage("Расшифровка записи", 2, of: 2)
                let result = try await transcribeChannel(
                    .microphone, callID, in: sessionDir,
                    audioURL: normalizedURL, rawAudioURL: rawURL,
                    asrJSONURL: sessionDir.appendingPathComponent("mic.asr.json")
                )
                let transcriptURL = sessionDir.appendingPathComponent(DualFiles.transcript)
                try TranscriptMerger.writeMicrophoneTranscript(result, to: transcriptURL)
                let segments = result.segments.map {
                    SpeakerTranscriptSegment(speaker: TranscriptChannel.microphone.speakerID, segment: $0)
                }
                finishCall(callID, in: sessionDir, segments: segments, audio: [rawURL, normalizedURL], persist: persist)

            case "dual":
                // a call cut off by a crash has only the raw files, streamed to disk while it recorded
                for (raw, asr) in [(DualFiles.microphoneRaw, DualFiles.microphoneASR), (DualFiles.systemRaw, DualFiles.systemASR)]
                where !fileManager.fileExists(atPath: sessionDir.appendingPathComponent(asr).path) {
                    _ = try await AudioNormalizer.normalize(
                        inputURL: sessionDir.appendingPathComponent(raw),
                        outputURL: sessionDir.appendingPathComponent(asr)
                    )
                }
                try await transcribeDualCall(callID, in: sessionDir, stages: 4, persist: persist)

            default:
                throw BesedaError.processFailed("Unsupported call kind: \(summary.kind)")
            }
            appendLog("Retry succeeded for \(callID)")
        } catch {
            status = .failed(error.localizedDescription)
            saveCall(
                callID, kind: summary.kind, in: sessionDir, startedAt: startedAt, endedAt: endedAt ?? Date(),
                durationSec: summary.durationSec, status: "failed", error: error.localizedDescription
            )
            appendLog("Retry failed: \(error.localizedDescription)")
        }
    }

    /// the file names inside a dual call's folder; the audio sweep and old calls rely on them
    private enum DualFiles {
        static let microphoneRaw = "me.raw.wav"
        static let systemRaw = "them.raw.wav"
        static let microphoneASR = "me.asr.wav"
        static let systemASR = "them.asr.wav"
        static let transcript = "transcript.md"
    }

    /// normalized me/them audio of a call: the last four stages of the pipeline, ASR start to diarization
    private func transcribeDualCall(
        _ callID: String,
        in sessionDir: URL,
        stages total: Int,
        persist: (_ status: String, _ transcriptURL: URL?) -> Void
    ) async throws {
        try await startTranscriber(stage: total - 3, of: total)
        persist("transcribing", nil)

        beginStage("Расшифровка вашего голоса", total - 2, of: total)
        appendLog("Transcribing microphone")
        let microphoneWithEcho = try await transcribeChannel(
            .microphone, callID, in: sessionDir,
            audioURL: sessionDir.appendingPathComponent(DualFiles.microphoneASR),
            rawAudioURL: sessionDir.appendingPathComponent(DualFiles.microphoneRaw),
            asrJSONURL: sessionDir.appendingPathComponent("me.asr.json")
        )
        beginStage("Расшифровка собеседников", total - 1, of: total)
        appendLog("Transcribing system audio")
        let systemAudio = try await transcribeChannel(
            .systemAudio, callID, in: sessionDir,
            audioURL: sessionDir.appendingPathComponent(DualFiles.systemASR),
            rawAudioURL: sessionDir.appendingPathComponent(DualFiles.systemRaw),
            asrJSONURL: sessionDir.appendingPathComponent("them.asr.json")
        )
        let microphone = try echoGated(microphoneWithEcho, system: systemAudio)
        let remoteTurns = await diarizedTurns(
            audioURL: systemAudio.normalizedAudioURL,
            segments: systemAudio.segments,
            step: total,
            of: total
        )

        let transcriptURL = sessionDir.appendingPathComponent(DualFiles.transcript)
        let dualResult = DualTranscriptResult(
            id: UUID().uuidString,
            createdAt: Date(),
            sessionDirectory: sessionDir,
            markdownURL: transcriptURL,
            microphone: microphone,
            systemAudio: systemAudio,
            remoteTurns: remoteTurns
        )
        try TranscriptMerger.writeDualTranscript(dualResult, to: transcriptURL)
        finishCall(
            callID, in: sessionDir, segments: dualResult.speakerSegments,
            audio: [microphone.rawAudioURL, systemAudio.rawAudioURL, microphone.normalizedAudioURL, systemAudio.normalizedAudioURL],
            persist: persist
        )
        appendLog("Wrote dual transcript to \(transcriptURL.path)")
    }

    /// the mic transcript without the remote side it picked up from the speakers; me.asr.json keeps it all
    private func echoGated(_ microphone: TranscriptResult, system: TranscriptResult) throws -> TranscriptResult {
        let segments = EchoGate.ownSpeechSegments(
            microphone.segments,
            mic: try LocalTranscriber.readSamples(at: microphone.normalizedAudioURL),
            system: try LocalTranscriber.readSamples(at: system.normalizedAudioURL)
        )
        appendLog("Echo gate kept \(segments.count) of \(microphone.segments.count) microphone sentences")
        return TranscriptResult(
            id: microphone.id,
            createdAt: microphone.createdAt,
            sessionDirectory: microphone.sessionDirectory,
            rawAudioURL: microphone.rawAudioURL,
            normalizedAudioURL: microphone.normalizedAudioURL,
            markdownURL: microphone.markdownURL,
            text: segments.map(\.text).joined(separator: " "),
            segments: segments,
            audioDurationSec: microphone.audioDurationSec,
            wallTimeSec: microphone.wallTimeSec,
            realTimeFactor: microphone.realTimeFactor
        )
    }

    private func startTranscriber(stage: Int, of total: Int) async throws {
        beginStage("Запуск распознавания", stage, of: total)
        let ready = try await transcriber.start()
        appendLog("ASR ready: \(ready.model) \(ready.version)")
    }

    /// one channel through ASR: its asr.json lands next to the audio and its job row in the index
    private func transcribeChannel(
        _ channel: TranscriptChannel,
        _ callID: String,
        in sessionDir: URL,
        audioURL: URL,
        rawAudioURL: URL,
        asrJSONURL: URL
    ) async throws -> TranscriptResult {
        let transcription = try await transcriber.transcribe(audioURL: audioURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(transcription).write(to: asrJSONURL)
        updateCallIndex {
            try callStore.upsertTranscriptJob(
                id: transcription.id,
                callID: callID,
                speaker: channel.speakerID,
                status: "ready",
                audioURL: audioURL,
                asrJSONURL: asrJSONURL,
                audioDurationSec: transcription.audioDurationSec,
                wallTimeSec: transcription.wallTimeSec,
                realTimeFactor: transcription.realTimeFactor,
                model: settings.speechModelID,
                error: nil
            )
        }
        return TranscriptResult(
            id: transcription.id,
            createdAt: Date(),
            sessionDirectory: sessionDir,
            rawAudioURL: rawAudioURL,
            normalizedAudioURL: audioURL,
            markdownURL: sessionDir.appendingPathComponent(DualFiles.transcript),
            text: transcription.text,
            segments: transcription.segments,
            audioDurationSec: transcription.audioDurationSec,
            wallTimeSec: transcription.wallTimeSec,
            realTimeFactor: transcription.realTimeFactor
        )
    }

    /// a written transcript: index its lines, mark the call ready, drop audio the rules say goes now
    private func finishCall(
        _ callID: String,
        in sessionDir: URL,
        segments: [SpeakerTranscriptSegment],
        audio: [URL],
        persist: (_ status: String, _ transcriptURL: URL?) -> Void
    ) {
        updateCallIndex {
            try callStore.replaceSegments(callID: callID, segments: segments.enumerated().map { index, line in
                StoredTranscriptSegment(
                    speaker: line.speaker,
                    startSec: line.segment.start,
                    endSec: line.segment.end,
                    text: line.segment.text,
                    orderIndex: index
                )
            })
        }
        persist("ready", sessionDir.appendingPathComponent(DualFiles.transcript))
        cleanupAudioIfNeeded(files: audio)
        status = .completed
        webhooks.enqueue(callID: callID)
        if settings.autoProcessCalls {
            do {
                if let call = try callStore.fetchCall(id: callID) {
                    startProcessing(try makeCallDetail(call), as: nil)
                }
            } catch {
                appendLog("Auto processing of \(callID) failed: \(error.localizedDescription)")
            }
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
    /// A given `type` skips the classifier — the call screen's type picker reruns through it.
    func generateSummary(as type: CallType? = nil) {
        guard let detail = selectedCallDetail else {
            return
        }
        startProcessing(detail, as: type)
    }

    /// a call that finishes while another is processed waits its turn instead of being dropped
    private func startProcessing(_ detail: StoredCallDetail, as type: CallType?) {
        if summarizingCallID != nil {
            appendLog("Processing of \(detail.id) queued: another call is being processed")
        }
        processingQueue.enqueue((detail, type))
    }

    private func runQueuedProcessing(of detail: StoredCallDetail, as type: CallType?) async {
        summaryError = nil
        summaryRecovery = nil
        summarizingCallID = detail.id
        summaryStartedAt = Date()
        await runSummary(for: detail, as: type)
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
            guard self.settings.summaryProvider == .lmStudio else {
                self.isServerDown = false
                self.summaryServerStatus = nil
                self.summaryModels = []
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
            defer { self.llamaServer.noteIdle() }
            let startedAt = Date()
            do {
                let provider = try await self.makeSummaryProvider().provider
                _ = try await provider.summarize(text: "Скажи «готово»")
                let elapsed = Date().timeIntervalSince(startedAt)
                self.summaryCheckResult = "Ответила за \(String(format: "%.1f", elapsed)) с"
            } catch {
                self.summaryCheckResult = error.localizedDescription
            }
        }
    }

    private func runSummary(for detail: StoredCallDetail, as chosenType: CallType?) async {
        defer {
            summarizingCallID = nil
            summaryStartedAt = nil
        }
        defer { llamaServer.noteIdle() }
        do {
            let (provider, characterBudget) = try await makeSummaryProvider()
            let (type, text) = try await SummarizationService.process(
                detail,
                types: settings.callTypes,
                chosen: chosenType,
                characterBudget: characterBudget,
                provider: { prompt in
                    var typed = provider
                    typed.prompt = prompt
                    return typed
                },
                jev: settings.classifiesWithJev ? JevClassifier(apiKey: settings.openRouterAPIKey) : nil,
                log: { [weak self] in self?.appendLog($0) }
            )
            appendLog("Processed \(detail.id) as «\(type.name)»")
            try callStore.setSummary(callID: detail.id, text: text)
            try callStore.setCallType(callID: detail.id, name: type.name)
            exportResult(detail, result: text, type: type.name)
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
                summaryRecovery = Self.recovery(
                    for: error,
                    provider: settings.summaryProvider,
                    isLMStudioInstalled: LocalModelSupport.isInstalled
                )
            }
        }
    }

    /// a failed write is only logged: the result is already stored and shown
    private func exportResult(_ detail: StoredCallDetail, result: String, type: String) {
        guard !settings.exportFolder.isEmpty else {
            return
        }
        do {
            let url = try CallExport.write(detail, result: result, type: type, to: URL(fileURLWithPath: settings.exportFolder))
            appendLog("Exported \(detail.id) to \(url.path)")
        } catch {
            appendLog("Export failed: \(error.localizedDescription)")
        }
    }

    func copyResult() {
        guard let text = selectedCallDetail?.summary.summaryText, !text.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash("Результат скопирован")
    }

    /// an empty transcript has nothing to do with settings, so only «Повторить» stays for it;
    /// a silent LM Studio offers to start it, a missing model offers to download it,
    /// everything else sends to Settings
    nonisolated static func recovery(for error: Error, provider: SummaryProvider, isLMStudioInstalled: Bool) -> SummaryRecovery? {
        guard let summarizationError = error as? SummarizationError else {
            return .openSettings
        }
        switch summarizationError {
        case .emptyTranscript:
            return nil
        case .modelMissing:
            return .downloadModel
        case .serverDown:
            let canStart = provider == .lmStudio && isLMStudioInstalled
            return canStart ? .startServer : .openSettings
        case .unauthorized, .unavailable:
            return .openSettings
        }
    }

    /// The provider the settings point at, and how much transcript it can be given: the built-in
    /// model has a 64k context, the other two take the whole call.
    private func makeSummaryProvider() async throws -> (provider: ChatCompletionsProvider, characterBudget: Int) {
        let prompt = settings.callTypes[0].prompt
        switch settings.summaryProvider {
        case .openRouter:
            guard !settings.openRouterAPIKey.isEmpty else {
                throw SummarizationError.unauthorized("Ключ OpenRouter не введён")
            }
            let provider = ChatCompletionsProvider(
                baseURL: OpenRouter.baseURL,
                model: settings.openRouterModel.isEmpty ? OpenRouter.defaultModel : settings.openRouterModel,
                prompt: prompt,
                apiKey: settings.openRouterAPIKey,
                serviceName: "OpenRouter"
            )
            return (provider, Self.cloudCharacterBudget)
        case .builtIn:
            let baseURL = try await llamaServer.ensureRunning()
            let provider = ChatCompletionsProvider(
                baseURL: baseURL,
                model: BundledSummary.current.modelID,
                prompt: prompt,
                serviceName: "Встроенная модель",
                timeout: Self.localTimeout
            )
            return (provider, Self.builtInCharacterBudget)
        case .lmStudio:
            let connection = try await LocalModelSupport.resolve(
                serverURL: settings.summaryServerURL,
                model: settings.summaryModel
            )
            let provider = ChatCompletionsProvider(
                baseURL: connection.baseURL,
                model: connection.model,
                prompt: prompt,
                serviceName: "LM Studio на \(Self.hostAndPort(connection.baseURL))",
                timeout: Self.localTimeout
            )
            return (provider, Self.cloudCharacterBudget)
        }
    }

    private func loadCallDetail(_ call: StoredCallSummary) {
        do {
            // switching calls used to stall; the number keeps a future slowdown from being a feeling
            let startedAt = Date()
            let detail = try makeCallDetail(call)
            appendLog("Loaded \(detail.segments.count) lines of \(call.id) in \(Int(Date().timeIntervalSince(startedAt) * 1000)) ms")
            selectedCallDetail = detail
            previousCallForSelected = try? callStore.previousRelatedCall(toCallID: call.id)
            webhooks.showCall(id: call.id)
        } catch {
            callBrowserError = error.localizedDescription
            appendLog("Call detail failed: \(error.localizedDescription)")
        }
    }

    private func makeCallDetail(_ call: StoredCallSummary) throws -> StoredCallDetail {
        StoredCallDetail(
            summary: call,
            segments: try callStore.fetchSegments(callID: call.id),
            speakerNames: try callStore.fetchSpeakerNames(callID: call.id),
            markdownText: try readMarkdownIfAvailable(for: call),
            jobStats: try callStore.fetchJobStats(callID: call.id)
        )
    }

    private func readMarkdownIfAvailable(for call: StoredCallSummary) throws -> String? {
        guard let transcriptURL = call.transcriptURL,
              fileManager.fileExists(atPath: transcriptURL.path) else {
            return nil
        }
        return try String(contentsOf: transcriptURL, encoding: .utf8)
    }

    private func saveCall(
        _ id: String,
        kind: String,
        in sessionDir: URL,
        startedAt: Date,
        endedAt: Date? = nil,
        durationSec: Double? = nil,
        status: String,
        transcriptURL: URL? = nil,
        error: String? = nil,
        appName: String? = nil
    ) {
        updateCallIndex {
            try callStore.upsertCall(
                id: id,
                kind: kind,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSec: durationSec,
                status: status,
                transcriptURL: transcriptURL,
                audioDirectoryURL: sessionDir,
                error: error,
                appName: appName
            )
        }
    }

    func canDelete(_ call: StoredCallSummary) -> Bool {
        !["recording", "normalizing", "transcribing"].contains(call.status) && processingCallID != call.id
            && summarizingCallID != call.id
    }

    /// the call with every file it left, its export copy included
    func deleteCall(_ call: StoredCallSummary) {
        guard canDelete(call) else {
            return
        }
        do {
            let exportFolder = settings.exportFolder.isEmpty ? nil : URL(fileURLWithPath: settings.exportFolder)
            try callStore.deleteCallAndFiles(id: call.id, exportFolder: exportFolder)
            if selectedCallDetail?.id == call.id {
                selectCall(id: nil)
            }
            refreshRecentCalls()
            refreshCallBrowser()
            appendLog("Deleted call \(call.id)")
        } catch {
            appendLog("Delete failed: \(error.localizedDescription)")
            deleteError = error.localizedDescription
        }
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
    private func cleanupAudioIfNeeded(files: [URL]) {
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
                if self.recordingWarning == nil, let writeError = capture.writeError {
                    self.stopRecording(after: writeError, capture: capture)
                }
            }
        }
    }

    /// a failed write (disk full, the 4 GB WAV limit) keeps what reached the disk and ends the call there
    private func stopRecording(after writeError: String, capture: DualCapture) {
        recordingWarning = Self.recordingWarning(forWriteError: writeError)
        appendLog("Recording write failed: \(writeError)")
        notifier.recordingStopped(reason: recordingWarning ?? writeError)
        capture.stop(reason: .writeFailed)
    }

    nonisolated static func recordingWarning(forWriteError writeError: String) -> String {
        writeError.contains("4 GB")
            ? "Запись остановлена: файл дошёл до предела в 4 ГБ (около 3 часов). Сохранённое будет расшифровано."
            : "Запись остановлена: не удалось записать звук на диск (\(writeError)). Сохранённое будет расшифровано."
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
}
