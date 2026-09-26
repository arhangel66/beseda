import Accelerate
import Foundation

/// the remote side leaking from the speakers into the mic, removed from the mic transcript
/// (measured in docs/decisions/speaker-accuracy.md: echo words transcribed twice 0.678 → 0.013)
enum EchoGate {
    static let frameSamples = 320 // 20 ms at 16 kHz
    static let maxLagSamples = 8_000 // 500 ms
    static let minRunFrames = 15 // 0.3 s
    /// mic energy must beat the predicted echo by 6 dB to count as "me"
    static let echoMargin: Float = 4

    static func ownSpeechSegments(_ segments: [TranscriptSegment], mic: [Float], system: [Float]) -> [TranscriptSegment] {
        // each mic sentence cut down to its longest run of own speech; echo-only sentences are dropped.
        // ASR often glues "me" and echo into one sentence, so a keep/drop per sentence fails.
        let own = ownSpeechFrames(mic: mic, system: system)
        return segments.compactMap { segment in
            let first = max(Int(segment.start * 50), 0)
            let last = min(Int((segment.end * 50).rounded(.up)), own.count)
            var longest: Range<Int>?
            var runStart: Int?
            for frame in first...max(first, last) {
                let isOwn = frame < last && own[frame]
                if isOwn, runStart == nil {
                    runStart = frame
                } else if !isOwn, let start = runStart {
                    if frame - start >= minRunFrames, frame - start > longest?.count ?? 0 {
                        longest = start..<frame
                    }
                    runStart = nil
                }
            }
            guard let longest else {
                return nil
            }
            return TranscriptSegment(
                start: Double(longest.lowerBound) / 50,
                end: Double(longest.upperBound) / 50,
                text: segment.text,
                confidence: segment.confidence,
                words: segment.words
            )
        }
    }

    /// 20 ms frames where the mic carries more than the echo of the system channel predicts
    static func ownSpeechFrames(mic: [Float], system: [Float]) -> [Bool] {
        // ponytail: one delay + one gain fits a pure-delay echo exactly; a real room smears it over
        // ~100 ms, where this needs a max over nearby lags or a real AEC (WebRTC AEC3 / Apple VPIO).
        let frames = mic.count / frameSamples
        guard frames > 0 else {
            return []
        }
        let lag = echoLag(mic: mic, system: system)
        let shifted = [Float](repeating: 0, count: min(lag, mic.count)) + system.prefix(max(mic.count - lag, 0))
        let padded = shifted + [Float](repeating: 0, count: mic.count - shifted.count)
        let gain = vDSP.dot(mic, padded) / (vDSP.dot(padded, padded) + 1e-12)

        let micEnergy = frameEnergies(mic, frames: frames)
        let echoEnergy = vDSP.multiply(gain * gain, frameEnergies(padded, frames: frames))
        let noiseFloor = micEnergy.sorted()[Int(Double(frames - 1) * 0.1)]
        let own = (0..<frames).map { micEnergy[$0] > echoMargin * echoEnergy[$0] && micEnergy[$0] > 10 * noiseFloor }
        // bridge 200 ms gaps inside words
        return (0..<frames).map { frame in own[max(frame - 5, 0)...min(frame + 5, frames - 1)].contains(true) }
    }

    /// delay (samples, 0..500 ms) of the system channel inside the mic, by FFT cross-correlation
    static func echoLag(mic: [Float], system: [Float]) -> Int {
        // ponytail: correlated block by block (8 s) to keep memory flat on hour-long calls; pairs across
        // a block edge are missed, under 1 % at a 60 ms lag. Whole-file FFT if this ever misfits.
        let block = 1 << 17
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
            let micSpectrum = dft.transform(real: padded(mic[offset..<end], to: size), imaginary: zeros)
            let systemSpectrum = dft.transform(real: padded(system[offset..<end], to: size), imaginary: zeros)
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

    private static func padded(_ samples: ArraySlice<Float>, to size: Int) -> [Float] {
        Array(samples) + [Float](repeating: 0, count: size - samples.count)
    }

    private static func frameEnergies(_ samples: [Float], frames: Int) -> [Float] {
        (0..<frames).map { frame in
            vDSP.meanSquare(samples[frame * frameSamples..<(frame + 1) * frameSamples])
        }
    }
}
