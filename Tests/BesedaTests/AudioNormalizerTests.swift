import AVFAudio
import Foundation
import Testing

@testable import Beseda

/// two seconds of a 440 Hz tone, 48 kHz stereo float: the shape the capture writes
private func writeFixture(to url: URL) throws {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let frames = AVAudioFrameCount(format.sampleRate * 2)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for frame in 0..<Int(frames) {
        let sample = Float(sin(Double(frame) / format.sampleRate * 440 * 2 * .pi)) * 0.5
        buffer.floatChannelData![0][frame] = sample
        buffer.floatChannelData![1][frame] = sample
    }
    try file.write(from: buffer)
}

@Test func normalisingYieldsSixteenKilohertzMonoInt16() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-normalize-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = directory.appendingPathComponent("me.raw.wav")
    try writeFixture(to: input)

    let output = try await AudioNormalizer.normalize(inputURL: input, outputURL: directory.appendingPathComponent("asr/me.asr.wav"))

    let file = try AVAudioFile(forReading: output, commonFormat: .pcmFormatInt16, interleaved: true)
    #expect(file.fileFormat.sampleRate == 16_000)
    #expect(file.fileFormat.channelCount == 1)
    #expect(file.fileFormat.commonFormat == .pcmFormatInt16)
    #expect(abs(Double(file.length) / 16_000 - 2) < 0.02)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    let peak = (0..<Int(buffer.frameLength)).map { abs(buffer.int16ChannelData![0][$0]) }.max() ?? 0
    #expect(peak > 15_000 && peak < 17_500)
}
