import AVFAudio
import Foundation

/// Transcribes the two raw files while the recorder is still writing them, in fixed chunks
/// (`LiveBackoff`). It never touches the capture threads: it only reads what reached the disk.
/// Everything comes in as closures, so a harness can drive it with files it writes itself.
struct LiveTranscriptionLoop: Sendable {
    let microphoneURL: URL
    let systemURL: URL
    /// 16 kHz mono samples in, words with times relative to the chunk out
    let transcribe: @Sendable ([Float]) async throws -> [TranscriptWord]
    let droppedBuffers: @Sendable () -> Int
    let isPaused: @Sendable () -> Bool
    let log: @Sendable (String) -> Void
    /// every line so far and how many seconds of the microphone file are on disk
    let update: @Sendable (_ lines: [LiveLine], _ recordedSeconds: Double) async -> Void

    private struct Channel {
        let kind: TranscriptChannel
        let file: GrowingWAVFile
        var words: [TranscriptWord] = []
        var transcribedUntil = 0.0
    }

    /// runs until its task is cancelled; a chunk in flight finishes first
    func run() async {
        var channels = [
            Channel(kind: .microphone, file: GrowingWAVFile(url: microphoneURL)),
            Channel(kind: .systemAudio, file: GrowingWAVFile(url: systemURL))
        ]
        var backoff = LiveBackoff()
        while !Task.isCancelled {
            var transcribed = false
            for index in channels.indices where !Task.isCancelled && !isPaused() {
                let recorded = channels[index].file.recordedSeconds()
                guard let start = LiveBackoff.nextChunkStart(
                    transcribedUntil: channels[index].transcribedUntil, recordedSeconds: recorded
                ) else {
                    continue
                }
                let started = Date()
                do {
                    let samples = try channels[index].file.samples16k(from: start, seconds: LiveBackoff.chunkSeconds)
                    let words = try await transcribe(samples).map {
                        TranscriptWord(start: $0.start + start, end: $0.end + start, text: $0.text)
                    }
                    channels[index].words = LiveChunkMerge.merge(
                        channels[index].words, chunk: words, chunkStart: start,
                        overlap: max(0, channels[index].transcribedUntil - start)
                    )
                } catch BesedaError.runtimeMissing {
                    // no speech model: every chunk would fail the same way
                    log("Live transcription stopped: \(BesedaError.runtimeMissing.localizedDescription)")
                    return
                } catch {
                    log("Live transcription skipped \(channels[index].kind.rawValue) at \(Int(start))s: \(error.localizedDescription)")
                }
                channels[index].transcribedUntil = start + LiveBackoff.chunkSeconds
                backoff.chunkFinished(
                    wallSeconds: Date().timeIntervalSince(started),
                    audioSeconds: LiveBackoff.chunkSeconds,
                    droppedBuffers: droppedBuffers()
                )
                transcribed = true
                await update(
                    LiveLine.lines(microphone: channels[0].words, system: channels[1].words),
                    channels[0].file.recordedSeconds()
                )
                if backoff.restSeconds > 0 {
                    try? await Task.sleep(for: .seconds(backoff.restSeconds))
                }
            }
            if !transcribed {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// A raw WAV the recorder is still writing: interleaved Float32 whose header says zero frames
/// until close (see `PCMFloatRecorder.repairWAVHeader`), so its length comes from the file size.
final class GrowingWAVFile {
    private struct Layout {
        let dataOffset: UInt64
        let sampleRate: Double
        let channelCount: Int
    }

    let url: URL
    private var layout: Layout?

    init(url: URL) {
        self.url = url
    }

    /// 0 until the recorder has opened the file
    func recordedSeconds() -> Double {
        guard let layout = try? readLayout(),
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64,
              size > layout.dataOffset else {
            return 0
        }
        let frames = (size - layout.dataOffset) / UInt64(layout.channelCount * 4)
        return Double(frames) / layout.sampleRate
    }

    /// `seconds` of audio from `start`, mixed to mono and resampled to 16 kHz the way `AudioNormalizer` does
    func samples16k(from start: Double, seconds: Double) throws -> [Float] {
        let layout = try readLayout()
        let frameBytes = layout.channelCount * 4
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: layout.dataOffset + UInt64(start * layout.sampleRate) * UInt64(frameBytes))
        let bytes = try handle.read(upToCount: Int(seconds * layout.sampleRate) * frameBytes) ?? Data()
        let frames = bytes.count / frameBytes

        guard let source = AVAudioFormat(standardFormatWithSampleRate: layout.sampleRate, channels: 1),
              let target = AVAudioFormat(standardFormatWithSampleRate: AudioNormalizer.sampleRate, channels: 1),
              let converter = AVAudioConverter(from: source, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(max(frames, 1))),
              let output = AVAudioPCMBuffer(
                  pcmFormat: target,
                  frameCapacity: AVAudioFrameCount(Double(frames) * target.sampleRate / source.sampleRate) + 64
              ) else {
            throw BesedaError.processFailed("Не получилось перевести \(url.lastPathComponent) в 16 кГц моно")
        }
        bytes.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Float.self)
            let mono = input.floatChannelData![0]
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<layout.channelCount {
                    sum += samples[frame * layout.channelCount + channel]
                }
                mono[frame] = sum / Float(layout.channelCount)
            }
        }
        input.frameLength = AVAudioFrameCount(frames)

        let feed = OneShotFeed(buffer: input)
        var converted: [Float] = []
        var status = AVAudioConverterOutputStatus.haveData
        while status == .haveData {
            var convertError: NSError?
            status = converter.convert(to: output, error: &convertError) { _, outStatus in
                feed.next(outStatus)
            }
            if let convertError {
                throw convertError
            }
            converted += UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))
        }
        return converted
    }

    /// the header is written when the recorder opens the file and never moves after that
    private func readLayout() throws -> Layout {
        if let layout {
            return layout
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 8192) ?? Data()
        var offset = 12
        var format: (sampleRate: Double, channels: Int)?
        while offset + 8 <= header.count {
            let id = header.subdata(in: offset..<offset + 4)
            let size = Int(header.loadUInt32(at: offset + 4))
            if id == Data("fmt ".utf8), offset + 24 <= header.count {
                guard header.loadUInt16(at: offset + 22) == 32 else {
                    throw BesedaError.processFailed("\(url.lastPathComponent) не в формате Float32")
                }
                format = (Double(header.loadUInt32(at: offset + 12)), Int(header.loadUInt16(at: offset + 10)))
            }
            if id == Data("data".utf8), let format, format.channels > 0, format.sampleRate > 0 {
                let layout = Layout(dataOffset: UInt64(offset + 8), sampleRate: format.sampleRate, channelCount: format.channels)
                self.layout = layout
                return layout
            }
            offset += 8 + size + size % 2
        }
        throw BesedaError.processFailed("В \(url.lastPathComponent) пока нет звука")
    }
}

/// hands the converter one buffer, then the end of the stream; runs on the converting thread
private final class OneShotFeed: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        guard let buffer else {
            outStatus.pointee = .endOfStream
            return nil
        }
        self.buffer = nil
        outStatus.pointee = .haveData
        return buffer
    }
}

private extension Data {
    func loadUInt32(at offset: Int) -> UInt32 {
        subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    }

    func loadUInt16(at offset: Int) -> UInt16 {
        subdata(in: offset..<offset + 2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).littleEndian }
    }
}
