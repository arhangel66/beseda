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
    private let autoDetectKey = "beseda.autoDetectEnabled"
    private let enabledCallAppsKey = "beseda.enabledCallApps"
    private let rawRetentionKey = "beseda.rawAudioRetention"
    private let normalizedRetentionKey = "beseda.normalizedAudioRetention"
    private let stopOnSilenceKey = "beseda.stopOnSilence"
    private let notifyWhenReadyKey = "beseda.notifyWhenReady"
    private let onboardingDoneKey = "beseda.onboardingDone"
    private let copyFormatKey = "beseda.copyFormat"
    private let calendarEnabledKey = "beseda.calendarEnabled"
    private let calendarIdentifiersKey = "beseda.calendarIdentifiers"
    private let summaryProviderKey = "beseda.summaryProvider"
    private let openRouterAPIKeyKey = "beseda.openRouterAPIKey"
    private let openRouterModelKey = "beseda.openRouterModel"
    private let summaryServerURLKey = "beseda.summaryServerURL"
    private let summaryModelKey = "beseda.summaryModel"
    private let summaryPromptKey = "beseda.summaryPrompt"
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
            defaults.set(openRouterAPIKey, forKey: openRouterAPIKeyKey)
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

    /// "" means automatic: `ChatCompletionsProvider.defaultPrompt`
    var summaryPrompt: String {
        didSet {
            defaults.set(summaryPrompt, forKey: summaryPromptKey)
        }
    }

    var webhookEnabled: Bool {
        didSet {
            defaults.set(webhookEnabled, forKey: webhookEnabledKey)
        }
    }

    var webhookURL: String {
        didSet {
            defaults.set(webhookURL, forKey: webhookURLKey)
        }
    }

    /// plain text in UserDefaults like every other setting; Keychain is a follow-up
    var webhookSecret: String {
        didSet {
            defaults.set(webhookSecret, forKey: webhookSecretKey)
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

    init(defaults: UserDefaults = .standard) {
        if defaults === UserDefaults.standard, let legacy = UserDefaults(suiteName: "app.podushka.Podushka") {
            AppSettings.importLegacyValues(from: legacy, into: defaults)
        }
        self.defaults = defaults
        self.autoDetectEnabled = AppSettings.bool(defaults, autoDetectKey, otherwise: false)
        self.enabledCallApps = (defaults.array(forKey: enabledCallAppsKey) as? [String])
            .map(Set.init) ?? AppSettings.defaultEnabledCallApps
        self.rawAudioRetention = defaults.string(forKey: rawRetentionKey)
            .flatMap(RetentionRule.init(rawValue:)) ?? .days90
        self.normalizedAudioRetention = defaults.string(forKey: normalizedRetentionKey)
            .flatMap(RetentionRule.init(rawValue:)) ?? .days30
        self.stopOnSilence = AppSettings.bool(defaults, stopOnSilenceKey, otherwise: true)
        self.notifyWhenReady = AppSettings.bool(defaults, notifyWhenReadyKey, otherwise: true)
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
        self.summaryPrompt = defaults.string(forKey: summaryPromptKey) ?? ""
        self.webhookEnabled = defaults.bool(forKey: webhookEnabledKey)
        self.webhookURL = defaults.string(forKey: webhookURLKey) ?? ""
        self.webhookSecret = defaults.string(forKey: webhookSecretKey) ?? ""
        self.speechModelID = defaults.string(forKey: speechModelKey) ?? SpeechModel.default.id
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
