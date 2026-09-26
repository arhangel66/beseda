import AVFAudio
import Foundation
import Testing

@testable import Beseda

@MainActor
@Test func queueProcessesTwoCallsFinishingBackToBackInOrder() async {
    var processed: [String] = []
    var release: CheckedContinuation<Void, Never>?
    let queue = SerialQueue<String> { callID in
        if callID == "first" {
            await withCheckedContinuation { release = $0 }
        }
        processed.append(callID)
    }

    queue.enqueue("first")
    while release == nil { await Task.yield() }
    queue.enqueue("second")
    release?.resume()
    while processed.count < 2 { await Task.yield() }

    #expect(processed == ["first", "second"])
}

@MainActor
@Test func aDeletedCallWaitingInTheQueueIsNotProcessed() async {
    var processed: [String] = []
    var release: CheckedContinuation<Void, Never>?
    let queue = SerialQueue<String> { callID in
        if callID == "running" {
            await withCheckedContinuation { release = $0 }
        }
        processed.append(callID)
    }

    queue.enqueue("running")
    while release == nil { await Task.yield() }
    queue.enqueue("deleted")
    queue.enqueue("kept")
    queue.removeWaiting { $0 == "deleted" }
    release?.resume()
    while processed.count < 2 { await Task.yield() }

    #expect(processed == ["running", "kept"])
}

@Test func writePastTheLimitSurfacesAsARecordingWarning() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-limit-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_000)!
    buffer.frameLength = 1_000
    let recorder = try PCMFloatRecorder(
        url: directory.appendingPathComponent("me.raw.wav"),
        sampleRate: 48_000, channelCount: 1, activityTracker: nil,
        maximumDataBytes: 6_000
    )

    try recorder.append(pcmBuffer: buffer)
    #expect(recorder.writeError == nil)
    #expect(throws: AudioCaptureError.self) { try recorder.append(pcmBuffer: buffer) }

    let writeError = try #require(recorder.writeError)
    #expect(recorder.droppedBufferCount == 1)
    #expect(AppController.recordingWarning(forWriteError: writeError).contains("4 ГБ"))
    #expect(AppController.recordingWarning(forWriteError: CocoaError(.fileWriteOutOfSpace)).contains("не удалось записать"))
    #expect(try recorder.finish().frameCount == 1_000)
}
