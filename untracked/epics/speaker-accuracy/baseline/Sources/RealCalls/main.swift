import AVFoundation
import Foundation

// Speaker counts of one archived call (a COPY in a temp dir): old = 0.3.5 per-word labels, no echo gate;
// new = native-ui HEAD per-sentence labels + echo gate. Both reuse the call's stored ASR (unchanged between
// the two) and one diarizer run (same FluidAudio config). Prints one JSON line of counts, no text.

struct CallCounts: Encodable {
    let call: String
    let diarizerSpeakers: Int
    let oldThem: Int
    let newThem: Int
    let oldMe: Bool
    let newMe: Bool
    /// seconds of sentences per new `them-N`, largest first: a tail of tiny speakers points at over-splitting
    let newThemSeconds: [Int]
    let seconds: Double
}

func readSamples(at url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw BesedaError.processFailed("Could not allocate a buffer for \(url.lastPathComponent)")
    }
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

func segments(_ url: URL) throws -> [TranscriptSegment] {
    try JSONDecoder().decode(ASRTranscription.self, from: Data(contentsOf: url)).segments
}

let callDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let started = Date()
let mine = try segments(callDirectory.appendingPathComponent("me.asr.json"))
let theirs = try segments(callDirectory.appendingPathComponent("them.asr.json"))
let systemAudio = callDirectory.appendingPathComponent("them.asr.wav")

let diarizer = Diarizer()
try await diarizer.prepareModels()
let timeline = (try? await diarizer.timeline(for: systemAudio)) ?? []
let oldTurns = SpeakerAssignment.remoteTurns(segments: theirs, timeline: timeline)
let newTurns = SentenceSpeakerAssignment.remoteTurns(segments: theirs, timeline: timeline)
let ownSpeech = EchoGate.ownSpeechSegments(
    mine,
    mic: try readSamples(at: callDirectory.appendingPathComponent("me.asr.wav")),
    system: try readSamples(at: systemAudio)
)

// an empty turn list is the app's single `them` fallback
func themCount(_ turns: [SpeakerTurn]) -> Int {
    turns.isEmpty ? (theirs.isEmpty ? 0 : 1) : Set(turns.map(\.speaker)).count
}

let secondsBySpeaker = Dictionary(grouping: newTurns, by: \.speaker).mapValues { $0.reduce(0) { $0 + $1.end - $1.start } }
let counts = CallCounts(
    call: callDirectory.lastPathComponent,
    diarizerSpeakers: Set(timeline.map(\.speaker)).count,
    oldThem: themCount(oldTurns),
    newThem: themCount(newTurns),
    oldMe: !mine.isEmpty,
    newMe: !ownSpeech.isEmpty,
    newThemSeconds: secondsBySpeaker.values.map { Int($0.rounded()) }.sorted(by: >),
    seconds: Date().timeIntervalSince(started)
)
print(String(decoding: try JSONEncoder().encode(counts), as: UTF8.self))
