import AVFoundation
import Foundation
import Testing

@testable import Beseda

/// 16 kHz mono Int16 like the normalized files: noise with a tone every other minute; mic = own tone + echo
private func writeSyntheticCall(hours: Double, into directory: URL) throws -> (mic: URL, system: URL) {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false
    ]
    let micURL = directory.appendingPathComponent("me.wav")
    let systemURL = directory.appendingPathComponent("them.wav")
    let mic = try AVAudioFile(forWriting: micURL, settings: settings)
    let system = try AVAudioFile(forWriting: systemURL, settings: settings)
    let second = AVAudioFrameCount(16_000)
    let micBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: second)!
    let systemBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: second)!
    micBuffer.frameLength = second
    systemBuffer.frameLength = second
    for secondIndex in 0..<Int(hours * 3600) {
        let remoteTalks = (secondIndex / 60) % 2 == 0
        for index in 0..<Int(second) {
            let remote = Float.random(in: -0.01...0.01) + (remoteTalks ? 0.3 * sin(Float(index) * 0.05) : 0)
            systemBuffer.floatChannelData![0][index] = remote
            micBuffer.floatChannelData![0][index] = 0.1 * remote + (remoteTalks ? 0 : 0.3 * sin(Float(index) * 0.2))
        }
        try mic.write(from: micBuffer)
        try system.write(from: systemBuffer)
    }
    return (micURL, systemURL)
}

private func peakResidentMegabytes() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576 // bytes on macOS
}

/// headless measurement, one path per run: BESEDA_LONG_CALL_MEMORY=echo|asr, BESEDA_LONG_CALL_HOURS (default 4)
@Test(.enabled(if: ProcessInfo.processInfo.environment["BESEDA_LONG_CALL_MEMORY"] != nil))
func peakMemoryOnASyntheticLongCall() throws {
    let environment = ProcessInfo.processInfo.environment
    let hours = Double(environment["BESEDA_LONG_CALL_HOURS"] ?? "4")!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let call = try writeSyntheticCall(hours: hours, into: directory)
    let baseline = peakResidentMegabytes()

    switch environment["BESEDA_LONG_CALL_MEMORY"] {
    case "echo":
        let segments = [TranscriptSegment(start: 60, end: 61, text: "me", confidence: 1, words: nil)]
        let kept = try EchoGate.ownSpeechSegments(segments, mic: .file(at: call.mic), system: .file(at: call.system))
        #expect(kept.map(\.text) == ["me"])
    default:
        var pieces = 0
        try UtteranceSplitter.forEachPiece(of: .file(at: call.mic), sampleRate: 16_000, maxSeconds: 120) { _ in pieces += 1 }
        #expect(pieces >= Int(hours * 30))
    }
    print("long call \(hours) h, \(environment["BESEDA_LONG_CALL_MEMORY"]!): peak RSS \(Int(peakResidentMegabytes())) MB, after generating \(Int(baseline)) MB")
}

/// a call of `seconds` that is never stored, remembering the largest window anyone read from it
private final class GeneratedCall {
    var largestRead = 0

    func channel(seconds: Int, delay: Int) -> SampleSource {
        SampleSource(count: seconds * 16_000) { range in
            self.largestRead = max(self.largestRead, range.count)
            return range.map { index in index >= delay ? 0.3 * sin(Float(index - delay) * 0.05) : 0 }
        }
    }
}

private func largestReadOnTheEchoGateAndPiecePaths(seconds: Int) throws -> Int {
    let call = GeneratedCall()
    _ = try EchoGate.ownSpeechFrames(mic: call.channel(seconds: seconds, delay: 960), system: call.channel(seconds: seconds, delay: 0))
    try UtteranceSplitter.forEachPiece(of: call.channel(seconds: seconds, delay: 0), sampleRate: 16_000, maxSeconds: 120) { _ in }
    return call.largestRead
}

@Test func noReadGrowsWithTheLengthOfTheCall() throws {
    let short = try largestReadOnTheEchoGateAndPiecePaths(seconds: 5 * 60)
    let long = try largestReadOnTheEchoGateAndPiecePaths(seconds: 20 * 60)

    #expect(long == short)
    #expect(long == 120 * 16_000 + 1)
}

@Test func piecesReadWindowByWindowFromAFileMatchTheWholeArraySplit() throws {
    // 3 s cycles with a quarter-second hush, so cuts land at different quiet spots
    let samples: [Float] = (0..<(70 * 16_000)).map { index in
        let loudness = index % 48_000 < 4_000 ? 0.001 : 0.5
        return Float(sin(Double(index) * 0.05) * loudness)
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("me.wav")
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = buffer.frameCapacity
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)

    var streamed: [AudioPiece] = []
    try UtteranceSplitter.forEachPiece(of: .file(at: url), sampleRate: 16_000, maxSeconds: 25) { streamed.append($0) }

    #expect(streamed.count > 2)
    let whole = UtteranceSplitter.split(samples, sampleRate: 16_000, maxSeconds: 25)
    #expect(streamed.map(\.offsetSec) == whole.map(\.offsetSec))
    #expect(streamed == whole)
}
