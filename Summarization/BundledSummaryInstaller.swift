import Foundation

/// Installs what the built-in summary provider needs: the llama.cpp server build and the Gemma
/// model. Same care as `RuntimeInstaller` — download beside the target, check the hash, move it
/// in — but one row in Settings shows the whole thing, so the state here is one stage deep.
@MainActor
@Observable
final class BundledSummaryInstaller {
    enum Stage {
        case runtime
        case model
        case warmUp

        var title: String {
            switch self {
            case .runtime:
                "Движок"
            case .model:
                "Модель"
            case .warmUp:
                "Подготовка"
            }
        }
    }

    /// nil when nothing is being installed
    private(set) var stage: Stage?
    /// nil while the running stage has no percentage to show
    private(set) var fraction: Double?
    private(set) var failure: String?
    private(set) var isReady: Bool
    private(set) var isInstalling = false

    @ObservationIgnored var log: (String) -> Void = { _ in }
    @ObservationIgnored private let paths: AppPaths
    @ObservationIgnored private let artifacts: BundledSummary
    @ObservationIgnored private let downloader: RuntimeDownloader
    @ObservationIgnored private let warmUp: () async throws -> Void

    init(
        paths: AppPaths,
        artifacts: BundledSummary = .current,
        downloader: @escaping RuntimeDownloader = FileDownloader.download,
        warmUp: @escaping () async throws -> Void
    ) {
        self.paths = paths
        self.artifacts = artifacts
        self.downloader = downloader
        self.warmUp = warmUp
        self.isReady = artifacts.isInstalled(paths)
    }

    /// the stages that are still missing, in order; stops at the first failure
    func install() {
        guard !isInstalling else {
            return
        }
        failure = nil
        isInstalling = true
        Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                isInstalling = false
                stage = nil
                fraction = nil
                isReady = artifacts.isInstalled(paths)
            }
            do {
                if !artifacts.isRuntimeInstalled(paths) {
                    try await run(.runtime, installRuntime)
                }
                if !artifacts.isModelDownloaded(paths) {
                    try await run(.model, downloadModel)
                }
                if !isWarmedUp {
                    try await run(.warmUp, markWarmedUp)
                }
                log("Summary model installed")
            } catch {
                failure = error.localizedDescription
                log("Summary model install failed: \(error.localizedDescription)")
            }
        }
    }

    /// Frees the 4.6 GB model. The small engine stays so reinstalling only downloads the model.
    func remove() throws {
        let model = artifacts.modelFile(paths)
        if FileManager.default.fileExists(atPath: model.path) {
            try FileManager.default.removeItem(at: model)
        }
        let marker = artifacts.warmUpMarker(paths)
        if FileManager.default.fileExists(atPath: marker.path) {
            try FileManager.default.removeItem(at: marker)
        }
        isReady = artifacts.isInstalled(paths)
    }

    private func run(_ stage: Stage, _ body: () async throws -> Void) async throws {
        self.stage = stage
        fraction = nil
        try await body()
    }

    private var isWarmedUp: Bool {
        (try? String(contentsOf: artifacts.warmUpMarker(paths), encoding: .utf8)) == artifacts.llamaBuild
    }

    /// Unpacks the release tarball and keeps only `llama-server` and the libraries it loads;
    /// the other thirty tools in it are dead weight.
    private func installRuntime() async throws {
        let staging = paths.runtimeDirectory.appendingPathComponent("llama-download", isDirectory: true)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let archive = staging.appendingPathComponent("llama.tar.gz")
        try await download(artifacts.llamaArchiveURL, to: archive)
        guard try RuntimeInstaller.sha256(of: archive) == artifacts.llamaArchiveSHA256 else {
            throw BesedaError.processFailed("Движок повредился при скачивании")
        }

        try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["xzf", archive.path, "-C", staging.path],
            currentDirectoryURL: nil
        )

        let unpacked = staging.appendingPathComponent(artifacts.archiveRootName, isDirectory: true)
        let build = artifacts.buildDirectory(paths)
        try? FileManager.default.removeItem(at: build)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: unpacked.path)
        for name in names where name == "llama-server" || name.hasSuffix(".dylib") {
            try FileManager.default.moveItem(
                at: unpacked.appendingPathComponent(name),
                to: build.appendingPathComponent(name)
            )
        }
        guard artifacts.isRuntimeInstalled(paths) else {
            throw BesedaError.processFailed("В архиве движка не оказалось llama-server")
        }
    }

    private func downloadModel() async throws {
        try FileManager.default.createDirectory(at: paths.modelsDirectory, withIntermediateDirectories: true)
        let target = artifacts.modelFile(paths)
        let partial = target.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)

        try await download(artifacts.modelURL, to: partial)
        guard try RuntimeInstaller.sha256(of: partial) == artifacts.modelSHA256 else {
            try? FileManager.default.removeItem(at: partial)
            throw BesedaError.processFailed("Файл модели повреждён при скачивании")
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)
    }

    /// starting the server once compiles the Metal shaders, so the first real summary does not
    private func markWarmedUp() async throws {
        try await warmUp()
        try Data(artifacts.llamaBuild.utf8).write(to: artifacts.warmUpMarker(paths))
    }

    private func download(_ source: URL, to destination: URL) async throws {
        try await downloader(source, destination) { [weak self] fraction in
            Task { @MainActor in
                self?.fraction = fraction
            }
        }
    }
}
