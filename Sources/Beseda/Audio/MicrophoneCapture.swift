import AVFAudio
import AVFoundation
import Foundation

enum AudioCaptureError: LocalizedError {
    case unsupportedFormat(String)
    case permissionDenied(String)
    case noFrames(String)
    case fileFull(String)
    case writerBehind(String)
    case audioStatus(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let message), .permissionDenied(let message), .noFrames(let message), .fileFull(let message),
             .writerBehind(let message):
            message
        case .audioStatus(let operation, let status):
            "Ошибка звука: \(operation), OSStatus \(status) (\(CoreAudioStatus.fourCC(status)))"
        }
    }
}

final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let activityTracker: AudioActivityTracker
    private(set) var recorder: PCMFloatRecorder?
    // serializes the restart after a format change with `stop`, so a stopped engine never starts again
    private let lifecycleLock = NSLock()
    private var configurationObserver: (any NSObjectProtocol)?
    private let lastBufferEnd = LastBufferEnd()

    init(activityTracker: AudioActivityTracker) {
        self.activityTracker = activityTracker
    }

    var isPaused: Bool {
        get { recorder?.isPaused ?? false }
        set { recorder?.isPaused = newValue }
    }

    var droppedBufferCount: Int {
        recorder?.droppedBufferCount ?? 0
    }

    func start(writingTo url: URL? = nil) async throws {
        if IsolatedCopy.skips("AVAudioEngine.start (microphone)") {
            throw AudioCaptureError.permissionDenied("Беседе не разрешён доступ к микрофону")
        }
        try await requestMicrophonePermission()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.unsupportedFormat("Микрофон отдаёт звук в неподходящем формате: \(format)")
        }

        let recorder = try PCMFloatRecorder(
            url: url,
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            activityTracker: activityTracker
        )
        installTap(writingTo: recorder)
        self.recorder = recorder
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.restartOnTheNewInputFormat()
        }

        engine.prepare()
        try engine.start()
    }

    func stop() throws -> AudioFileMetadata {
        stopEngine()
        guard let recorder else {
            throw AudioCaptureError.noFrames("Запись микрофона не запустилась")
        }
        return try recorder.finish()
    }

    func stopDiscarding() {
        stopEngine()
    }

    private func stopEngine() {
        lifecycleLock.withLock {
            if let configurationObserver {
                NotificationCenter.default.removeObserver(configurationObserver)
            }
            configurationObserver = nil
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    // the engine stops itself when the input changes format, e.g. AirPods switching to headset mode
    // a moment after a call app takes the microphone; without a restart the call has no "me" channel
    private func restartOnTheNewInputFormat() {
        lifecycleLock.withLock {
            guard configurationObserver != nil, let recorder else {
                return
            }
            engine.inputNode.removeTap(onBus: 0)
            installTap(writingTo: recorder)
            do {
                engine.prepare()
                try engine.start()
            } catch {
                fputs("microphone restart failed: \(error)\n", stderr)
            }
        }
    }

    /// taps the input at the device's current format; a format other than the file's goes through a converter
    private func installTap(writingTo recorder: PCMFloatRecorder) {
        let input = engine.inputNode
        let deviceFormat = input.outputFormat(forBus: 0)
        guard deviceFormat.sampleRate > 0, deviceFormat.channelCount > 0 else {
            fputs("microphone has no input format: \(deviceFormat)\n", stderr)
            return
        }
        let fileFormat = AVAudioFormat(
            standardFormatWithSampleRate: recorder.sampleRate,
            channels: AVAudioChannelCount(recorder.channelCount)
        )!
        let converter = deviceFormat == fileFormat ? nil : AVAudioConverter(from: deviceFormat, to: fileFormat)
        // a tap after a restart starts where the previous one ended, the gap between them becomes silence
        var gapStartHostTime = lastBufferEnd.hostTime
        let lastBufferEnd = lastBufferEnd

        input.installTap(onBus: 0, bufferSize: 4096, format: deviceFormat) { buffer, when in
            if when.isHostTimeValid {
                if let gapStart = gapStartHostTime, when.hostTime > gapStart {
                    recorder.appendSilence(seconds: AVAudioTime.seconds(forHostTime: when.hostTime - gapStart))
                }
                gapStartHostTime = nil
                let duration = Double(buffer.frameLength) / buffer.format.sampleRate
                lastBufferEnd.hostTime = when.hostTime + AVAudioTime.hostTime(forSeconds: duration)
            }
            do {
                if let converter {
                    try recorder.append(pcmBuffer: Self.converted(buffer, with: converter))
                } else {
                    try recorder.append(pcmBuffer: buffer)
                }
            } catch {
                fputs("microphone append failed: \(error)\n", stderr)
            }
        }
    }

    /// allocates per buffer, which only a device that changed format mid-call pays for
    static func converted(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) throws -> AVAudioPCMBuffer {
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity)!
        let feed = OneBufferFeed(buffer)
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            feed.next(status)
        }
        if let conversionError {
            throw conversionError
        }
        return output
    }

    private func requestMicrophonePermission() async throws {
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .granted {
            return
        }
        if permission == .denied {
            throw AudioCaptureError.permissionDenied("Беседе не разрешён доступ к микрофону")
        }

        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { value in
                continuation.resume(returning: value)
            }
        }

        if !granted {
            throw AudioCaptureError.permissionDenied("Доступ к микрофону не выдан")
        }
    }
}

/// where the last tapped buffer ended; written by the tap thread, read when a restart installs the next tap
private final class LastBufferEnd: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64?

    var hostTime: UInt64? {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

/// hands the converter one tap buffer, then reports that nothing more has arrived yet
private final class OneBufferFeed: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        defer { buffer = nil }
        status.pointee = buffer == nil ? .noDataNow : .haveData
        return buffer
    }
}
