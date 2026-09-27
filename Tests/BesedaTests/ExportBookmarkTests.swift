import Foundation
import Testing
@testable import Beseda

private enum BookmarkFailure: Error { case invalid }

@MainActor
@Test func bookmarksPersistRecoverAndBalanceScopes() throws {
    let name = "bookmark-test-\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let old = URL(fileURLWithPath: "/tmp/beseda-old")
    let current = URL(fileURLWithPath: "/tmp/beseda-current")
    var starts = 0
    var stops = 0
    var stale = false
    var revoked = false
    var invalid = false
    var renewalFails = false
    let platform = ExportBookmarks(sandboxed: true, create: { url in
        if renewalFails { throw BookmarkFailure.invalid }
        return Data(url.path.utf8)
    }, resolve: { data in
        if invalid { throw BookmarkFailure.invalid }
        return (URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), stale)
    }, start: { _ in
        starts += 1
        return !revoked
    }, stop: { _ in stops += 1 })
    func reopen() -> AppSettings {
        AppSettings(defaults: defaults, keychain: Keychain(service: name), exportBookmarks: platform)
    }
    let first = reopen()
    try first.selectExportFolder(old)
    try first.selectExportFolder(current)
    let settings = reopen()
    #expect(settings.exportFolder == current.path)
    #expect(try settings.withExportFolder { $0.path } == current.path)
    #expect(try settings.withExportFolder(at: old.path) { $0.path } == old.path)
    #expect(starts == 2 && stops == 2)
    #expect(throws: BookmarkFailure.self) {
        try settings.withExportFolder { _ in throw BookmarkFailure.invalid }
    }
    #expect(starts == 3 && stops == 3)

    stale = true
    #expect(try settings.withExportFolder { $0.path } == current.path)
    #expect(defaults.data(forKey: "beseda.exportBookmark") == Data(current.path.utf8))
    renewalFails = true
    #expect(throws: AppSettings.ExportAccessError.self) { try settings.withExportFolder { _ in } }
    #expect(settings.exportNeedsReselection)
    #expect(starts == 5 && stops == 5)
    renewalFails = false
    stale = false
    invalid = true
    #expect(throws: AppSettings.ExportAccessError.self) { try settings.withExportFolder { _ in } }
    invalid = false
    revoked = true
    #expect(throws: AppSettings.ExportAccessError.self) { try settings.withExportFolder { _ in } }
    #expect(starts == 6 && stops == 5)
    revoked = false
    defaults.removeObject(forKey: "beseda.exportBookmarks")
    #expect(throws: AppSettings.ExportAccessError.self) { try settings.withExportFolder(at: old.path) { _ in } }
    try settings.selectExportFolder(old) // explicit reauthorization, without a panel
    #expect(try settings.withExportFolder(at: old.path) { $0.path } == old.path)
    #expect(!settings.exportNeedsReselection)
    #expect(starts == 7 && stops == 6)
}

@Test func bookmarkRecoveryStringsExistInBothLanguages() throws {
    for language in ["en", "ru"] {
        let file = Bundle.module.url(forResource: "Settings", withExtension: "strings", subdirectory: "\(language).lproj")
        #expect(file != nil)
        let strings = NSDictionary(contentsOf: try #require(file)) as? [String: String]
        for key in ["Выберите папку экспорта снова в настройках", "Для удаления старой копии выберите прежнюю папку и повторите удаление. Затем можно вернуть текущую папку."] {
            #expect(strings?[key]?.isEmpty == false)
        }
    }
}
