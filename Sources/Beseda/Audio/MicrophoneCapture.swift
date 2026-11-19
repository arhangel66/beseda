import AVFAudio
import AVFoundation
import Foundation
import OSLog

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
    private let activityTracker: AudioActivityTracker
    private let lifecycle = DispatchQueue(label: "app.beseda.microphone", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var activeRecorder: PCMFloatRecorder?
    private var configurationObserver: (any NSObjectProtocol)?
    private var inputCheck: DispatchSourceTimer?
    private var engineGeneration = 0
    private var lastEngineStart: UInt64 = 0
    private let lastBufferEnd = LastBufferEnd()
    private let logger = Logger(subsystem: "app.beseda.Beseda", category: "microphone")

    init(activityTracker: AudioActivityTracker) {
        self.activityTracker = activityTracker
    }

    var recorder: PCMFloatRecorder? {
        lifecycle.sync { activeRecorder }
    }

    var isPaused: Bool {
        get { recorder?.isPaused ?? false }
        set { recorder?.isPaused = newValue }
    }

    var droppedBufferCount: Int {
        recorder?.droppedBufferCount ?? 0
    }

    var inputMissing: Bool {
        lastBufferEnd.hostTime.map { Self.inputTimedOut(since: $0) } ?? false
    }

    func start(writingTo url: URL? = nil) async throws {
        if IsolatedCopy.skips("AVAudioEngine.start (microphone)") {
            throw AudioCaptureError.permissionDenied("Беседе не разрешён доступ к микрофону")
        }
        try await requestMicrophonePermission()

        try lifecycle.sync {
            let recorder = try PCMFloatRecorder(
                url: url, sampleRate: 48_000, channelCount: 1, activityTracker: activityTracker
            )
            lastBufferEnd.hostTime = mach_absolute_time()
            activeRecorder = recorder
            openInput(writingTo: recorder)
            let timer = DispatchSource.makeTimerSource(queue: lifecycle)
            timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
            timer.setEventHandler { [weak self] in self?.checkInput() }
            inputCheck = timer
            timer.resume()
        }
    }

    func stop() throws -> AudioFileMetadata {
        guard let recorder = lifecycle.sync(execute: endCapture) else {
            throw AudioCaptureError.noFrames("Запись микрофона не запустилась")
        }
        return try recorder.finish()
    }

    func stopDiscarding() {
        _ = lifecycle.sync(execute: endCapture)
    }

    private func endCapture() -> PCMFloatRecorder? {
        inputCheck?.cancel()
        inputCheck = nil
        stopEngine()
        lastBufferEnd.hostTime = nil
        let recorder = activeRecorder
        activeRecorder = nil
        return recorder
    }

    private func stopEngine() {
        engineGeneration += 1
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private func openInput(writingTo recorder: PCMFloatRecorder) {
        // Use a fresh engine so it cannot carry over a connection in the previous hardware format.
        lastEngineStart = mach_absolute_time()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            logger.error("Microphone input is unavailable: \(format, privacy: .public)")
            return
        }
        installTap(on: input, writingTo: recorder)
        self.engine = engine
        let generation = engineGeneration
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            // AVAudioEngine sends this on a framework queue that must return before teardown.
            self?.lifecycle.async { [weak self] in
                guard let self, self.engineGeneration == generation else { return }
                self.reopenInput()
            }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            stopEngine()
            logger.error("Microphone start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func checkInput() {
        guard activeRecorder != nil else { return }
        let lastInput = max(lastEngineStart, lastBufferEnd.hostTime ?? 0)
        // A format change can leave a running engine with no tap callbacks, even for silent samples.
        if Self.inputTimedOut(since: lastInput) {
            logger.warning("No microphone buffers for 1.5 seconds, reopening input")
            reopenInput()
        }
    }

    private static func inputTimedOut(since latestBuffer: UInt64) -> Bool {
        let now = mach_absolute_time()
        return now > latestBuffer && AVAudioTime.seconds(forHostTime: now - latestBuffer) >= 1.5
    }

    private func reopenInput() {
        guard let recorder = activeRecorder else { return }
        stopEngine()
        openInput(writingTo: recorder)
    }

    private func installTap(on input: AVAudioInputNode, writingTo recorder: PCMFloatRecorder) {
        // Each tap converts its actual buffers to the WAV format and keeps their time on the call timeline.
        let fileFormat = AVAudioFormat(
            standardFormatWithSampleRate: recorder.sampleRate,
            channels: AVAudioChannelCount(recorder.channelCount)
        )!
        var formatConverter = MicrophoneFormatConverter(fileFormat: fileFormat)
        let lastBufferEnd = lastBufferEnd
        let logger = logger
        var gapStart = lastBufferEnd.hostTime
        var receivedFirstBuffer = false

        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, when in
            do {
                let converted = try formatConverter.convert(buffer)
                if when.isHostTimeValid {
                    if let gapStart, when.hostTime > gapStart {
                        recorder.appendSilence(seconds: AVAudioTime.seconds(forHostTime: when.hostTime - gapStart))
                    }
                    let duration = Double(buffer.frameLength) / buffer.format.sampleRate
                    lastBufferEnd.hostTime = when.hostTime + AVAudioTime.hostTime(forSeconds: duration)
                } else {
                    lastBufferEnd.hostTime = mach_absolute_time()
                }
                gapStart = nil
                try recorder.append(pcmBuffer: converted)
                if !receivedFirstBuffer {
                    logger.info("Recording microphone buffers at \(buffer.format.sampleRate, privacy: .public) Hz")
                    receivedFirstBuffer = true
                }
            } catch {
                logger.error("Microphone buffer rejected: \(error.localizedDescription, privacy: .public)")
            }
        }
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

struct MicrophoneFormatConverter {
    private let fileFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(fileFormat: AVAudioFormat) {
        self.fileFormat = fileFormat
    }

    mutating func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        // Use the tap buffer's format, which can differ from the engine's reported format during a transition.
        if buffer.format == fileFormat {
            converter = nil
            return buffer
        }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: fileFormat)
            converter?.primeMethod = .none
        }
        guard let converter else {
            throw AudioCaptureError.unsupportedFormat("Не удалось преобразовать звук микрофона: \(buffer.format)")
        }

        let ratio = fileFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        let output = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: capacity)!
        let feed = OneBufferFeed(buffer)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            feed.next(status)
        }
        if let error {
            throw error
        }
        return output
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
