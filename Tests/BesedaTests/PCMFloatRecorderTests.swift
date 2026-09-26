import AVFAudio
import Foundation
import Testing

@testable import Beseda

@Test func recorderLeavesARepairableFileWithoutStop() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-recorder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("me.raw.wav")
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_000)!
    buffer.frameLength = 1_000
    for frame in 0..<1_000 {
        buffer.floatChannelData![0][frame] = 0.25
        buffer.floatChannelData![1][frame] = -0.5
    }
    var recorder: PCMFloatRecorder? = try PCMFloatRecorder(url: url, sampleRate: 48_000, channelCount: 2, activityTracker: nil)

    for _ in 0..<5 {
        try recorder!.append(pcmBuffer: buffer)
    }
    // copy while the recorder is still open: the bytes a crash mid-call leaves on disk
    let crashed = directory.appendingPathComponent("crashed.raw.wav")
    try FileManager.default.copyItem(at: url, to: crashed)
    recorder = nil

    try PCMFloatRecorder.repairWAVHeader(at: crashed)

    let file = try AVAudioFile(forReading: crashed)
    #expect(file.length == 5_000)
    let readBack = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 5_000)!
    try file.read(into: readBack)
    #expect(readBack.floatChannelData![0][4_999] == 0.25)
    #expect(readBack.floatChannelData![1][4_999] == -0.5)
    #expect(try AVAudioFile(forReading: url).length == 5_000)
}
