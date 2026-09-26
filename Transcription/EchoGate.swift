import Accelerate
import Foundation

/// the remote side leaking from the speakers into the mic, removed from the mic transcript
/// (measured in docs/decisions/speaker-accuracy.md: echo words transcribed twice 0.678 → 0.013)
enum EchoGate {
    static let frameSamples = 320 // 20 ms at 16 kHz
    static let maxLagSamples = 8_000 // 500 ms
    /// mic energy must beat the predicted echo by 6 dB to count as "me"
    static let echoMargin: Float = 4
    /// samples read at once: the lag search's 8 s block, cut to whole frames for the energy pass
    private static let block = 1 << 17
    private static let energyWindow = block / frameSamples * frameSamples

    static func ownSpeechSegments(_ segments: [TranscriptSegment], mic: SampleSource, system: SampleSource) throws -> [TranscriptSegment] {
        // each mic sentence keeps only its words that touch own speech, bounds from those words;
        // ASR often glues "me" and echo into one sentence, so a keep/drop per sentence fails
        let own = try ownSpeechFrames(mic: mic, system: system)
        func isOwn(_ word: TranscriptWord) -> Bool {
            let first = max(Int(word.start * 50), 0)
            let last = min(max(Int((word.end * 50).rounded(.up)), first + 1), own.count)
            return first < last && own[first..<last].contains(true)
        }
        return segments.compactMap { segment in
            let words = segment.words ?? [TranscriptWord(start: segment.start, end: segment.end, text: segment.text)]
            let kept = words.filter(isOwn)
            guard let first = kept.first, let last = kept.last else {
                return nil
            }
            return TranscriptSegment(
                start: first.start,
                end: last.end,
                text: kept.map(\.text).joined(separator: " "),
                confidence: segment.confidence,
                words: segment.words == nil ? nil : kept
            )
        }
    }

    /// 20 ms frames where the mic carries more than the echo of the system channel predicts
    static func ownSpeechFrames(mic: SampleSource, system: SampleSource) throws -> [Bool] {
        // ponytail: one delay + one gain fits a pure-delay echo exactly; a real room smears it over
        // ~100 ms, where this needs a max over nearby lags or a real AEC (WebRTC AEC3 / Apple VPIO).
        let frames = mic.count / frameSamples
        guard frames > 0 else {
            return []
        }
        let lag = try echoLag(mic: mic, system: system)
        // one pass for the gain's dot products and both energies; only per-frame numbers are kept
        var micDotEcho = 0.0
        var echoDotEcho = 0.0
        var micEnergy: [Float] = []
        var unscaledEchoEnergy: [Float] = []
        micEnergy.reserveCapacity(frames)
        unscaledEchoEnergy.reserveCapacity(frames)
        var offset = 0
        while offset < mic.count {
            let range = offset..<min(offset + energyWindow, mic.count)
            let micWindow = try mic.read(range)
            let echoWindow = try delayed(system, by: lag, range)
            micDotEcho += Double(vDSP.dot(micWindow, echoWindow))
            echoDotEcho += Double(vDSP.dot(echoWindow, echoWindow))
            let windowFrames = range.count / frameSamples
            micEnergy += frameEnergies(micWindow, frames: windowFrames)
            unscaledEchoEnergy += frameEnergies(echoWindow, frames: windowFrames)
            offset = range.upperBound
        }
        let gain = Float(micDotEcho / (echoDotEcho + 1e-12))
        let echoEnergy = vDSP.multiply(gain * gain, unscaledEchoEnergy)
        let noiseFloor = micEnergy.sorted()[Int(Double(frames - 1) * 0.1)]
        let own = (0..<frames).map { micEnergy[$0] > echoMargin * echoEnergy[$0] && micEnergy[$0] > 10 * noiseFloor }
        // bridge 200 ms gaps inside words
        return (0..<frames).map { frame in own[max(frame - 5, 0)...min(frame + 5, frames - 1)].contains(true) }
    }

    /// delay (samples, 0..500 ms) of the system channel inside the mic, by FFT cross-correlation
    static func echoLag(mic: SampleSource, system: SampleSource) throws -> Int {
        // ponytail: correlated block by block (8 s) to keep memory flat on hour-long calls; pairs across
        // a block edge are missed, under 1 % at a 60 ms lag. Whole-file FFT if this ever misfits.
        let size = block * 2
        guard let dft = try? vDSP.DiscreteFourierTransform(
            count: size, direction: .forward, transformType: .complexComplex, ofType: Float.self
        ), let inverse = try? vDSP.DiscreteFourierTransform(
            count: size, direction: .inverse, transformType: .complexComplex, ofType: Float.self
        ) else {
            return 0
        }
        let zeros = [Float](repeating: 0, count: size)
        var sumReal = zeros
        var sumImaginary = zeros
        var offset = 0
        while offset < min(mic.count, system.count) {
            let end = min(offset + block, mic.count, system.count)
            let micSpectrum = dft.transform(real: padded(try mic.read(offset..<end), to: size), imaginary: zeros)
            let systemSpectrum = dft.transform(real: padded(try system.read(offset..<end), to: size), imaginary: zeros)
            // mic · conj(system)
            sumReal = vDSP.add(sumReal, vDSP.add(
                vDSP.multiply(micSpectrum.real, systemSpectrum.real),
                vDSP.multiply(micSpectrum.imaginary, systemSpectrum.imaginary)
            ))
            sumImaginary = vDSP.add(sumImaginary, vDSP.subtract(
                vDSP.multiply(micSpectrum.imaginary, systemSpectrum.real),
                vDSP.multiply(micSpectrum.real, systemSpectrum.imaginary)
            ))
            offset = end
        }
        let correlation = inverse.transform(real: sumReal, imaginary: sumImaginary).real
        let magnitudes = vDSP.absolute(correlation[0...maxLagSamples])
        return Int(vDSP.indexOfMaximum(magnitudes).0)
    }

    private static func padded(_ samples: [Float], to size: Int) -> [Float] {
        samples + [Float](repeating: 0, count: size - samples.count)
    }

    /// the system channel as the mic hears it over `range`: `lag` samples late, silent where it has no audio
    private static func delayed(_ system: SampleSource, by lag: Int, _ range: Range<Int>) throws -> [Float] {
        var echo = [Float](repeating: 0, count: range.count)
        let first = max(range.lowerBound - lag, 0)
        let end = min(range.upperBound - lag, system.count)
        if first < end {
            let start = first + lag - range.lowerBound
            echo.replaceSubrange(start..<start + end - first, with: try system.read(first..<end))
        }
        return echo
    }

    private static func frameEnergies(_ samples: [Float], frames: Int) -> [Float] {
        (0..<frames).map { frame in
            vDSP.meanSquare(samples[frame * frameSamples..<(frame + 1) * frameSamples])
        }
    }
}
