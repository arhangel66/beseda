import FluidAudio
import Foundation

// go/no-go spike: does FluidAudio split the system-audio channel into a sane number of
// speakers on real call recordings, or does it invent extra ones?

let untrackedDirectory = URL(fileURLWithPath: NSString(string: "~/w/learning/podushka/untracked").expandingTildeInPath)

// every normalized channel under untracked/: call recordings plus anything dropped into
// diarize-samples/ by hand
func normalizedAudioFiles(under directory: URL) -> [URL] {
    let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
    let files = (enumerator?.allObjects as? [URL]) ?? []
    return files
        .filter { $0.lastPathComponent.hasSuffix(".asr.wav") }
        .sorted { $0.path < $1.path }
}

let files = normalizedAudioFiles(under: untrackedDirectory)
guard !files.isEmpty else {
    print("no *.asr.wav under \(untrackedDirectory.path)")
    exit(1)
}

let manager = OfflineDiarizerManager(config: OfflineDiarizerConfig())
let modelsStarted = Date()
try await manager.prepareModels()
print("models ready in \(String(format: "%.1f", Date().timeIntervalSince(modelsStarted)))s\n")

for file in files {
    let call = "\(file.deletingLastPathComponent().lastPathComponent)/\(file.lastPathComponent)"
    let started = Date()
    // a silent channel throws noSpeechDetected, which the app will have to survive
    guard let result = try? await manager.process(file) else {
        print("\(call): no speech detected\n")
        continue
    }
    let elapsed = Date().timeIntervalSince(started)

    let speakers = Set(result.segments.map(\.speakerId)).sorted()
    // FluidAudio reports times as Float; the app works in Double throughout
    let spoken = result.segments.reduce(into: [String: Double]()) { totals, segment in
        totals[segment.speakerId, default: 0] += Double(segment.endTimeSeconds - segment.startTimeSeconds)
    }

    print("\(call): \(speakers.count) speakers, \(result.segments.count) segments, \(String(format: "%.1f", elapsed))s")
    for speaker in speakers {
        print("  \(speaker): \(String(format: "%.1f", spoken[speaker] ?? 0))s")
    }
    let timeline = result.segments.map { segment in
        ["speaker": segment.speakerId, "start": Double(segment.startTimeSeconds), "end": Double(segment.endTimeSeconds)]
            as [String: Any]
    }
    let timelineURL = file.deletingPathExtension().appendingPathExtension("diarization.json")
    try JSONSerialization.data(withJSONObject: timeline, options: [.prettyPrinted]).write(to: timelineURL)

    // only short files get a full timeline printed; a 26-minute call would bury the summary
    if result.segments.count <= 20 {
        for segment in result.segments {
            print(
                "    \(String(format: "%6.2f", Double(segment.startTimeSeconds)))–"
                    + "\(String(format: "%6.2f", Double(segment.endTimeSeconds)))  \(segment.speakerId)"
            )
        }
    }
    print("")
}
