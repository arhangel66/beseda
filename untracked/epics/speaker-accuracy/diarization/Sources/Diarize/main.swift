import AVFoundation
import FluidAudio
import Foundation

// Every diarizer variant on every <id>.system.wav of the eval set. Writes hyp-system/<variant>/<id>.json:
// {"segments": [{"start", "end", "speaker"}], "processing_seconds"} — system channel only; assemble.py
// turns these into full hypotheses.

let evalRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let audioDirectory = evalRoot.appendingPathComponent("data/audio")
let outputRoot = evalRoot.appendingPathComponent("diarization/hyp-system")

struct Turn: Encodable {
    let start: Double
    let end: Double
    let speaker: String
}

struct SystemHypothesis: Encodable {
    let segments: [Turn]
    let processing_seconds: Double
}

func readSamples(at url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

/// number of remote speakers in the reference: the "known speaker count" oracle
func referenceSpeakerCount(_ fileID: String) throws -> Int {
    let url = evalRoot.appendingPathComponent("data/refs/\(fileID).json")
    let reference = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let segments = reference["segments"] as! [[String: Any]]
    return Set(segments.filter { $0["channel"] as! String == "system" }.map { $0["speaker"] as! String }).count
}

func turns(of timeline: DiarizerTimeline) -> [Turn] {
    timeline.speakers.flatMap { index, speaker in
        speaker.finalizedSegments.map { Turn(start: Double($0.startTime), end: Double($0.endTime), speaker: "spk-\(index)") }
    }.sorted { $0.start < $1.start }
}

func offline(_ config: OfflineDiarizerConfig) async throws -> (URL, String) async throws -> [Turn] {
    let manager = OfflineDiarizerManager(config: config)
    try await manager.prepareModels()
    return { url, _ in
        try await manager.process(url).segments.map {
            Turn(start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds), speaker: "spk-\($0.speakerId)")
        }
    }
}

func offlineWithKnownCount(threshold: Double) async throws -> (URL, String) async throws -> [Turn] {
    // a manager per file, since the count is per file: its model load lands in the timing
    return { url, fileID in
        var config = OfflineDiarizerConfig(clusteringThreshold: threshold)
        config.clustering.numSpeakers = try referenceSpeakerCount(fileID)
        let manager = OfflineDiarizerManager(config: config)
        try await manager.prepareModels()
        return try await manager.process(url).segments.map {
            Turn(start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds), speaker: "spk-\($0.speakerId)")
        }
    }
}

func sortformer() async throws -> (URL, String) async throws -> [Turn] {
    let diarizer = SortformerDiarizer(config: .default)
    diarizer.initialize(models: try await SortformerModels.loadFromHuggingFace(config: .default))
    return { url, _ in turns(of: try diarizer.processComplete(try readSamples(at: url), keepingEnrolledSpeakers: false)) }
}

func lseend(_ variant: LSEENDVariant) async throws -> (URL, String) async throws -> [Turn] {
    let diarizer = LSEENDDiarizer()
    try await diarizer.initialize(variant: variant)
    return { url, _ in turns(of: try diarizer.processComplete(try readSamples(at: url), keepingEnrolledSpeakers: false)) }
}

var shortSegments = OfflineDiarizerConfig(clusteringThreshold: 0.7)
shortSegments.embedding.minSegmentDurationSeconds = 0.3

// the model load is kept out of the timings: the app loads once and reuses
let variants: [(String, () async throws -> (URL, String) async throws -> [Turn])] = [
    ("offline-t0.5", { try await offline(OfflineDiarizerConfig(clusteringThreshold: 0.5)) }),
    ("offline-t0.6", { try await offline(OfflineDiarizerConfig(clusteringThreshold: 0.6)) }),
    ("offline-t0.7", { try await offline(OfflineDiarizerConfig(clusteringThreshold: 0.7)) }),
    ("offline-t0.8", { try await offline(OfflineDiarizerConfig(clusteringThreshold: 0.8)) }),
    ("offline-t0.7-minseg0.3", { try await offline(shortSegments) }),
    ("offline-t0.7-known-count", { try await offlineWithKnownCount(threshold: 0.7) }),
    ("sortformer", sortformer),
    ("lseend-dihard3", { try await lseend(.dihard3) }),
    ("lseend-callhome", { try await lseend(.callhome) }),
]
let only = ProcessInfo.processInfo.environment["VARIANTS"]?.split(separator: ",").map(String.init)
let systemFiles = try FileManager.default.contentsOfDirectory(atPath: audioDirectory.path)
    .filter { $0.hasSuffix(".system.wav") }.sorted()

for (name, load) in variants where only?.contains(name) ?? true {
    let diarize = try await load()
    let directory = outputRoot.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for systemFile in systemFiles {
        let fileID = String(systemFile.dropLast(".system.wav".count))
        let started = Date()
        let segments = try await diarize(audioDirectory.appendingPathComponent(systemFile), fileID)
        let elapsed = Date().timeIntervalSince(started)
        try JSONEncoder().encode(SystemHypothesis(segments: segments, processing_seconds: elapsed))
            .write(to: directory.appendingPathComponent("\(fileID).json"))
        print("\(name) \(fileID): \(String(format: "%.2f", elapsed)) s, \(Set(segments.map(\.speaker)).count) speakers")
    }
}
