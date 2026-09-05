import FluidAudio
import Foundation

/// wraps FluidAudio so the rest of the app only ever sees plain speaker intervals
final class Diarizer: @unchecked Sendable {
    private let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
    private var modelsReady = false

    /// Downloads and compiles the CoreML models on the first call. Separate from `timeline`
    /// because it is the longest wait of the whole pipeline and needs its own line on screen.
    func prepareModels() async throws {
        guard !modelsReady else {
            return
        }
        try await manager.prepareModels()
        modelsReady = true
    }

    func timeline(
        for audioURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [SpeakerInterval] {
        try await prepareModels()
        let result = try await manager.process(audioURL) { chunksProcessed, totalChunks in
            guard totalChunks > 0 else {
                return
            }
            onProgress?(Double(chunksProcessed) / Double(totalChunks))
        }
        // FluidAudio reports times as Float; the app works in Double throughout
        return result.segments.map { segment in
            SpeakerInterval(
                speaker: segment.speakerId,
                start: Double(segment.startTimeSeconds),
                end: Double(segment.endTimeSeconds)
            )
        }
    }
}
