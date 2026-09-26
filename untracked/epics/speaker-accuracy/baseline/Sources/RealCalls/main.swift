import Accelerate
import AVFoundation
import FluidAudio
import Foundation

// Speaker counts of one archived call (a COPY in a temp dir): old = 0.3.5 per-word labels, no echo gate;
// new = native-ui HEAD per-sentence labels + echo gate. Both reuse the call's stored ASR (unchanged between
// the two) and one diarizer run (same FluidAudio config). Prints one JSON line of counts, no text.
// BESEDA-69: the same embeddings clustered at several thresholds, and 0.70 with small speakers merged away.
// Given a .wav instead of a call dir, prints each variant's diarizer timeline (the benchmark sweep).

struct CallCounts: Encodable {
    let call: String
    let diarizerSpeakers: Int
    let oldThem: Int
    let newThem: Int
    let oldMe: Bool
    let newMe: Bool
    /// seconds of sentences per new `them-N`, largest first: a tail of tiny speakers points at over-splitting
    let newThemSeconds: [Int]
    /// new-assignment `them` count per diarizer variant
    let themByVariant: [String: Int]
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

struct VariantTimeline: Encodable {
    let variant: String
    let segments: [Turn]
    struct Turn: Encodable { let start: Double, end: Double, speaker: String }
}

// speakers with under `minimumShare` of the speech go to the closest bigger speaker by cosine of their
// mean embeddings; a small speaker with no embedding is dropped
func mergingSmallSpeakers(_ result: DiarizationResult, minimumShare: Double) -> [SpeakerInterval] {
    let seconds = Dictionary(grouping: result.segments, by: \.speakerId)
        .mapValues { $0.reduce(0) { $0 + Double($1.durationSeconds) } }
    let total = seconds.values.reduce(0, +)
    let big = seconds.filter { $0.value >= minimumShare * total }.keys
    func centroid(_ speaker: String) -> [Float]? {
        let vectors = result.segments.filter { $0.speakerId == speaker && !$0.embedding.isEmpty }.map(\.embedding)
        guard let first = vectors.first else { return nil }
        return vectors.dropFirst().reduce(first) { zip($0, $1).map { $0 + $1 } }
    }
    func cosine(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b).map { $0 * $1 }.reduce(0, +) / (sqrt(a.map { $0 * $0 }.reduce(0, +)) * sqrt(b.map { $0 * $0 }.reduce(0, +)))
    }
    let bigCentroids = big.compactMap { speaker in centroid(speaker).map { (speaker, $0) } }
    var target: [String: String] = [:]
    for speaker in seconds.keys {
        if big.contains(speaker) || big.isEmpty {
            target[speaker] = speaker
        } else if let own = centroid(speaker), let nearest = bigCentroids.max(by: { cosine(own, $0.1) < cosine(own, $1.1) }) {
            target[speaker] = nearest.0
        }
    }
    return result.segments.compactMap { segment in
        target[segment.speakerId].map {
            SpeakerInterval(speaker: $0, start: Double(segment.startTimeSeconds), end: Double(segment.endTimeSeconds))
        }
    }
}

func intervals(_ result: DiarizationResult) -> [SpeakerInterval] {
    result.segments.map {
        SpeakerInterval(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
    }
}

// embeddings once, clustering per threshold; the models load once per manager from the local cache
func diarizerVariants(of url: URL) async throws -> [(String, [SpeakerInterval])] {
    var managers: [Double: OfflineDiarizerManager] = [:]
    for threshold in [0.6, 0.7, 0.8, 0.85] {
        managers[threshold] = OfflineDiarizerManager(config: OfflineDiarizerConfig(clusteringThreshold: threshold))
        try await managers[threshold]!.prepareModels()
    }
    let prepared = try await managers[0.7]!.prepare(audio: try AudioConverter().resampleAudioFile(url))
    let current = try managers[0.7]!.cluster(prepared)
    return [
        ("t0.60", intervals(try managers[0.6]!.cluster(prepared))),
        ("t0.70", intervals(current)),
        ("t0.80", intervals(try managers[0.8]!.cluster(prepared))),
        ("t0.85", intervals(try managers[0.85]!.cluster(prepared))),
        ("t0.70-merge2%", mergingSmallSpeakers(current, minimumShare: 0.02)),
        ("t0.70-merge5%", mergingSmallSpeakers(current, minimumShare: 0.05)),
    ]
}

// BESEDA-79: `RealCalls <call dir or wav> dump` prints one JSON line for ../extra_speakers.py: the t0.70 diarizer
// segments with embeddings of the system channel (of a call: also of the mic), the echo gate's own-speech
// intervals and 100 ms RMS levels in dBFS. No audio and no text leave the temp copy.
struct DumpedSegment: Encodable { let start: Float, end: Float, speaker: String, quality: Float, embedding: [Float] }
struct Dump: Encodable {
    let system: [DumpedSegment]
    let system80: [DumpedSegment]
    let mic: [DumpedSegment]
    let ownSpeech: [[Double]]
    let systemDb: [Float]
    let micDb: [Float]
}

func dumpedSegments(_ url: URL, thresholds: [Float] = [0.7]) async throws -> [[DumpedSegment]] {
    // embeddings once, one clustering per threshold (BESEDA-82 adds 0.80)
    let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig(clusteringThreshold: 0.7))
    try await manager.prepareModels()
    let prepared = try await manager.prepare(audio: try AudioConverter().resampleAudioFile(url))
    var clustered: [[DumpedSegment]] = []
    for threshold in thresholds {
        let clusterer = OfflineDiarizerManager(config: OfflineDiarizerConfig(clusteringThreshold: Double(threshold)))
        try await clusterer.prepareModels()
        clustered.append(try clusterer.cluster(prepared).segments.map {
            DumpedSegment(start: $0.startTimeSeconds, end: $0.endTimeSeconds, speaker: $0.speakerId, quality: $0.qualityScore, embedding: $0.embedding)
        })
    }
    return clustered
}

func decibels(_ samples: [Float]) -> [Float] {
    stride(from: 0, to: samples.count - 1_599, by: 1_600).map { 10 * log10(vDSP.meanSquare(samples[$0..<$0 + 1_600]) + 1e-10) }
}

if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "dump" {
    let input = URL(fileURLWithPath: CommandLine.arguments[1])
    let dump: Dump
    if input.pathExtension == "wav" {
        let system = try await dumpedSegments(input, thresholds: [0.7, 0.8])
        dump = Dump(system: system[0], system80: system[1], mic: [], ownSpeech: [], systemDb: decibels(try readSamples(at: input)), micDb: [])
    } else {
        let systemURL = input.appendingPathComponent("them.asr.wav"), micURL = input.appendingPathComponent("me.asr.wav")
        let system = try readSamples(at: systemURL), mic = try readSamples(at: micURL)
        let own = EchoGate.ownSpeechFrames(mic: mic, system: system)
        var runs: [[Double]] = []
        for (frame, isOwn) in own.enumerated() where isOwn {
            if let last = runs.last, last[1] == Double(frame) / 50 { runs[runs.count - 1][1] = Double(frame + 1) / 50 }
            else { runs.append([Double(frame) / 50, Double(frame + 1) / 50]) }
        }
        let clustered = try await dumpedSegments(systemURL, thresholds: [0.7, 0.8])
        dump = Dump(
            system: clustered[0], system80: clustered[1], mic: try await dumpedSegments(micURL)[0],
            ownSpeech: runs, systemDb: decibels(system), micDb: decibels(mic)
        )
    }
    print(String(decoding: try JSONEncoder().encode(dump), as: UTF8.self))
    exit(0)
}

let started = Date()
let argument = URL(fileURLWithPath: CommandLine.arguments[1])
if argument.pathExtension == "wav" {
    for (variant, timeline) in try await diarizerVariants(of: argument) {
        let segments = timeline.map { VariantTimeline.Turn(start: $0.start, end: $0.end, speaker: $0.speaker) }
        print(String(decoding: try JSONEncoder().encode(VariantTimeline(variant: variant, segments: segments)), as: UTF8.self))
    }
    exit(0)
}
let callDirectory = argument
let mine = try segments(callDirectory.appendingPathComponent("me.asr.json"))
let theirs = try segments(callDirectory.appendingPathComponent("them.asr.json"))
let systemAudio = callDirectory.appendingPathComponent("them.asr.wav")

let variants = (try? await diarizerVariants(of: systemAudio)) ?? []
let timeline = variants.first { $0.0 == "t0.70" }?.1 ?? []
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
    themByVariant: Dictionary(uniqueKeysWithValues: variants.map {
        ($0.0, themCount(SentenceSpeakerAssignment.remoteTurns(segments: theirs, timeline: $0.1)))
    }),
    seconds: Date().timeIntervalSince(started)
)
print(String(decoding: try JSONEncoder().encode(counts), as: UTF8.self))
