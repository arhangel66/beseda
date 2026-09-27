import AVFAudio
import CoreAudio
import Foundation

struct AudioFileMetadata: Codable, Hashable {
    let path: String
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
}

final class PCMFloatRecorder: @unchecked Sendable {
    let sampleRate: Double
    let channelCount: Int
    let url: URL?

    private let lock = NSLock()
    private let activityTracker: AudioActivityTracker?
    private let format: AVAudioFormat
    // samples reach the disk a few milliseconds after the callback; after a crash `repairWAVHeader` makes the file readable
    private var file: AVAudioFile?
    private var frameCount = 0
    private var failedWrites = 0
    private var firstWriteError: (any Error)?
    private let maximumDataBytes: Int

    // the audio callback only copies into this ring and never locks, allocates or touches the disk;
    // `writer` drains it. Counters are monotonic totals: the callback owns `framesQueued`, the writer `framesWritten`
    private let ringFrames: Int
    private let ring: UnsafeMutablePointer<Float>
    private let writeBuffer: AVAudioPCMBuffer
    private let framesQueued = AtomicCounter()
    private let framesWritten = AtomicCounter()
    private let framesDropped = AtomicCounter()
    private let pausedFlag = AtomicCounter()
    private let stopRequested = AtomicCounter()
    private var framesDroppedReported: Int64 = 0
    private var writer: Thread?
    private let writerExited = DispatchSemaphore(value: 0)
    /// how long the writer sleeps when the ring is empty; the ring holds `ringSeconds`, far more
    static let writerPollInterval: TimeInterval = 0.01
    static let ringSeconds: Double = 4
    // AudioFile holds back the tail of a write longer than this until the next one, which a crash would lose
    static let writeChunkFrames = 4_096
    /// only tests set it, to play a disk that cannot keep up
    var writerStall: TimeInterval = 0

    /// a WAV header holds 32-bit sizes: past 4 GiB (~3 h of 48 kHz stereo) the file is unreadable,
    /// so the recorder refuses to grow the data chunk beyond this and leaves room for the header
    static let wavDataLimit = 4_000_000_000

    /// opens `url` for writing and starts its writer thread; nil only meters levels
    init(
        url: URL?,
        sampleRate: Double,
        channelCount: Int,
        activityTracker: AudioActivityTracker?,
        maximumDataBytes: Int = PCMFloatRecorder.wavDataLimit,
        ringFrames: Int? = nil
    ) throws {
        self.url = url
        self.maximumDataBytes = maximumDataBytes
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.activityTracker = activityTracker
        self.ringFrames = ringFrames ?? Int(sampleRate * Self.ringSeconds)
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        )!
        ring = .allocate(capacity: self.ringFrames * channelCount)
        writeBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(self.ringFrames))!
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            file = try AVAudioFile(forWriting: url, settings: format.settings)
        }
        startWriter()
    }

    deinit {
        ring.deallocate()
    }

    /// while paused both channels drop their buffers, so the two files stay aligned
    var isPaused: Bool {
        get { pausedFlag.load() != 0 }
        set { pausedFlag.add((newValue ? 1 : 0) - pausedFlag.load()) }
    }

    /// buffers that did not reach the file, including a ring overflow: the live transcription backs off when this grows
    var droppedBufferCount: Int {
        lock.withLock { failedWrites }
    }

    /// frames the callback threw away because the writer had not freed the ring
    var droppedFrameCount: Int {
        Int(framesDropped.load())
    }

    /// the first write that failed (disk full, the file size limit, the writer falling behind), kept for the user to see
    var writeError: (any Error)? {
        lock.withLock { firstWriteError }
    }

    func append(pcmBuffer: AVAudioPCMBuffer) throws {
        guard !isPaused else {
            return
        }
        guard pcmBuffer.format.commonFormat == .pcmFormatFloat32 else {
            throw AudioCaptureError.unsupportedFormat("Микрофон отдаёт звук не в Float32 PCM: \(pcmBuffer.format)")
        }
        guard let channelData = pcmBuffer.floatChannelData else {
            throw AudioCaptureError.unsupportedFormat("В звуке микрофона нет данных Float32")
        }

        let channels = Int(pcmBuffer.format.channelCount)
        enqueue(frames: Int(pcmBuffer.frameLength)) { frame, channel in
            channel < channels ? channelData[channel][frame] : 0
        }
    }

    func append(audioBufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) throws {
        guard !isPaused else {
            return
        }
        guard format.mFormatID == kAudioFormatLinearPCM else {
            throw AudioCaptureError.unsupportedFormat("Системный звук пришёл не в линейном PCM: \(format)")
        }

        let flags = format.mFormatFlags
        let isFloat = (flags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (flags & kAudioFormatFlagIsSignedInteger) != 0
        let isNonInterleaved = (flags & kAudioFormatFlagIsNonInterleaved) != 0
        let bitsPerChannel = Int(format.mBitsPerChannel)

        guard isFloat || isSignedInteger else {
            throw AudioCaptureError.unsupportedFormat("Системный звук пришёл в неподдерживаемом формате PCM: \(format)")
        }
        guard bitsPerChannel == 32 || bitsPerChannel == 16 else {
            throw AudioCaptureError.unsupportedFormat("Неподдерживаемая разрядность системного звука: \(bitsPerChannel)")
        }

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let channelCount = channelCount

        if isNonInterleaved {
            var frames = buffers.isEmpty ? 0 : Int.max
            for buffer in buffers {
                let bytesPerSample = max(1, bitsPerChannel / 8)
                let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
                frames = min(frames, Int(buffer.mDataByteSize) / bytesPerSample / channelsInBuffer)
            }
            enqueue(frames: frames) { frame, channel in
                guard channel < buffers.count, let data = buffers[channel].mData else {
                    return 0
                }
                return Self.readSample(data: data, index: frame, isFloat: isFloat, bitsPerChannel: bitsPerChannel)
            }
        } else {
            guard let firstBuffer = buffers.first, let data = firstBuffer.mData else {
                return
            }
            let bytesPerFrame = max(1, Int(format.mBytesPerFrame))
            enqueue(frames: Int(firstBuffer.mDataByteSize) / bytesPerFrame) { frame, channel in
                Self.readSample(data: data, index: frame * channelCount + channel, isFloat: isFloat, bitsPerChannel: bitsPerChannel)
            }
        }
    }

    /// stops the writer after it has written everything the callbacks queued, then closes the file
    func finish() throws -> AudioFileMetadata {
        if let writer, !writer.isFinished {
            stopRequested.add(1)
            writerExited.wait()
        }
        let frames = lock.withLock {
            file = nil
            return frameCount
        }
        guard frames > 0 else {
            throw AudioCaptureError.noFrames("Звук не записался: \(url?.path ?? "проверка уровня")")
        }
        return AudioFileMetadata(path: url?.path ?? "", sampleRate: sampleRate, channelCount: channelCount, frameCount: frames)
    }

    /// blocks until the writer has taken everything queued so far; for readers of the growing file in tests
    func waitUntilWritten() {
        while framesWritten.load() < framesQueued.load() {
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    /// the real-time half: copies `frames` interleaved samples into the ring, or counts them dropped when it is full
    @inline(__always)
    private func enqueue(frames: Int, sample: (_ frame: Int, _ channel: Int) -> Float) {
        guard frames > 0 else {
            return
        }
        let queued = framesQueued.load()
        guard Int(queued - framesWritten.load()) + frames <= ringFrames else {
            framesDropped.add(Int64(frames))
            return
        }
        var slot = Int(queued % Int64(ringFrames))
        for frame in 0..<frames {
            let base = slot * channelCount
            for channel in 0..<channelCount {
                ring[base + channel] = sample(frame, channel)
            }
            slot = slot + 1 == ringFrames ? 0 : slot + 1
        }
        framesQueued.add(Int64(frames))
    }

    private func startWriter() {
        // weak: a recorder dropped without `finish` (the level check, a discarded call) ends its thread
        let thread = Thread { [weak self, writerExited] in
            // each step holds the recorder only for its own statement, so the sleep never keeps it alive
            while let drained = self?.drainRing(), self?.isStopRequestedAndEmpty == false {
                if !drained {
                    Thread.sleep(forTimeInterval: Self.writerPollInterval)
                }
            }
            writerExited.signal()
        }
        thread.name = "app.beseda.recorder-writer"
        thread.qualityOfService = .userInitiated
        writer = thread
        thread.start()
    }

    private var isStopRequestedAndEmpty: Bool {
        stopRequested.load() != 0 && framesWritten.load() == framesQueued.load()
    }

    /// the writer half: moves what the ring holds into the file; false when there was nothing to move
    private func drainRing() -> Bool {
        reportOverflow()
        let written = framesWritten.load()
        let available = Int(framesQueued.load() - written)
        guard available > 0 else {
            return false
        }
        if writerStall > 0 {
            Thread.sleep(forTimeInterval: writerStall)
        }
        let start = Int(written % Int64(ringFrames))
        let frames = min(available, ringFrames - start, Self.writeChunkFrames)
        let samples = UnsafeBufferPointer(start: ring + start * channelCount, count: frames * channelCount)
        activityTracker?.observe(samples: Array(samples))
        if url != nil {
            write(interleaved: samples, frames: frames)
        }
        framesWritten.add(Int64(frames))
        return true
    }

    private func reportOverflow() {
        let dropped = framesDropped.load()
        guard dropped > framesDroppedReported else {
            return
        }
        framesDroppedReported = dropped
        record(AudioCaptureError.writerBehind("Запись не успевала на диск: потеряно \(dropped) кадров звука"))
    }

    private func write(interleaved samples: UnsafeBufferPointer<Float>, frames: Int) {
        writeBuffer.frameLength = AVAudioFrameCount(frames)
        let channelData = writeBuffer.floatChannelData!
        for frame in 0..<frames {
            for channel in 0..<channelCount {
                channelData[channel][frame] = samples[frame * channelCount + channel]
            }
        }
        lock.lock()
        let file = file
        let fits = (frameCount + frames) * channelCount * MemoryLayout<Float>.size <= maximumDataBytes
        lock.unlock()
        guard let file else {
            return
        }
        do {
            guard fits else {
                throw AudioCaptureError.fileFull("Запись достигла предела WAV в 4 ГБ")
            }
            try file.write(from: writeBuffer)
            lock.withLock { frameCount += frames }
        } catch {
            // a refused write can take the tail of the previous one with it; count what the file really holds
            lock.withLock { frameCount = min(frameCount, Int(file.length)) }
            record(error)
        }
    }

    private func record(_ error: any Error) {
        fputs("recorder write failed: \(error)\n", stderr)
        lock.withLock {
            failedWrites += 1
            firstWriteError = firstWriteError ?? error
        }
    }

    /// a WAV whose writer died: AudioFile fills in the header sizes only at close, so a killed
    /// recording has all its samples on disk and a header that says zero frames
    static func repairWAVHeader(at url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let fileLength = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let riff = try handle.read(upToCount: 12) ?? Data()
        guard riff.count == 12, riff.prefix(4) == Data("RIFF".utf8), riff.suffix(4) == Data("WAVE".utf8) else {
            throw BesedaError.processFailed("\(url.lastPathComponent): файл не в формате WAV")
        }
        var offset: UInt64 = 12
        while offset + 8 <= fileLength {
            try handle.seek(toOffset: offset)
            let header = try handle.read(upToCount: 8) ?? Data()
            guard header.count == 8 else {
                break
            }
            let chunkSize = header.suffix(4).withUnsafeBytes { UInt64($0.loadUnaligned(as: UInt32.self).littleEndian) }
            if header.prefix(4) == Data("data".utf8) {
                // `wavDataLimit` keeps a live recording under 4 GB, so the sizes fit
                try write(UInt32(clamping: fileLength - offset - 8), at: offset + 4, in: handle)
                try write(UInt32(clamping: fileLength - 8), at: 4, in: handle)
                return
            }
            offset += 8 + chunkSize + chunkSize % 2
        }
        throw BesedaError.processFailed("\(url.lastPathComponent): в файле нет блока со звуком")
    }

    private static func write(_ value: UInt32, at offset: UInt64, in handle: FileHandle) throws {
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: withUnsafeBytes(of: value.littleEndian) { Data($0) })
    }

    private static func readSample(data: UnsafeMutableRawPointer, index: Int, isFloat: Bool, bitsPerChannel: Int) -> Float {
        if isFloat && bitsPerChannel == 32 {
            return data.assumingMemoryBound(to: Float.self)[index]
        }
        if bitsPerChannel == 16 {
            return Float(data.assumingMemoryBound(to: Int16.self)[index]) / Float(Int16.max)
        }
        return 0
    }
}

/// a lock-free Int64 on its own allocation, so the callback and the writer never share a Swift property
private final class AtomicCounter: @unchecked Sendable {
    // ponytail: OSAtomic is deprecated, but Synchronization.Atomic needs macOS 15 and the target is 14.2; swap when it moves
    private let value = UnsafeMutablePointer<Int64>.allocate(capacity: 1)

    init() {
        value.initialize(to: 0)
    }

    deinit {
        value.deallocate()
    }

    func load() -> Int64 {
        OSAtomicAdd64Barrier(0, value)
    }

    func add(_ delta: Int64) {
        OSAtomicAdd64Barrier(delta, value)
    }
}
