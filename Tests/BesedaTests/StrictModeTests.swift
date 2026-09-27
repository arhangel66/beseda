import Foundation
import Testing

@testable import Beseda

@Test func fileVaultIsReadFromTheIsActiveAnswerAndUnknownOtherwise() {
    #expect(FileVault.isOn(run: { (0, "true\n") }) == true)
    #expect(FileVault.isOn(run: { (1, "false\n") }) == false)
    #expect(FileVault.isOn(run: { (2, "") }) == nil)
    #expect(FileVault.isOn(run: { (1, "Error: something") }) == nil)
    #expect(FileVault.isOn(run: { nil }) == nil)
}

@Test func onlyAFolderInsideMobileDocumentsCountsAsICloudDrive() {
    let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    #expect(ICloudDrive.contains("/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/Beseda", home: home))
    #expect(ICloudDrive.contains("/Users/someone/Library/Mobile Documents", home: home))
    #expect(!ICloudDrive.contains("/Users/someone/Library/Mobile Documents Old", home: home))
    #expect(!ICloudDrive.contains("/Users/someone/Documents/Beseda", home: home))
    #expect(!ICloudDrive.contains("", home: home))
}

@MainActor
@Test func strictModeOverridesItsSettingsAndTurningItOffRestoresThem() {
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
        Keychain(service: suiteName).deleteAll()
    }
    let settings = AppSettings(defaults: defaults, keychain: Keychain(service: suiteName))
    settings.rawAudioRetention = .forever
    settings.normalizedAudioRetention = .days90
    settings.exportFolder = "/tmp/export"

    settings.setStrictMode(true)
    let reloaded = AppSettings(defaults: defaults, keychain: Keychain(service: suiteName))
    #expect(reloaded.strictMode)
    #expect(reloaded.rawAudioRetention == .immediately)
    #expect(reloaded.normalizedAudioRetention == .immediately)
    #expect(reloaded.exportFolder == "")
    #expect(reloaded.localOnly)
    #expect(reloaded.excludesFromBackup)

    reloaded.setStrictMode(false)
    #expect(!reloaded.strictMode)
    #expect(reloaded.rawAudioRetention == .forever)
    #expect(reloaded.normalizedAudioRetention == .days90)
    #expect(reloaded.exportFolder == "/tmp/export")
    #expect(!reloaded.localOnly)
    #expect(!reloaded.excludesFromBackup)
}

@MainActor
@Test func theBackupExclusionIsAppliedToTheDataFolderAtLaunchAndCleared() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-backup-\(UUID().uuidString)", isDirectory: true)
    let suiteName = "beseda-test-\(UUID().uuidString)"
    defer {
        UserDefaults().removePersistentDomain(forName: suiteName)
        Keychain(service: suiteName).deleteAll()
        try? FileManager.default.removeItem(at: root)
    }
    let paths = AppPaths(dataDirectory: root)
    try FileManager.default.createDirectory(at: paths.callsDirectory, withIntermediateDirectories: true)
    let settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!, keychain: Keychain(service: suiteName))
    #expect(!settings.excludesFromBackup)
    settings.excludesFromBackup = true

    let controller = AppController(paths: paths, settings: settings)
    #expect(BackupExclusion.isExcluded(root))

    settings.excludesFromBackup = false
    controller.applyBackupExclusion()
    #expect(!BackupExclusion.isExcluded(root))
}
