import Foundation
import Observation

/// How long a kind of audio file survives before the daily sweep removes it.
enum RetentionRule: String, CaseIterable, Identifiable, Sendable {
    case immediately
    case days30
    case days90
    case forever

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .immediately:
            SettingsText.get("Сразу")
        case .days30:
            SettingsText.get("30 дней")
        case .days90:
            SettingsText.get("90 дней")
        case .forever:
            SettingsText.get("Всегда")
        }
    }

    /// nil means the file is never swept; zero means it goes as soon as the transcript is written
    var maximumAge: TimeInterval? {
        switch self {
        case .immediately:
            0
        case .days30:
            30 * 24 * 60 * 60
        case .days90:
            90 * 24 * 60 * 60
        case .forever:
            nil
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private let keychain: Keychain
    /// the background Keychain read started by `init`; tests await it
    @ObservationIgnored private(set) var secretsLoad: Task<Void, Never>?
    @ObservationIgnored private var isLoadingSecrets = false
    /// false until the Keychain read returns; the settings key fields say «Загрузка…» meanwhile
    private(set) var secretsLoaded = false
    private let autoDetectKey = "beseda.autoDetectEnabled"
    private let enabledCallAppsKey = "beseda.enabledCallApps"
    private let rawRetentionKey = "beseda.rawAudioRetention"
    private let normalizedRetentionKey = "beseda.normalizedAudioRetention"
    private let stopOnSilenceKey = "beseda.stopOnSilence"
    private let notifyWhenReadyKey = "beseda.notifyWhenReady"
    private let transcribesDuringCallKey = "beseda.transcribesDuringCall"
    private let onboardingDoneKey = "beseda.onboardingDone"
    private let copyFormatKey = "beseda.copyFormat"
    private let calendarEnabledKey = "beseda.calendarEnabled"
    private let calendarIdentifiersKey = "beseda.calendarIdentifiers"
    private let summaryProviderKey = "beseda.summaryProvider"
    private let openRouterAPIKeyKey = "beseda.openRouterAPIKey"
    private let openRouterModelKey = "beseda.openRouterModel"
    private let summaryServerURLKey = "beseda.summaryServerURL"
    private let summaryModelKey = "beseda.summaryModel"
    /// only read, to carry an edited summary prompt into the first call type
    private let legacySummaryPromptKey = "beseda.summaryPrompt"
    private let callTypesKey = "beseda.callTypes"
    private let classifyLocallyKey = "beseda.classifyLocally"
    private let localOnlyKey = "beseda.localOnly"
    private let autoProcessCallsKey = "beseda.autoProcessCalls"
    private let exportFolderKey = "beseda.exportFolder"
    private let exportBookmarkKey = "beseda.exportBookmark"
    private let webhookEnabledKey = "beseda.webhookEnabled"
    private let webhookURLKey = "beseda.webhookURL"
    private let webhookSecretKey = "beseda.webhookSecret"
    private let speechModelKey = "beseda.speechModel"
    private let excludesFromBackupKey = "beseda.excludesFromBackup"
    private let strictModeKey = "beseda.strictMode"
    private let strictModeConfirmedKey = "beseda.strictModeConfirmed"
    private let valuesBeforeStrictModeKey = "beseda.valuesBeforeStrictMode"

    var autoDetectEnabled: Bool {
        didSet {
            defaults.set(autoDetectEnabled, forKey: autoDetectKey)
        }
    }

    var enabledCallApps: Set<String> {
        didSet {
            defaults.set(Array(enabledCallApps), forKey: enabledCallAppsKey)
        }
    }

    var rawAudioRetention: RetentionRule {
        didSet {
            defaults.set(rawAudioRetention.rawValue, forKey: rawRetentionKey)
        }
    }

    var normalizedAudioRetention: RetentionRule {
        didSet {
            defaults.set(normalizedAudioRetention.rawValue, forKey: normalizedRetentionKey)
        }
    }

    var stopOnSilence: Bool {
        didSet {
            defaults.set(stopOnSilence, forKey: stopOnSilenceKey)
        }
    }

    /// the live preview in the menu bar while recording; the post-call transcript is still the result
    var transcribesDuringCall: Bool {
        didSet {
            defaults.set(transcribesDuringCall, forKey: transcribesDuringCallKey)
        }
    }

    var notifyWhenReady: Bool {
        didSet {
            defaults.set(notifyWhenReady, forKey: notifyWhenReadyKey)
        }
    }

    var onboardingDone: Bool {
        didSet {
            defaults.set(onboardingDone, forKey: onboardingDoneKey)
        }
    }

    var copyFormat: TranscriptCopyFormat {
        didSet {
            defaults.set(copyFormat.rawValue, forKey: copyFormatKey)
        }
    }

    var calendarEnabled: Bool {
        didSet {
            defaults.set(calendarEnabled, forKey: calendarEnabledKey)
        }
    }

    /// which calendars to read; empty means every calendar the Mac knows about
    var calendarIdentifiers: Set<String> {
        didSet {
            defaults.set(Array(calendarIdentifiers), forKey: calendarIdentifiersKey)
        }
    }

    var summaryProvider: SummaryProvider {
        didSet {
            defaults.set(summaryProvider.rawValue, forKey: summaryProviderKey)
        }
    }

    var openRouterAPIKey: String {
        didSet {
            storeSecret(openRouterAPIKey, key: openRouterAPIKeyKey)
        }
    }

    /// "" means `OpenRouter.defaultModel`
    var openRouterModel: String {
        didSet {
            defaults.set(openRouterModel, forKey: openRouterModelKey)
        }
    }

    /// "" means automatic: discover the running LM Studio server via `lms`
    var summaryServerURL: String {
        didSet {
            defaults.set(summaryServerURL, forKey: summaryServerURLKey)
        }
    }

    /// "" means automatic: the first chat model LM Studio reports
    var summaryModel: String {
        didSet {
            defaults.set(summaryModel, forKey: summaryModelKey)
        }
    }

    /// never empty, exactly one `isOther`: the classifier runs only when there are two or more
    var callTypes: [CallType] {
        didSet {
            defaults.set(try? JSONEncoder().encode(callTypes), forKey: callTypesKey)
        }
    }

    /// off: Jev classifies whenever an OpenRouter key is set (Mikhail's default, 2026-09-26)
    var classifyLocally: Bool {
        didSet {
            defaults.set(classifyLocally, forKey: classifyLocallyKey)
        }
    }

    /// «Другое» stays whatever is asked
    func deleteCallType(id: CallType.ID) {
        guard id != callTypes.other.id else {
            return
        }
        callTypes.removeAll { $0.id == id }
    }

    /// «Только локально»: nothing leaves the Mac whatever else is set; off by default (Mikhail, 2026-09-26)
    var localOnly: Bool {
        didSet {
            defaults.set(localOnly, forKey: localOnlyKey)
        }
    }

    var classifiesWithJev: Bool {
        !localOnly && !classifyLocally && !openRouterAPIKey.isEmpty
    }

    /// the provider that actually writes summaries and live key points: under `localOnly` one that
    /// would send the text off the Mac is replaced by the built-in model
    var effectiveSummaryProvider: SummaryProvider {
        guard localOnly, summaryProvider == .openRouter || remoteSummaryHost != nil else {
            return summaryProvider
        }
        return .builtIn
    }

    /// the LM Studio server's host when it is set by hand to another machine
    var remoteSummaryHost: String? {
        guard summaryProvider == .lmStudio,
              let host = URL(string: summaryServerURL)?.host,
              !["localhost", "127.0.0.1", "::1"].contains(host) else {
            return nil
        }
        return host
    }

    var sendsWebhooks: Bool {
        webhookEnabled && !localOnly
    }

    /// off: a call is processed only from «Итоги»
    var autoProcessCalls: Bool {
        didSet {
            defaults.set(autoProcessCalls, forKey: autoProcessCallsKey)
        }
    }

    var webhookEnabled: Bool {
        didSet {
            defaults.set(webhookEnabled, forKey: webhookEnabledKey)
        }
    }

    var exportFolder: String {
        didSet {
            defaults.set(exportFolder, forKey: exportFolderKey)
            if exportFolder.isEmpty { defaults.removeObject(forKey: exportBookmarkKey) }
        }
    }

    var exportNeedsReselection = false

    var sandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    func selectExportFolder(_ url: URL) throws {
        if sandboxed {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: exportBookmarkKey)
        }
        exportFolder = url.path
        exportNeedsReselection = false
    }

    func withExportFolder<T>(_ body: (URL) throws -> T) throws -> T {
        if !sandboxed { return try body(URL(fileURLWithPath: exportFolder)) }
        guard let bookmark = defaults.data(forKey: exportBookmarkKey) else {
            exportNeedsReselection = true
            throw ExportAccessError.reselect
        }
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            exportNeedsReselection = true
            throw ExportAccessError.reselect
        }
        guard url.startAccessingSecurityScopedResource() else {
            exportNeedsReselection = true
            throw ExportAccessError.reselect
        }
        defer { url.stopAccessingSecurityScopedResource() }
        if stale {
            if let renewed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(renewed, forKey: exportBookmarkKey)
            } else {
                exportNeedsReselection = true
            }
        }
        return try body(url)
    }

    enum ExportAccessError: LocalizedError {
        case reselect
        var errorDescription: String? { "Select the export folder again in Settings / Выберите папку экспорта снова в настройках" }
    }

    var webhookURL: String {
        didSet {
            defaults.set(webhookURL, forKey: webhookURLKey)
        }
    }

    var webhookSecret: String {
        didSet {
            storeSecret(webhookSecret, key: webhookSecretKey)
        }
    }

    /// the id of a `SpeechModel`; an unknown value falls back to the default on read
    var speechModelID: String {
        didSet {
            defaults.set(speechModelID, forKey: speechModelKey)
        }
    }

    /// opt-in (Mikhail keeps his backups, 2026-09-27); the app applies it to the data folder
    var excludesFromBackup: Bool {
        didSet {
            defaults.set(excludesFromBackup, forKey: excludesFromBackupKey)
        }
    }

    /// «Строгий режим»: audio goes right after transcription, no export, local only, no backups
    private(set) var strictMode: Bool

    /// the audio-deletion confirmation is shown only the first time strict mode goes on
    var strictModeConfirmed: Bool {
        didSet {
            defaults.set(strictModeConfirmed, forKey: strictModeConfirmedKey)
        }
    }

    /// saves what strict mode overrides so turning it off puts every value back
    func setStrictMode(_ on: Bool) {
        guard on != strictMode else { return }
        if on {
            defaults.set([
                rawRetentionKey: rawAudioRetention.rawValue,
                normalizedRetentionKey: normalizedAudioRetention.rawValue,
                exportFolderKey: exportFolder,
                exportBookmarkKey: defaults.data(forKey: exportBookmarkKey) ?? Data(),
                localOnlyKey: localOnly,
                excludesFromBackupKey: excludesFromBackup
            ] as [String: Any], forKey: valuesBeforeStrictModeKey)
            rawAudioRetention = .immediately
            normalizedAudioRetention = .immediately
            exportFolder = ""
            localOnly = true
            excludesFromBackup = true
        } else if let saved = defaults.dictionary(forKey: valuesBeforeStrictModeKey) {
            rawAudioRetention = (saved[rawRetentionKey] as? String).flatMap(RetentionRule.init(rawValue:)) ?? .days90
            normalizedAudioRetention = (saved[normalizedRetentionKey] as? String).flatMap(RetentionRule.init(rawValue:)) ?? .days30
            exportFolder = saved[exportFolderKey] as? String ?? ""
            if let bookmark = saved[exportBookmarkKey] as? Data, !bookmark.isEmpty {
                defaults.set(bookmark, forKey: exportBookmarkKey)
            }
            localOnly = saved[localOnlyKey] as? Bool ?? false
            excludesFromBackup = saved[excludesFromBackupKey] as? Bool ?? false
            defaults.removeObject(forKey: valuesBeforeStrictModeKey)
        }
        strictMode = on
        defaults.set(on, forKey: strictModeKey)
    }

    var speechModel: SpeechModel {
        SpeechModel.named(speechModelID) ?? .default
    }

    init(defaults: UserDefaults = .standard, keychain: Keychain = .app) {
        if defaults === UserDefaults.standard,
           ProcessInfo.processInfo.environment["IOS_KIT_CLEAN_DEFAULTS"] == nil,
           let legacy = UserDefaults(suiteName: "app.podushka.Podushka") {
            AppSettings.importLegacyValues(from: legacy, into: defaults)
        }
        self.defaults = defaults
        self.keychain = keychain
        self.autoDetectEnabled = AppSettings.bool(defaults, autoDetectKey, otherwise: false)
        self.enabledCallApps = (defaults.array(forKey: enabledCallAppsKey) as? [String])
            .map(Set.init) ?? AppSettings.defaultEnabledCallApps
        self.rawAudioRetention = defaults.string(forKey: rawRetentionKey)
            .flatMap(RetentionRule.init(rawValue:)) ?? .days90
        self.normalizedAudioRetention = defaults.string(forKey: normalizedRetentionKey)
            .flatMap(RetentionRule.init(rawValue:)) ?? .days30
        self.stopOnSilence = AppSettings.bool(defaults, stopOnSilenceKey, otherwise: true)
        self.notifyWhenReady = AppSettings.bool(defaults, notifyWhenReadyKey, otherwise: true)
        self.transcribesDuringCall = defaults.bool(forKey: transcribesDuringCallKey)
        self.onboardingDone = defaults.bool(forKey: onboardingDoneKey)
        self.copyFormat = defaults.string(forKey: copyFormatKey)
            .flatMap(TranscriptCopyFormat.init(rawValue:)) ?? .timestamped
        self.calendarEnabled = defaults.bool(forKey: calendarEnabledKey)
        self.calendarIdentifiers = (defaults.array(forKey: calendarIdentifiersKey) as? [String])
            .map(Set.init) ?? []
        self.summaryProvider = defaults.string(forKey: summaryProviderKey)
            .flatMap(SummaryProvider.init(rawValue:)) ?? .builtIn
        self.openRouterAPIKey = defaults.string(forKey: openRouterAPIKeyKey) ?? ""
        self.openRouterModel = defaults.string(forKey: openRouterModelKey) ?? ""
        self.summaryServerURL = defaults.string(forKey: summaryServerURLKey) ?? ""
        self.summaryModel = defaults.string(forKey: summaryModelKey) ?? ""
        self.callTypes = defaults.data(forKey: callTypesKey)
            .flatMap { try? JSONDecoder().decode([CallType].self, from: $0) }
            .flatMap { $0.isEmpty ? nil : AppSettings.migratingStoredCallTypes($0) }
            ?? [AppSettings.defaultCallType(legacyPrompt: defaults.string(forKey: legacySummaryPromptKey))]
        self.classifyLocally = defaults.bool(forKey: classifyLocallyKey)
        self.localOnly = defaults.bool(forKey: localOnlyKey)
        self.autoProcessCalls = defaults.bool(forKey: autoProcessCallsKey)
        self.webhookEnabled = defaults.bool(forKey: webhookEnabledKey)
        self.exportFolder = defaults.string(forKey: exportFolderKey) ?? ""
        self.webhookURL = defaults.string(forKey: webhookURLKey) ?? ""
        self.webhookSecret = defaults.string(forKey: webhookSecretKey) ?? ""
        self.speechModelID = defaults.string(forKey: speechModelKey) ?? SpeechModel.default.id
        self.excludesFromBackup = defaults.bool(forKey: excludesFromBackupKey)
        self.strictMode = defaults.bool(forKey: strictModeKey)
        self.strictModeConfirmed = defaults.bool(forKey: strictModeConfirmedKey)
        secretsLoad = Task { await loadSecrets() }
    }

    /// the secrets load off the main thread: reading an item another signature wrote makes macOS ask,
    /// and a prompt left open must not hold up the menu bar and windows. Until it returns the keys read "".
    /// A secret still in UserDefaults (a release before the Keychain, or a failed write) moves to the
    /// Keychain here; if the Keychain refuses, it stays in defaults and keeps working from there
    private func loadSecrets() async {
        let keychain = keychain
        for key in [openRouterAPIKeyKey, webhookSecretKey] {
            let stored = defaults.string(forKey: key)
            let loaded = await Task.detached {
                guard let stored else {
                    return keychain.read(account: key)
                }
                return keychain.save(stored, account: key) ? stored : nil
            }.value
            if stored != nil {
                if loaded != nil, defaults.string(forKey: key) == stored {
                    defaults.removeObject(forKey: key)
                }
                continue
            }
            // a key typed while the read was waiting wins over the stored one
            guard let loaded else { continue }
            isLoadingSecrets = true
            if key == openRouterAPIKeyKey, openRouterAPIKey.isEmpty {
                openRouterAPIKey = loaded
            } else if key == webhookSecretKey, webhookSecret.isEmpty {
                webhookSecret = loaded
            }
            isLoadingSecrets = false
        }
        secretsLoaded = true
    }

    private func storeSecret(_ value: String, key: String) {
        guard !isLoadingSecrets else { return }
        if keychain.save(value, account: key) {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(value, forKey: key)
        }
    }

    /// the settings written while the app was called Podushka; a value already set under
    /// the new name wins, so this runs at most once per key
    static func importLegacyValues(from legacy: UserDefaults, into defaults: UserDefaults) {
        for (key, value) in legacy.dictionaryRepresentation() where key.hasPrefix("podushka.") {
            let newKey = "beseda." + key.dropFirst("podushka.".count)
            if defaults.object(forKey: newKey) == nil {
                defaults.set(value, forKey: newKey)
            }
        }
    }

    static func defaultCallType(legacyPrompt: String?) -> CallType {
        let prompt = legacyPrompt.flatMap { $0.isEmpty ? nil : $0 } ?? ChatCompletionsProvider.defaultPrompt
        return CallType(name: CallType.otherName, description: "ни один другой тип не подходит", prompt: prompt, isOther: true)
    }

    /// Types stored before `isOther` meant «Другое» by position: the first one gets the flag.
    /// BESEDA-46 seeded one type named «Созвон»; unrenamed, it becomes «Другое» with its prompt kept.
    /// A prompt still equal to the previous default gets the current one; an edited prompt stays.
    static func migratingStoredCallTypes(_ types: [CallType]) -> [CallType] {
        var types = types
        for index in types.indices where types[index].prompt == ChatCompletionsProvider.previousDefaultPrompt {
            types[index].prompt = ChatCompletionsProvider.defaultPrompt
        }
        if !types.contains(where: \.isOther) {
            types[0].isOther = true
        }
        guard types[0].name == "Созвон" else {
            return types
        }
        types[0].name = CallType.otherName
        if types[0].description == "любой разговор" {
            types[0].description = "ни один другой тип не подходит"
        }
        return types
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, otherwise fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    var retentionRules: RetentionRules {
        RetentionRules(rawAudio: rawAudioRetention, normalizedAudio: normalizedAudioRetention)
    }

    static let defaultEnabledCallApps: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.tinyspeck.slackmacgap",
        "com.tdesktop.Telegram",
        "org.telegram.desktop",
        "ru.keepcoder.Telegram",
        "com.hnc.Discord",
        "com.apple.FaceTime",
        "ru.yandex.mobile.telemost"
    ]
}
