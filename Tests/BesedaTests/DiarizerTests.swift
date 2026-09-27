import Foundation
import Testing

@testable import Beseda

@Test func aDiarizerFileWithTheWrongHashIsNeverInstalled() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-diarizer-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let diarizer = Diarizer(
        paths: AppPaths(dataDirectory: root),
        downloader: { _, destination, _ in try Data(count: 16).write(to: destination) },
        freeSpace: { _ in nil }
    )

    await #expect(throws: BesedaError.self) { try await diarizer.download() }

    let left = FileManager.default.enumerator(atPath: diarizer.directory.path)?.allObjects as? [String] ?? []
    #expect(left.allSatisfy { !$0.hasSuffix(".bin") && !$0.hasSuffix(".mil") && !$0.hasSuffix(".partial") })
    #expect(!diarizer.isDownloaded)
}

@Test func theDiarizerDownloadStopsBeforeADiskThatCannotHoldIt() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-diarizer-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let diarizer = Diarizer(
        paths: AppPaths(dataDirectory: root),
        downloader: { _, _, _ in Issue.record("downloaded despite a full disk") },
        freeSpace: { _ in Diarizer.bytes }
    )

    await #expect(throws: BesedaError.self) { try await diarizer.download() }
}
