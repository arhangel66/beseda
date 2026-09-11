import CryptoKit
import Foundation
import Testing

@testable import Beseda

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Serves the two artefacts by URL, and can fail one of them on demand.
private actor Downloads {
    private(set) var sources: [URL] = []
    private let files: [URL: Data]
    private let failing: URL?

    init(files: [URL: Data], failing: URL? = nil) {
        self.files = files
        self.failing = failing
    }

    func fetch(_ source: URL) throws -> Data {
        sources.append(source)
        if source == failing {
            throw BesedaError.processFailed("сеть отвалилась")
        }
        return files[source] ?? Data()
    }
}

@MainActor
private struct Harness {
    let directory: URL
    let paths: AppPaths
    let artifacts: BundledSummary
    let archive: Data
    let modelPayload = Data("gguf-bytes".utf8)

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("beseda-summary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        paths = AppPaths(dataDirectory: directory)
        archive = try Self.makeArchive(in: directory, root: "llama-test-build")
        let payload = Data("gguf-bytes".utf8)
        artifacts = BundledSummary(
            title: "Test",
            subtitle: "",
            llamaBuild: "test-build",
            llamaArchiveURL: URL(string: "https://example.invalid/llama.tar.gz")!,
            llamaArchiveSHA256: sha256(archive),
            modelFilename: "test-model.gguf",
            modelURL: URL(string: "https://example.invalid/test-model.gguf")!,
            modelSHA256: sha256(payload),
            modelBytes: Int64(payload.count),
            modelID: "test-model"
        )
    }

    /// a tarball shaped like the llama.cpp release: one directory with the server, a library
    /// and a tool nobody needs
    private static func makeArchive(in directory: URL, root: String) throws -> Data {
        let staging = directory.appendingPathComponent("archive-source", isDirectory: true)
        let contents = staging.appendingPathComponent(root, isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data("server".utf8).write(to: contents.appendingPathComponent("llama-server"))
        try Data("lib".utf8).write(to: contents.appendingPathComponent("libggml.0.dylib"))
        try Data("bench".utf8).write(to: contents.appendingPathComponent("llama-bench"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: contents.appendingPathComponent("llama-server").path
        )
        let tarball = directory.appendingPathComponent("source.tar.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["czf", tarball.path, "-C", staging.path, root]
        try process.run()
        process.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: staging) }
        return try Data(contentsOf: tarball)
    }

    var files: [URL: Data] {
        [artifacts.llamaArchiveURL: archive, artifacts.modelURL: modelPayload]
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func installer(
        downloads: Downloads,
        warmUp: @escaping () async throws -> Void = {}
    ) -> BundledSummaryInstaller {
        BundledSummaryInstaller(
            paths: paths,
            artifacts: artifacts,
            downloader: { source, destination, onProgress in
                let data = try await downloads.fetch(source)
                onProgress(1)
                try data.write(to: destination)
            },
            warmUp: warmUp
        )
    }

    func settled(_ installer: BundledSummaryInstaller) async throws {
        for _ in 0..<300 where installer.isInstalling {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
@Test func installingLeavesTheServerTheModelAndTheWarmUpMarkerOnDisk() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }
    var warmedUp = false

    let installer = harness.installer(downloads: Downloads(files: harness.files)) {
        warmedUp = true
    }
    installer.install()
    try await harness.settled(installer)

    #expect(installer.failure == nil)
    #expect(installer.isReady)
    #expect(warmedUp)
    #expect(harness.artifacts.isInstalled(harness.paths))
    let marker = try String(contentsOf: harness.artifacts.warmUpMarker(harness.paths), encoding: .utf8)
    #expect(marker == "test-build")
}

@MainActor
@Test func onlyTheServerAndItsLibrariesSurviveTheUnpacking() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }

    let installer = harness.installer(downloads: Downloads(files: harness.files))
    installer.install()
    try await harness.settled(installer)

    let build = harness.artifacts.buildDirectory(harness.paths)
    let kept = try FileManager.default.contentsOfDirectory(atPath: build.path).sorted()
    #expect(kept == ["libggml.0.dylib", "llama-server", "warm-up.ok"])
    // the staging directory does not outlive the install
    #expect(!FileManager.default.fileExists(
        atPath: harness.paths.runtimeDirectory.appendingPathComponent("llama-download").path
    ))
}

@MainActor
@Test func aModelThatArrivesCorruptedLeavesNoFileBehind() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }
    let wrongBytes = [harness.artifacts.llamaArchiveURL: harness.archive,
                      harness.artifacts.modelURL: Data("не те байты".utf8)]

    let installer = harness.installer(downloads: Downloads(files: wrongBytes))
    installer.install()
    try await harness.settled(installer)

    #expect(installer.failure == "Файл модели повреждён при скачивании")
    #expect(!installer.isReady)
    #expect(!harness.artifacts.isModelDownloaded(harness.paths))
    #expect(!FileManager.default.fileExists(
        atPath: harness.artifacts.modelFile(harness.paths).appendingPathExtension("partial").path
    ))
}

@MainActor
@Test func aFailedEngineDownloadStopsBeforeTheFourGigabyteModel() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }
    let downloads = Downloads(files: harness.files, failing: harness.artifacts.llamaArchiveURL)

    let installer = harness.installer(downloads: downloads)
    installer.install()
    try await harness.settled(installer)

    #expect(installer.failure != nil)
    #expect(await downloads.sources == [harness.artifacts.llamaArchiveURL])
}

@MainActor
@Test func removingTakesBackTheModelAndKeepsTheEngine() async throws {
    let harness = try Harness()
    defer { harness.tearDown() }

    let installer = harness.installer(downloads: Downloads(files: harness.files))
    installer.install()
    try await harness.settled(installer)
    try installer.remove()

    #expect(!installer.isReady)
    #expect(!FileManager.default.fileExists(atPath: harness.artifacts.modelFile(harness.paths).path))
    #expect(harness.artifacts.isRuntimeInstalled(harness.paths))
    #expect(!FileManager.default.fileExists(atPath: harness.artifacts.warmUpMarker(harness.paths).path))
}

@MainActor
@Test func aServerThatIsNotInstalledIsReportedAsAMissingModel() async {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-summary-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = LlamaServer(paths: AppPaths(dataDirectory: directory))

    do {
        _ = try await server.ensureRunning()
        Issue.record("ожидалась ошибка modelMissing")
    } catch SummarizationError.modelMissing {
        #expect(!server.isRunning)
    } catch {
        Issue.record("неожиданная ошибка: \(error)")
    }
}
