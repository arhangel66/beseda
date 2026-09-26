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
            "Сразу"
        case .days30:
            "30 дней"
        case .days90:
            "90 дней"
        case .forever:
            "Всегда"
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
    private let webhookEnabledKey = "beseda.webhookEnabled"
    private let webhookURLKey = "beseda.webhookURL"
    private let webhookSecretKey = "beseda.webhookSecret"
    private let speechModelKey = "beseda.speechModel"

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

    /// a plain path, empty = no export; no security-scoped bookmark while the app is not sandboxed
    var exportFolder: String {
        didSet {
            defaults.set(exportFolder, forKey: exportFolderKey)
        }
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

    var speechModel: SpeechModel {
        SpeechModel.named(speechModelID) ?? .default
    }

    init(defaults: UserDefaults = .standard, keychain: Keychain = Keychain()) {
        if defaults === UserDefaults.standard, let legacy = UserDefaults(suiteName: "app.podushka.Podushka") {
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
        self.openRouterAPIKey = AppSettings.secret(openRouterAPIKeyKey, defaults: defaults, keychain: keychain)
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
        self.webhookSecret = AppSettings.secret(webhookSecretKey, defaults: defaults, keychain: keychain)
        self.speechModelID = defaults.string(forKey: speechModelKey) ?? SpeechModel.default.id
    }

    /// a secret still in UserDefaults (a release before the Keychain, or a failed write) moves to the
    /// Keychain here; if the Keychain refuses, it stays in defaults and keeps working from there
    private static func secret(_ key: String, defaults: UserDefaults, keychain: Keychain) -> String {
        guard let stored = defaults.string(forKey: key) else {
            return keychain.read(account: key) ?? ""
        }
        if keychain.save(stored, account: key) {
            defaults.removeObject(forKey: key)
        }
        return stored
    }

    private func storeSecret(_ value: String, key: String) {
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
    static func migratingStoredCallTypes(_ types: [CallType]) -> [CallType] {
        var types = types
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
