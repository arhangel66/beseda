import Foundation

// BESEDA-84: `AppMerge <call dir copy>` — `them` count and per-segment keys of one call through the app's own Diarizer and
// SpeakerAssignment (short-reply merge included), on the call's stored ASR. Prints one JSON line, no text.
let call = URL(fileURLWithPath: CommandLine.arguments[1])
let theirs = try JSONDecoder().decode(
    ASRTranscription.self, from: Data(contentsOf: call.appendingPathComponent("them.asr.json"))
).segments
let timeline = try await Diarizer().timeline(for: call.appendingPathComponent("them.asr.wav"))
let turns = SpeakerAssignment.remoteTurns(segments: theirs, timeline: timeline)
// turns: the final key of every ASR segment, so two runs can be compared key by key (BESEDA-120)
print(#"{"call": "\#(call.lastPathComponent)", "diarizer": \#(Set(timeline.map(\.speaker)).count), "them": \#(Set(turns.map(\.speaker)).count), "turns": "\#(turns.map(\.speaker).joined(separator: ","))"}"#)
