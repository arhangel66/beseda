import AVFAudio
import Testing

@testable import Beseda

@Test func headsetModeAudioIsConvertedToTheRateTheFileWasOpenedAt() throws {
    // AirPods drop from 48 kHz to 24 kHz when a call app takes the microphone; the open file stays at 48 kHz
    let headset = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    let file = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    let converter = AVAudioConverter(from: headset, to: file)!
    let buffer = AVAudioPCMBuffer(pcmFormat: headset, frameCapacity: 2_400)!
    buffer.frameLength = 2_400
    for frame in 0..<2_400 {
        buffer.floatChannelData![0][frame] = sin(Float(frame) * 0.05)
    }

    var converted = 0
    for _ in 0..<10 {
        converted += Int(try MicrophoneCapture.converted(buffer, with: converter).frameLength)
    }

    #expect(abs(converted - 48_000) < 100)
}
