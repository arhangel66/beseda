import Foundation
import Testing

@testable import Beseda

@Test func transcribingWithoutTheModelFileFailsWithTheTypedError() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-transcriber-\(UUID().uuidString)", isDirectory: true)
    let transcriber = LocalTranscriber(paths: AppPaths(dataDirectory: directory))

    await #expect(throws: BesedaError.self) {
        try await transcriber.start()
    }
    do {
        _ = try await transcriber.start()
    } catch {
        #expect(error.localizedDescription == BesedaError.runtimeMissingMessage)
    }
}

private let jfkSample = AppPaths.sourceRoot.appendingPathComponent("samples/jfk.wav")

// the model is installed and samples/ is gitignored; a fresh checkout or worktree has neither, so it skips
@Test(.enabled(if: SpeechModel.default.isDownloaded(in: AppPaths.current.modelsDirectory)
    && FileManager.default.fileExists(atPath: jfkSample.path)))
func theInstalledModelTranscribesRealSpeech() async throws {
    let paths = AppPaths.current
    let model = SpeechModel.default
    let sample = jfkSample

    let transcriber = LocalTranscriber(paths: paths, model: model)
    let ready = try await transcriber.start()
    let result = try await transcriber.transcribe(audioURL: sample)
    transcriber.shutdown()

    #expect(ready.model == model.id)
    #expect(result.text.lowercased().contains("ask not what your country can do for you"))
    #expect(!result.segments.isEmpty)
    #expect(result.segments.allSatisfy { $0.start <= $0.end })
    #expect(zip(result.segments, result.segments.dropFirst()).allSatisfy { $0.start <= $1.start })
}
