import Foundation
import Testing

@testable import Beseda

@MainActor
@Test func theSummarySettingsDefaultToEmptyAndRoundTripThroughUserDefaults() {
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    #expect(settings.summaryServerURL == "")
    #expect(settings.summaryModel == "")
    #expect(settings.summaryPrompt == "")

    settings.summaryServerURL = "http://localhost:1235/v1"
    settings.summaryModel = "google/gemma-4-26b-a4b-qat"
    settings.summaryPrompt = "свой промпт"

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.summaryServerURL == "http://localhost:1235/v1")
    #expect(reloaded.summaryModel == "google/gemma-4-26b-a4b-qat")
    #expect(reloaded.summaryPrompt == "свой промпт")
}

@MainActor
@Test func theWebhookSettingsDefaultToOffAndRoundTripThroughUserDefaults() {
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    #expect(settings.webhookEnabled == false)
    #expect(settings.webhookURL == "")
    #expect(settings.webhookSecret == "")

    settings.webhookEnabled = true
    settings.webhookURL = "https://kushetka.example/api/webhooks/krisp"
    settings.webhookSecret = "s3cret"

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.webhookEnabled == true)
    #expect(reloaded.webhookURL == "https://kushetka.example/api/webhooks/krisp")
    #expect(reloaded.webhookSecret == "s3cret")
}

@MainActor
@Test func podushkaValuesAreImportedUnlessAlreadySetUnderTheNewName() {
    let oldSuite = "beseda-test-old-\(UUID().uuidString)"
    let newSuite = "beseda-test-new-\(UUID().uuidString)"
    let legacy = UserDefaults(suiteName: oldSuite)!
    let defaults = UserDefaults(suiteName: newSuite)!
    defer {
        legacy.removePersistentDomain(forName: oldSuite)
        defaults.removePersistentDomain(forName: newSuite)
    }
    legacy.set(true, forKey: "podushka.onboardingDone")
    legacy.set("http://old", forKey: "podushka.webhookURL")
    defaults.set("http://new", forKey: "beseda.webhookURL")

    AppSettings.importLegacyValues(from: legacy, into: defaults)
    let settings = AppSettings(defaults: defaults)

    #expect(settings.onboardingDone)
    #expect(settings.webhookURL == "http://new")
}
