import AVFAudio
import AVFoundation
import Foundation

enum AudioCaptureError: LocalizedError {
    case unsupportedFormat(String)
    case permissionDenied(String)
    case noFrames(String)
    case audioStatus(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let message), .permissionDenied(let message), .noFrames(let message):
            message
        case .audioStatus(let operation, let status):
            "\(operation) failed with OSStatus \(status) (\(CoreAudioStatus.fourCC(status)))"
        }
    }
}

final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let activityTracker: AudioActivityTracker?
    private var recorder: PCMFloatRecorder?

    init(activityTracker: AudioActivityTracker? = nil) {
        self.activityTracker = activityTracker
    }

    var isPaused: Bool {
        get { recorder?.isPaused ?? false }
        set { recorder?.isPaused = newValue }
    }

    func record(duration: TimeInterval, outputURL: URL) async throws -> AudioFileMetadata {
        try await start(expectedDuration: duration)
        try await Task.sleep(for: .seconds(duration))
        return try stopAndWrite(to: outputURL)
    }

    func start(expectedDuration: TimeInterval) async throws {
        try await requestMicrophonePermission()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.unsupportedFormat("Default microphone returned invalid format: \(format)")
        }

        let recorder = PCMFloatRecorder(
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            expectedDuration: expectedDuration,
            activityTracker: activityTracker
        )
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            do {
                try recorder.append(pcmBuffer: buffer)
            } catch {
                fputs("microphone append failed: \(error)\n", stderr)
            }
        }
        self.recorder = recorder

        engine.prepare()
        try engine.start()
    }

    func stopAndWrite(to url: URL) throws -> AudioFileMetadata {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        guard let recorder else {
            throw AudioCaptureError.noFrames("Microphone recorder was not started")
        }
        return try recorder.writeWAV(to: url)
    }

    func stopDiscarding() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func requestMicrophonePermission() async throws {
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .granted {
            return
        }
        if permission == .denied {
            throw AudioCaptureError.permissionDenied("Microphone permission is denied for Beseda")
        }

        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { value in
                continuation.resume(returning: value)
            }
        }

        if !granted {
            throw AudioCaptureError.permissionDenied("Microphone permission was not granted")
        }
    }
}
