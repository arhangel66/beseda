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

@Test func theInstalledModelTranscribesRealSpeech() async throws {
    let paths = AppPaths.current
    let model = SpeechModel.default
    // the model is installed, not vendored; without it there is nothing to assert against
    try #require(model.isDownloaded(in: paths.modelsDirectory))
    let sample = AppPaths.sourceRoot.appendingPathComponent("samples/jfk.wav")
    try #require(FileManager.default.fileExists(atPath: sample.path))

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
