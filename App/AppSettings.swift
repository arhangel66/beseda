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
    private let autoDetectKey = "podushka.autoDetectEnabled"
    private let enabledCallAppsKey = "podushka.enabledCallApps"
    private let rawRetentionKey = "podushka.rawAudioRetention"
    private let normalizedRetentionKey = "podushka.normalizedAudioRetention"
    private let stopOnSilenceKey = "podushka.stopOnSilence"
    private let notifyWhenReadyKey = "podushka.notifyWhenReady"
    private let onboardingDoneKey = "podushka.onboardingDone"
    private let copyFormatKey = "podushka.copyFormat"
    private let calendarEnabledKey = "podushka.calendarEnabled"
    private let calendarIdentifiersKey = "podushka.calendarIdentifiers"
    private let summaryServerURLKey = "podushka.summaryServerURL"
    private let summaryModelKey = "podushka.summaryModel"
    private let summaryPromptKey = "podushka.summaryPrompt"
    private let webhookEnabledKey = "podushka.webhookEnabled"
    private let webhookURLKey = "podushka.webhookURL"
    private let webhookSecretKey = "podushka.webhookSecret"
    private let speechModelKey = "podushka.speechModel"

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

    /// "" means automatic: `LocalModelProvider.defaultPrompt`
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
        self.summaryServerURL = defaults.string(forKey: summaryServerURLKey) ?? ""
        self.summaryModel = defaults.string(forKey: summaryModelKey) ?? ""
        self.summaryPrompt = defaults.string(forKey: summaryPromptKey) ?? ""
        self.webhookEnabled = defaults.bool(forKey: webhookEnabledKey)
        self.webhookURL = defaults.string(forKey: webhookURLKey) ?? ""
        self.webhookSecret = defaults.string(forKey: webhookSecretKey) ?? ""
        self.speechModelID = defaults.string(forKey: speechModelKey) ?? SpeechModel.default.id
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, otherwise fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    /// bound to the onboarding sheet: dismissing it is the same as finishing it
    var showOnboarding: Bool {
        get { !onboardingDone }
        set { onboardingDone = !newValue }
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
