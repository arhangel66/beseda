import Foundation
import Testing

@testable import Podushka

@Test func catalogueEntriesAreDistinct() {
    let ids = SpeechModel.catalogue.map(\.id)
    let filenames = SpeechModel.catalogue.map(\.filename)
    #expect(Set(ids).count == ids.count)
    #expect(Set(filenames).count == filenames.count)
    #expect(SpeechModel.catalogue.allSatisfy { $0.sha256.count == 64 })
    #expect(SpeechModel.catalogue.allSatisfy { $0.bytes > 0 })
}

@Test func downloadURLsPinARevision() {
    // an unpinned "resolve/main" URL would let the file change under the recorded hash
    for model in SpeechModel.catalogue {
        #expect(!model.downloadURL.path.contains("/resolve/main/"))
        #expect(model.downloadURL.lastPathComponent == model.filename)
    }
}

@Test func onlyGigaamNeedsSplitting() {
    #expect(SpeechModel.parakeetV3.maxUtteranceSec == nil)
    #expect(SpeechModel.gigaamV3.maxUtteranceSec == 25)
    #expect(SpeechModel.default.id == SpeechModel.parakeetV3.id)
}

@Test func namedFindsCatalogueEntries() {
    #expect(SpeechModel.named("gigaam-v3-e2e-rnnt")?.title == "GigaAM v3")
    #expect(SpeechModel.named("whisper-large") == nil)
}

@Test func downloadStateFollowsTheFileSize() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = SpeechModel.parakeetV3

    #expect(!model.isDownloaded(in: directory))
    try Data("truncated".utf8).write(to: model.localURL(in: directory))
    #expect(!model.isDownloaded(in: directory))
}
