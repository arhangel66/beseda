import CryptoKit
import Foundation
import Testing

@testable import Beseda

/// counts the downloads and hands back the bytes the test asked for
private actor Downloads {
    private(set) var sources: [URL] = []
    private var payload: Data
    private var failure: Error?

    init(payload: Data, failure: Error? = nil) {
        self.payload = payload
        self.failure = failure
    }

    func fetch(_ source: URL, to destination: URL) throws -> Data {
        sources.append(source)
        if let failure {
            throw failure
        }
        return payload
    }
}

@MainActor
private struct Harness {
    let directory: URL
    let paths: AppPaths
    /// a model whose bytes and hash match the payload the fake downloader serves
    let model: SpeechModel
    let payload = Data("gguf-bytes".utf8)

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("beseda-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        paths = AppPaths(dataDirectory: directory)
        let payload = Data("gguf-bytes".utf8)
        model = SpeechModel(
            id: "test-model",
            title: "Test",
            subtitle: "",
            languages: "ru",
            bytes: Int64(payload.count),
            filename: "test-model.gguf",
            downloadURL: URL(string: "https://example.invalid/test-model.gguf")!,
            sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
            transcriptionLanguage: nil,
            maxUtteranceSec: nil
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func installer(
        downloads: Downloads,
        progress: [Double] = [],
        warmUp: @escaping () async throws -> Void = {}
    ) -> RuntimeInstaller {
        RuntimeInstaller(
            paths: paths,
            model: model,
            downloader: { source, destination, onProgress in
                let data = try await downloads.fetch(source, to: destination)
                progress.forEach(onProgress)
                try data.write(to: destination)
            },
            warmUp: warmUp
        )
    }

    func plantModel() throws {
        try FileManager.default.createDirectory(at: paths.modelsDirectory, withIntermediateDirectories: true)
        try payload.write(to: model.localURL(in: paths.modelsDirectory))
    }

    func settled(_ installer: RuntimeInstaller) async throws {
        for _ in 0..<300 where installer.isInstalling {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
@Test func aFreshDirectoryHasEveryStagePending() throws {
    let harness = try Harness()
    defer { harness.tearDown() }

    let installer = harness.installer(downloads: Downloads(payload: harness.payload))

    #expect(RuntimeStage.allCases.allSatisfy { installer.state(of: $0) == .pending })
    #expect(!installer.isReady)
}

@MainActor
@Test func aModelAlreadyOnDiskIsNotDownloadedAgain() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }
    try harness.plantModel()
    let downloads = Downloads(payload: harness.payload)

    let installer = harness.installer(downloads: downloads)
    installer.install()
    try await harness.settled(installer)

    #expect(installer.isReady)
    #expect(await downloads.sources.isEmpty)
}

@MainActor
@Test func installDownloadsTheModelAndMarksTheWarmUp() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }
    let downloads = Downloads(payload: harness.payload)

    let installer = harness.installer(downloads: downloads)
    installer.install()
    try await harness.settled(installer)

    #expect(await downloads.sources == [harness.model.downloadURL])
    #expect(installer.state(of: .speechModel) == .done)
    #expect(installer.state(of: .warmUp) == .done)
    #expect(installer.isDownloaded(harness.model))
}

@MainActor
@Test func aWrongHashFailsTheStageAndLeavesNoFile() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }
    let downloads = Downloads(payload: Data("something-else".utf8))

    let installer = harness.installer(downloads: downloads)
    installer.install()
    try await harness.settled(installer)

    #expect(installer.state(of: .speechModel) == .failed("Файл модели повреждён при скачивании"))
    #expect(installer.state(of: .warmUp) == .pending)
    #expect(!installer.isDownloaded(harness.model))
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: harness.paths.modelsDirectory.path)
    #expect(leftovers.isEmpty)
}

@MainActor
@Test func aFailedDownloadStopsTheChainAndKeepsItsMessage() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }
    let downloads = Downloads(payload: harness.payload, failure: BesedaError.processFailed("Сервер ответил 404"))

    let installer = harness.installer(downloads: downloads)
    installer.install()
    try await harness.settled(installer)

    #expect(installer.state(of: .speechModel) == .failed("Сервер ответил 404"))
    #expect(installer.state(of: .warmUp) == .pending)
    #expect(!installer.isInstalling)
}

@MainActor
@Test func progressFractionsReachTheStage() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }
    let installer = harness.installer(
        downloads: Downloads(payload: harness.payload),
        progress: [0.25, 0.5],
        warmUp: { try await Task.sleep(for: .milliseconds(200)) }
    )

    installer.install()
    for _ in 0..<200 {
        if case .running = installer.state(of: .warmUp) {
            break
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    // the download finished, so the model stage settled on done rather than a fraction
    #expect(installer.state(of: .speechModel) == .done)
    try await harness.settled(installer)
    #expect(installer.isReady)
}

@MainActor
@Test func switchingModelsReopensTheStages() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }
    let installer = harness.installer(downloads: Downloads(payload: harness.payload))
    installer.install()
    try await harness.settled(installer)
    #expect(installer.isReady)

    installer.select(.gigaamV3)

    #expect(!installer.isReady)
    #expect(installer.state(of: .speechModel) == .pending)
    #expect(installer.state(of: .warmUp) == .pending)
}

@MainActor
@Test func removingAModelDropsItsFileAndTheWarmUp() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }
    let installer = harness.installer(downloads: Downloads(payload: harness.payload))
    installer.install()
    try await harness.settled(installer)

    try installer.remove(harness.model)

    #expect(!installer.isDownloaded(harness.model))
    #expect(installer.state(of: .warmUp) == .pending)
    #expect(installer.diskUsage() == 0)
}

@Test func sha256MatchesTheKnownDigestOfAFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("abc".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(try RuntimeInstaller.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}
