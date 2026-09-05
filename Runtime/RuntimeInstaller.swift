import CryptoKit
import Foundation

/// The speech engine is installed in stages; each one leaves an artefact on disk, so a relaunch
/// resumes where the last run stopped instead of downloading again.
enum RuntimeStage: String, CaseIterable, Identifiable {
    case speechModel
    case warmUp

    var id: String {
        rawValue
    }
}

enum RuntimeStageState: Equatable {
    case pending
    /// nil while the stage has no percentage to show
    case running(fraction: Double?)
    case done
    case failed(String)

    var isDone: Bool {
        self == .done
    }
}

/// Fetches one file, reporting the share received. Injected so the installer can be tested
/// without a network.
typealias RuntimeDownloader = @Sendable (
    _ source: URL,
    _ destination: URL,
    _ onProgress: @escaping @Sendable (Double) -> Void
) async throws -> Void

@MainActor
@Observable
final class RuntimeInstaller {
    private(set) var states: [RuntimeStage: RuntimeStageState] = [:]
    private(set) var isInstalling = false
    /// the model the stages install; switching it re-runs both stages
    private(set) var model: SpeechModel

    @ObservationIgnored var log: (String) -> Void = { _ in }
    @ObservationIgnored private let paths: AppPaths
    @ObservationIgnored private let downloader: RuntimeDownloader
    @ObservationIgnored private let warmUp: () async throws -> Void

    init(
        paths: AppPaths,
        model: SpeechModel = .default,
        downloader: @escaping RuntimeDownloader = FileDownloader.download,
        warmUp: @escaping () async throws -> Void
    ) {
        self.paths = paths
        self.model = model
        self.downloader = downloader
        self.warmUp = warmUp
        refresh()
    }

    var isReady: Bool {
        RuntimeStage.allCases.allSatisfy { states[$0]?.isDone == true }
    }

    func state(of stage: RuntimeStage) -> RuntimeStageState {
        states[stage] ?? .pending
    }

    func select(_ model: SpeechModel) {
        guard model != self.model else {
            return
        }
        self.model = model
        refresh()
    }

    /// what the disk says; a failed stage keeps its message until the next attempt
    func refresh() {
        for stage in RuntimeStage.allCases {
            if isArtefactPresent(stage) {
                states[stage] = .done
            } else if case .failed = states[stage] {
                continue
            } else {
                states[stage] = .pending
            }
        }
    }

    /// the pending stages in order; stops at the first failure
    func install() {
        guard !isInstalling else {
            return
        }
        isInstalling = true
        Task { [weak self] in
            defer { self?.isInstalling = false }
            guard let self else {
                return
            }
            refresh()
            for stage in RuntimeStage.allCases where !state(of: stage).isDone {
                states[stage] = .running(fraction: nil)
                do {
                    try await run(stage)
                    states[stage] = .done
                    log("Runtime \(stage.rawValue) done")
                } catch {
                    states[stage] = .failed(error.localizedDescription)
                    log("Runtime \(stage.rawValue) failed: \(error.localizedDescription)")
                    return
                }
            }
        }
    }

    /// Deletes one model's file, and the warm-up marker when that model was the active one.
    func remove(_ model: SpeechModel) throws {
        try? FileManager.default.removeItem(at: model.localURL(in: paths.modelsDirectory))
        if model == self.model {
            try? FileManager.default.removeItem(at: warmUpMarker)
        }
        refresh()
    }

    func isDownloaded(_ model: SpeechModel) -> Bool {
        model.isDownloaded(in: paths.modelsDirectory)
    }

    func diskUsage() -> Int64 {
        SpeechModel.catalogue.reduce(0) { total, model in
            total + (isDownloaded(model) ? model.bytes : 0)
        }
    }

    private var warmUpMarker: URL {
        paths.runtimeDirectory.appendingPathComponent("warm-up.ok")
    }

    private func isArtefactPresent(_ stage: RuntimeStage) -> Bool {
        switch stage {
        case .speechModel:
            return isDownloaded(model)
        case .warmUp:
            // the marker names the model it was made for, so switching models warms up again
            return (try? String(contentsOf: warmUpMarker, encoding: .utf8)) == model.id
        }
    }

    private func run(_ stage: RuntimeStage) async throws {
        switch stage {
        case .speechModel:
            try await download(model)
        case .warmUp:
            try await warmUp()
            try FileManager.default.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)
            try Data(model.id.utf8).write(to: warmUpMarker)
        }
    }

    /// Downloads beside the target and only moves it in once the hash matches, so an interrupted
    /// or corrupted transfer can never look like an installed model.
    private func download(_ model: SpeechModel) async throws {
        let directory = paths.modelsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = model.localURL(in: directory)
        let partial = target.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)

        try await downloader(model.downloadURL, partial) { [weak self] fraction in
            Task { @MainActor in
                self?.states[.speechModel] = .running(fraction: fraction)
            }
        }

        let digest = try Self.sha256(of: partial)
        guard digest == model.sha256 else {
            try? FileManager.default.removeItem(at: partial)
            throw PodushkaError.processFailed("Файл модели повреждён при скачивании")
        }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Reports the share received; the async download API takes it as the task's delegate.
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            return
        }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    /// the async `download(from:delegate:)` hands the file back as its return value
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

enum FileDownloader {
    static let download: RuntimeDownloader = { source, destination, onProgress in
        let (temporary, response) = try await URLSession.shared.download(
            from: source, delegate: DownloadProgress(onProgress: onProgress)
        )
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw PodushkaError.processFailed("Сервер ответил \(http.statusCode)")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        onProgress(1)
    }
}
