import Foundation

/// One piece of a recording plus where it starts, so word times can be shifted back to
/// absolute time after the piece is transcribed on its own.
struct AudioPiece: Equatable {
    let offsetSec: Double
    let samples: [Float]
}

/// Cuts audio for models trained on a short window. GigaAM keeps decoding past its ~25 s
/// window but silently drops most of the speech, so the caller has to do the windowing —
/// and cutting mid-word costs a word, which is why the cut hunts for the quietest moment.
enum UtteranceSplitter {
    /// the cut is searched in the tail of the window, so a piece is never much shorter than allowed
    private static let searchTailShare = 0.2
    private static let frameSeconds = 0.1
    private static let hopSeconds = 0.01

    static func split(_ samples: [Float], sampleRate: Double, maxSeconds: Double) -> [AudioPiece] {
        let maxSamples = Int(maxSeconds * sampleRate)
        guard maxSamples > 0, samples.count > maxSamples else {
            return [AudioPiece(offsetSec: 0, samples: samples)]
        }

        var pieces: [AudioPiece] = []
        var cursor = 0
        while cursor < samples.count {
            let remaining = samples.count - cursor
            let end = remaining <= maxSamples
                ? samples.count
                : cursor + quietestCut(in: samples, from: cursor, window: maxSamples, sampleRate: sampleRate)
            pieces.append(AudioPiece(
                offsetSec: Double(cursor) / sampleRate,
                samples: Array(samples[cursor..<end])
            ))
            cursor = end
        }
        return pieces
    }

    /// the offset from `start`, inside the window's tail, whose frame is quietest
    private static func quietestCut(in samples: [Float], from start: Int, window: Int, sampleRate: Double) -> Int {
        let frame = Int(frameSeconds * sampleRate)
        let hop = Int(hopSeconds * sampleRate)
        let searchStart = start + Int(Double(window) * (1 - searchTailShare))
        // the cut lands half a frame past the position, so the search has to stop a frame
        // short of the window or the piece comes out longer than the model accepts
        let searchEnd = min(start + window - frame, samples.count - frame)
        guard searchEnd > searchStart else {
            return window
        }

        var bestOffset = window
        var bestEnergy = Double.infinity
        for position in stride(from: searchStart, through: searchEnd, by: hop) {
            var energy = 0.0
            for index in position..<(position + frame) {
                energy += Double(samples[index] * samples[index])
            }
            if energy < bestEnergy {
                bestEnergy = energy
                bestOffset = position + frame / 2 - start
            }
        }
        return bestOffset
    }
}
