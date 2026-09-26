import Accelerate
import AVFoundation
import Foundation

// BESEDA-95: the echo gate on one archived call (a COPY in a temp dir), mic against system channel.
// before = the gate up to BESEDA-95 (whole sentence text at the longest own-speech run, copied below),
// after = the app's EchoGate.swift (symlink). Prints one JSON line of counts, no text.

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

// the pre-BESEDA-95 EchoGate.ownSpeechSegments, verbatim but for the frame mask passed in
func gateBefore(_ segments: [TranscriptSegment], own: [Bool]) -> [TranscriptSegment] {
    segments.compactMap { segment in
        let first = max(Int(segment.start * 50), 0)
        let last = min(Int((segment.end * 50).rounded(.up)), own.count)
        var longest: Range<Int>?
        var runStart: Int?
        for frame in first...max(first, last) {
            let isOwn = frame < last && own[frame]
            if isOwn, runStart == nil {
                runStart = frame
            } else if !isOwn, let start = runStart {
                if frame - start >= 15, frame - start > longest?.count ?? 0 {
                    longest = start..<frame
                }
                runStart = nil
            }
        }
        guard let longest else { return nil }
        return TranscriptSegment(
            start: Double(longest.lowerBound) / 50, end: Double(longest.upperBound) / 50,
            text: segment.text, confidence: segment.confidence, words: segment.words
        )
    }
}

struct GateCounts: Encodable {
    let keptSentences: Int
    let keptWords: Int
    /// kept "me" words that repeat a system word at the same time (echo shown as "Я")
    let echoKept: Int
    /// dropped mic words, not a system repeat, mic clearly (10 dB) above the predicted echo and the noise floor
    let ownLost: Int
    /// kept sentences whose start or end is > 0.3 s off their words' times
    let boundsOff: Int
}

struct CallReport: Encodable {
    let call: String
    let minutes: Double
    let lagMs: Int
    /// echo level in the mic relative to the system channel, 20·log10(gain)
    let echoDb: Double
    /// share of mic energy the one-delay-one-gain echo model explains (r²)
    let echoFit: Double
    let micFloorDb: Double
    let ownShare: Double
    let systemActiveShare: Double
    /// share of system-active frames the gate calls own speech
    let ownWhileSystemActive: Double
    let micWords: Int
    /// mic words repeating a system word at the same time: how much echo ASR transcribed at all
    let echoWords: Int
    let before: GateCounts
    let after: GateCounts
}

let callDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let mic = try readSamples(at: callDirectory.appendingPathComponent("me.asr.wav"))
let system = try readSamples(at: callDirectory.appendingPathComponent("them.asr.wav"))
let mine = try segments(callDirectory.appendingPathComponent("me.asr.json"))
let theirs = try segments(callDirectory.appendingPathComponent("them.asr.json"))

// the gate's own echo model, recomputed to report it
let frames = mic.count / EchoGate.frameSamples
let lag = EchoGate.echoLag(mic: mic, system: system)
let shifted = [Float](repeating: 0, count: min(lag, mic.count)) + system.prefix(max(mic.count - lag, 0))
let echoSignal = shifted + [Float](repeating: 0, count: mic.count - shifted.count)
let micDot = vDSP.dot(mic, echoSignal)
let echoPower = vDSP.dot(echoSignal, echoSignal) + 1e-12
let gain = micDot / echoPower
let fit = Double(micDot * micDot / (echoPower * (vDSP.dot(mic, mic) + 1e-12)))
func frameEnergies(_ samples: [Float]) -> [Float] {
    (0..<frames).map { vDSP.meanSquare(samples[$0 * EchoGate.frameSamples..<($0 + 1) * EchoGate.frameSamples]) }
}
let micEnergy = frameEnergies(mic)
let echoEnergy = vDSP.multiply(gain * gain, frameEnergies(echoSignal))
let micFloor = micEnergy.sorted()[Int(Double(frames - 1) * 0.1)]
let systemEnergy = frameEnergies(system + [Float](repeating: 0, count: max(mic.count - system.count, 0)))
let systemFloor = systemEnergy.sorted()[Int(Double(frames - 1) * 0.1)]
let own = EchoGate.ownSpeechFrames(mic: mic, system: system)
let systemActive = systemEnergy.map { $0 > 10 * systemFloor }

func normalized(_ text: String) -> String {
    String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
}
struct SystemWord { let text: String, start: Double }
let lagSeconds = Double(lag) / 16_000
let systemWords: [SystemWord] = theirs.flatMap { $0.words ?? [] }
    .map { SystemWord(text: normalized($0.text), start: $0.start + lagSeconds) }
    .filter { $0.text.count >= 2 }
func isSystemRepeat(_ word: TranscriptWord) -> Bool {
    let text = normalized(word.text)
    return text.count >= 2 && systemWords.contains { $0.text == text && abs($0.start - word.start) <= 0.5 }
}
func isClearlyOwn(_ word: TranscriptWord) -> Bool {
    let first = max(Int(word.start * 50), 0)
    let last = min(max(Int((word.end * 50).rounded(.up)), first + 1), frames)
    guard first < last else { return false }
    let range = first..<last
    let micMean = range.map { micEnergy[$0] }.reduce(0, +) / Float(range.count)
    let echoMean = range.map { echoEnergy[$0] }.reduce(0, +) / Float(range.count)
    return micMean > 10 * echoMean && micMean > 10 * micFloor
}
let allWords = mine.flatMap { $0.words ?? [] }

func counts(_ kept: [TranscriptSegment]) -> GateCounts {
    let keptWords = kept.flatMap { $0.words ?? [] }
    let keptSet = Set(keptWords.map { "\($0.start)|\($0.text)" })
    let dropped = allWords.filter { !keptSet.contains("\($0.start)|\($0.text)") }
    return GateCounts(
        keptSentences: kept.count,
        keptWords: keptWords.count,
        echoKept: keptWords.filter(isSystemRepeat).count,
        ownLost: dropped.filter { !isSystemRepeat($0) && isClearlyOwn($0) }.count,
        boundsOff: kept.filter { segment in
            guard let first = segment.words?.first, let last = segment.words?.last else { return false }
            return abs(segment.start - first.start) > 0.3 || abs(segment.end - last.end) > 0.3
        }.count
    )
}

func share(_ flags: [Bool]) -> Double { Double(flags.filter { $0 }.count) / Double(max(flags.count, 1)) }
func rounded(_ value: Double, _ places: Double = 1_000) -> Double { (value * places).rounded() / places }
let report = CallReport(
    call: callDirectory.lastPathComponent,
    minutes: rounded(Double(mic.count) / 16_000 / 60, 10),
    lagMs: lag / 16,
    echoDb: rounded(20 * log10(Double(abs(gain)) + 1e-12), 10),
    echoFit: rounded(fit),
    micFloorDb: rounded(10 * log10(Double(micFloor) + 1e-12), 10),
    ownShare: rounded(share(own)),
    systemActiveShare: rounded(share(systemActive)),
    ownWhileSystemActive: rounded(share(zip(own, systemActive).filter { $0.1 }.map { $0.0 })),
    micWords: allWords.count,
    echoWords: allWords.filter(isSystemRepeat).count,
    before: counts(gateBefore(mine, own: own)),
    after: counts(EchoGate.ownSpeechSegments(mine, mic: mic, system: system))
)
print(String(decoding: try JSONEncoder().encode(report), as: UTF8.self))
