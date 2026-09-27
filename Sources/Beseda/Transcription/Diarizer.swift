import FluidAudio
import Foundation

/// wraps FluidAudio's Nemotron-3 so the rest of the app only ever sees plain speaker intervals
final class Diarizer: @unchecked Sendable {
    /// stored with every diarized call: a manual merge is tied to the labels of the model that made them
    static let id = "nemotron3-offline-\(ModelNames.Nemotron3.weightsVersion)"
    static let title = "Nemotron-3 Diarization"
    static let licence = "OpenMDW-1.1, NVIDIA"
    static let licenceURL = URL(string: "https://huggingface.co/nvidia/Nemotron-3-Diarization")!

    /// the offline preset's compiled bundle plus its silence embedding, as laid out in the Hub repo
    static let files: [(path: String, bytes: Int64, sha256: String)] = [
        ("monolithic/v2/Nemotron3Diarizer_offline.mlmodelc/weights/weight.bin", 198_654_080,
         "bab76e5f190d0e4a4e174e7fcb1e9beea58c6b2be56e665e2cac8fba6d10f7f1"),
        ("monolithic/v2/Nemotron3Diarizer_offline.mlmodelc/model.mil", 505_274,
         "ea5673d9e9ec785e7c8fb628acd82f9f86214c46b6584eaacdb6faddcb3f0277"),
        ("monolithic/v2/Nemotron3Diarizer_offline.mlmodelc/coremldata.bin", 758,
         "8b790c919c65744648c17290a26d3371e0e55db655310e7f8445080757b0bf08"),
        ("monolithic/v2/Nemotron3Diarizer_offline.mlmodelc/analytics/coremldata.bin", 243,
         "491594df92282a4f2cef65e96d236e210a5c4627063e37e822ec858aaaad416d"),
        ("learnable_sil_emb.bin", 2_048,
         "d4417b3c0eabdf7c47032fac2b5b5a7ee83d819a6ddda8fd8eaf74e2b5cc4ac7")
    ]
    static let bytes = files.reduce(0) { $0 + $1.bytes }
    private static let hubURL = URL(string:
        "https://huggingface.co/FluidInference/nemotron-3-diarization-coreml/resolve/25a90f97f254428d4b30374b76af9c74fdee8327/"
    )!

    let directory: URL
    private let downloader: RuntimeDownloader
    private let freeSpace: FreeSpaceReader
    private var diarizer: Nemotron3Diarizer?

    init(
        paths: AppPaths = .current,
        downloader: @escaping RuntimeDownloader = FileDownloader.download,
        freeSpace: @escaping FreeSpaceReader = FreeSpace.read
    ) {
        directory = paths.modelsDirectory.appendingPathComponent("nemotron-3-diarization", isDirectory: true)
        self.downloader = downloader
        self.freeSpace = freeSpace
    }

    /// FluidAudio loads the bundle and the embedding from one folder, so the repo's preset folder is dropped
    private func localURL(of hubPath: String) -> URL {
        directory.appendingPathComponent(hubPath.replacingOccurrences(of: "monolithic/v2/", with: ""))
    }

    var isDownloaded: Bool {
        Self.files.allSatisfy { file in
            let path = localURL(of: file.path).path
            return (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) == file.bytes
        }
    }

    /// Downloads the missing files and loads the model on the first call. Separate from `timeline`
    /// because it is the longest wait of the whole pipeline and needs its own line on screen.
    func prepareModels(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard diarizer == nil else {
            return
        }
        try await download(onProgress: onProgress)
        let models = try await Nemotron3Models.load(config: .offline, directory: directory)
        diarizer = Nemotron3Diarizer(config: .offline, models: models)
    }

    func timeline(for audioURL: URL) async throws -> [SpeakerInterval] {
        try await prepareModels()
        let samples = try AudioConverter().resampleAudioFile(audioURL)
        let (probabilities, frames) = try diarizer!.processComplete(samples)
        return Nemotron3Diarizer.segments(probabilities: probabilities, frameCount: frames).map { segment in
            SpeakerInterval(
                speaker: "spk-\(segment.speakerIndex)",
                start: Double(segment.startSeconds),
                end: Double(segment.endSeconds)
            )
        }
    }

    /// Each file lands beside its target and moves in only once its hash matches, so an interrupted
    /// or corrupted transfer never looks like an installed model; files already in place are kept.
    func download(onProgress: (@Sendable (Double) -> Void)? = nil) async throws {
        guard !isDownloaded else {
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FreeSpace.ensure(Self.bytes, in: directory, reader: freeSpace)
        var received: Int64 = 0
        for file in Self.files {
            let target = localURL(of: file.path)
            defer { received += file.bytes }
            if (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int64) == file.bytes {
                continue
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let partial = target.appendingPathExtension("partial")
            try? FileManager.default.removeItem(at: partial)
            let done = received
            try await downloader(Self.hubURL.appendingPathComponent(file.path), partial) { fraction in
                onProgress?(Double(done + Int64(fraction * Double(file.bytes))) / Double(Self.bytes))
            }
            guard try RuntimeInstaller.sha256(of: partial) == file.sha256 else {
                try? FileManager.default.removeItem(at: partial)
                throw BesedaError.processFailed("Файл модели разбора голосов повреждён при скачивании")
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: partial, to: target)
        }
    }
}
