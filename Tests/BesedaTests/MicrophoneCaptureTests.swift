import AVFAudio
import Foundation
import Testing

@testable import Beseda

@Test func changingMicrophoneFormatsKeepRecordingSpeechInTheSameWAV() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-mic-\(UUID()).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    let target = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    var converter = MicrophoneFormatConverter(fileFormat: target)
    let recorder = try PCMFloatRecorder(url: url, sampleRate: 48_000, channelCount: 1, activityTracker: nil)
    let formats = [(48_000.0, 1), (24_000, 1), (44_100, 2), (48_000, 1), (24_000, 1)]

    for (sampleRate, channels) in formats {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels))!
        let frames = AVAudioFrameCount(sampleRate / 10)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<channels {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] = sin(Float(frame) * 0.05)
            }
        }
        for _ in 0..<3 {
            let converted = try converter.convert(buffer)
            #expect(converted.format == target)
            try recorder.append(pcmBuffer: converted)
        }
    }
    let metadata = try recorder.finish()

    #expect(metadata.sampleRate == 48_000)
    #expect(metadata.channelCount == 1)
    #expect(abs(metadata.frameCount - 72_000) < 480)
    let audio = try AVAudioFile(forReading: url)
    let samples = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: AVAudioFrameCount(audio.length))!
    try audio.read(into: samples)
    let waveform = UnsafeBufferPointer(start: samples.floatChannelData![0], count: Int(samples.frameLength))
    for (index, _) in formats.enumerated() {
        let middle = index * 14_400 + 7_200
        #expect(waveform[(middle - 100)..<(middle + 100)].contains { abs($0) > 0.5 })
    }
}
