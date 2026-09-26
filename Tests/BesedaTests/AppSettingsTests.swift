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
    #expect(settings.callTypes.map(\.prompt) == [ChatCompletionsProvider.defaultPrompt])
    #expect(settings.autoProcessCalls == false)

    settings.summaryServerURL = "http://localhost:1235/v1"
    settings.summaryModel = "google/gemma-4-26b-a4b-qat"
    settings.callTypes.append(CallType(name: "Дейли", description: "рабочая встреча", prompt: "свой промпт"))
    settings.autoProcessCalls = true

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.summaryServerURL == "http://localhost:1235/v1")
    #expect(reloaded.summaryModel == "google/gemma-4-26b-a4b-qat")
    #expect(reloaded.callTypes == settings.callTypes)
    #expect(reloaded.autoProcessCalls)
}

@MainActor
@Test func theSummaryProviderDefaultsToTheBuiltInModelAndRoundTripsThroughUserDefaults() {
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    #expect(settings.summaryProvider == .builtIn)
    #expect(SummaryProvider.allCases == [.openRouter, .builtIn, .lmStudio])
    #expect(settings.openRouterAPIKey == "")
    #expect(settings.openRouterModel == "")

    settings.summaryProvider = .openRouter
    settings.openRouterAPIKey = "sk-or-v1-secret"
    settings.openRouterModel = "google/gemini-3.8-flash"

    let reloaded = AppSettings(defaults: defaults)
    #expect(reloaded.summaryProvider == .openRouter)
    #expect(reloaded.openRouterAPIKey == "sk-or-v1-secret")
    #expect(reloaded.openRouterModel == "google/gemini-3.8-flash")
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

@MainActor
@Test func anEditedSummaryPromptBecomesTheFirstCallTypesPrompt() {
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("старый свой промпт", forKey: "beseda.summaryPrompt")

    let settings = AppSettings(defaults: defaults)

    #expect(settings.callTypes.map(\.prompt) == ["старый свой промпт"])
}

@MainActor
@Test func anUnrenamedCallTypeFromBESEDA46BecomesOtherWithItsPrompt() throws {
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let old = CallType(name: "Созвон", description: "любой разговор", prompt: "мой промпт")
    defaults.set(try JSONEncoder().encode([old]), forKey: "beseda.callTypes")

    let settings = AppSettings(defaults: defaults)

    #expect(settings.callTypes.map(\.name) == ["Другое"])
    #expect(settings.callTypes[0].prompt == "мой промпт")
    #expect(settings.callTypes[0].id == old.id)
}

@MainActor
@Test func aRenamedFirstTypeIsNotMigrated() throws {
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let renamed = CallType(name: "Рабочее", description: "любой разговор", prompt: "p")
    defaults.set(try JSONEncoder().encode([renamed]), forKey: "beseda.callTypes")

    let settings = AppSettings(defaults: defaults)

    #expect(settings.callTypes.map(\.name) == ["Рабочее"])
    #expect(settings.callTypes[0].prompt == "p")
}

@MainActor
@Test func storedTypesWithoutTheFlagMakeTheFirstOtherAndItKeepsTheFlagAnywhereInTheList() throws {
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    // the JSON a build before the flag wrote: no `isOther` key
    defaults.set(Data("""
        [{"id":"8C1E1A52-6F57-4C3C-9E0B-2B8D5B4E6A11","name":"Другое","description":"","prompt":"общий"},
         {"id":"0B5D2E7A-1C4F-4B8E-8A3D-7E6F5A4B3C22","name":"Дейли","description":"","prompt":"p"}]
        """.utf8), forKey: "beseda.callTypes")

    let settings = AppSettings(defaults: defaults)
    settings.callTypes.reverse()
    let reloaded = AppSettings(defaults: defaults)
    reloaded.deleteCallType(id: reloaded.callTypes[1].id)

    #expect(reloaded.callTypes.map(\.name) == ["Дейли", "Другое"])
    #expect(reloaded.callTypes.other.prompt == "общий")
}

@MainActor
@Test func otherCannotBeDeletedButOtherTypesCan() {
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    let daily = CallType(name: "Дейли", description: "", prompt: "p")
    settings.callTypes.append(daily)

    settings.deleteCallType(id: settings.callTypes[0].id)
    settings.deleteCallType(id: daily.id)

    #expect(settings.callTypes.map(\.name) == ["Другое"])
}

@MainActor
@Test func jevClassifiesByDefaultOnlyWhenAnOpenRouterKeyIsSet() {
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)
    let withoutKey = settings.classifiesWithJev

    settings.openRouterAPIKey = "sk-or-v1-secret"
    let withKey = settings.classifiesWithJev
    settings.classifyLocally = true

    #expect(!withoutKey)
    #expect(withKey)
    #expect(!AppSettings(defaults: defaults).classifiesWithJev)
}
