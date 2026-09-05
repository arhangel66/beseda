import AVFAudio
import AVFoundation
import CoreAudio
import Foundation

typealias AudioDeviceID = AudioObjectID

enum SpikeError: Error, CustomStringConvertible {
    case argument(String)
    case audioStatus(String, OSStatus)
    case unsupportedFormat(String)
    case permissionDenied(String)
    case noFrames(String)

    var description: String {
        switch self {
        case .argument(let message):
            return message
        case .audioStatus(let operation, let status):
            return "\(operation) failed with OSStatus \(status) (\(fourCC(status)))"
        case .unsupportedFormat(let message):
            return message
        case .permissionDenied(let message):
            return message
        case .noFrames(let message):
            return message
        }
    }
}

struct RecordOptions {
    var duration: TimeInterval = 30
    var outputDir: URL?
    var skipMic = false
    var skipSystem = false
}

struct CaptureMetadata: Encodable {
    let startedAt: String
    let endedAt: String
    let durationSec: Double
    let system: FileMetadata?
    let microphone: FileMetadata?
}

struct FileMetadata: Encodable {
    let path: String
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
}

final class PermissionResult: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ newValue: Bool) {
        lock.withLock {
            value = newValue
        }
    }

    func get() -> Bool {
        lock.withLock {
            value
        }
    }
}

final class PCMFloatRecorder {
    let sampleRate: Double
    let channelCount: Int
    private let lock = NSLock()
    private var samples: [Float] = []

    init(sampleRate: Double, channelCount: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.samples.reserveCapacity(Int(sampleRate) * channelCount * 30)
    }

    var frameCount: Int {
        lock.withLock {
            samples.count / channelCount
        }
    }

    func append(pcmBuffer: AVAudioPCMBuffer) throws {
        guard pcmBuffer.format.commonFormat == .pcmFormatFloat32 else {
            throw SpikeError.unsupportedFormat("Mic buffer is not Float32 PCM: \(pcmBuffer.format)")
        }
        guard let channelData = pcmBuffer.floatChannelData else {
            throw SpikeError.unsupportedFormat("Mic buffer has no Float32 channel data")
        }

        let frames = Int(pcmBuffer.frameLength)
        let channels = Int(pcmBuffer.format.channelCount)
        var chunk = [Float]()
        chunk.reserveCapacity(frames * channels)

        for frame in 0..<frames {
            for channel in 0..<channels {
                chunk.append(channelData[channel][frame])
            }
        }

        lock.withLock {
            samples.append(contentsOf: chunk)
        }
    }

    func append(audioBufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) throws {
        guard format.mFormatID == kAudioFormatLinearPCM else {
            throw SpikeError.unsupportedFormat("System tap format is not linear PCM: \(format)")
        }

        let flags = format.mFormatFlags
        let isFloat = (flags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (flags & kAudioFormatFlagIsSignedInteger) != 0
        let isNonInterleaved = (flags & kAudioFormatFlagIsNonInterleaved) != 0
        let bitsPerChannel = Int(format.mBitsPerChannel)

        guard isFloat || isSignedInteger else {
            throw SpikeError.unsupportedFormat("System tap PCM format is neither float nor signed integer: \(format)")
        }
        guard bitsPerChannel == 32 || bitsPerChannel == 16 else {
            throw SpikeError.unsupportedFormat("Unsupported system tap bit depth: \(bitsPerChannel)")
        }

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        var chunk: [Float] = []

        if isNonInterleaved {
            let frames = buffers.map { buffer -> Int in
                let bytesPerSample = max(1, bitsPerChannel / 8)
                let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
                return Int(buffer.mDataByteSize) / bytesPerSample / channelsInBuffer
            }.min() ?? 0
            chunk.reserveCapacity(frames * channelCount)

            for frame in 0..<frames {
                for channel in 0..<channelCount {
                    guard channel < buffers.count else {
                        chunk.append(0)
                        continue
                    }
                    let buffer = buffers[channel]
                    guard let data = buffer.mData else {
                        chunk.append(0)
                        continue
                    }
                    chunk.append(readSample(data: data, index: frame, isFloat: isFloat, bitsPerChannel: bitsPerChannel))
                }
            }
        } else {
            guard let firstBuffer = buffers.first, let data = firstBuffer.mData else {
                return
            }
            let bytesPerFrame = max(1, Int(format.mBytesPerFrame))
            let frames = Int(firstBuffer.mDataByteSize) / bytesPerFrame
            let sampleCount = frames * channelCount
            chunk.reserveCapacity(sampleCount)

            for index in 0..<sampleCount {
                chunk.append(readSample(data: data, index: index, isFloat: isFloat, bitsPerChannel: bitsPerChannel))
            }
        }

        lock.withLock {
            samples.append(contentsOf: chunk)
        }
    }

    func writeWAV(to url: URL) throws -> FileMetadata {
        let snapshot = lock.withLock {
            samples
        }
        let frames = snapshot.count / channelCount
        guard frames > 0 else {
            throw SpikeError.noFrames("No frames captured for \(url.path)")
        }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)

        guard let channelData = buffer.floatChannelData else {
            throw SpikeError.unsupportedFormat("Could not allocate Float32 output buffer")
        }

        for frame in 0..<frames {
            for channel in 0..<channelCount {
                channelData[channel][frame] = snapshot[frame * channelCount + channel]
            }
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return FileMetadata(path: url.path, sampleRate: sampleRate, channelCount: channelCount, frameCount: frames)
    }

    private func readSample(data: UnsafeMutableRawPointer, index: Int, isFloat: Bool, bitsPerChannel: Int) -> Float {
        if isFloat && bitsPerChannel == 32 {
            return data.assumingMemoryBound(to: Float.self)[index]
        }
        if bitsPerChannel == 16 {
            return Float(data.assumingMemoryBound(to: Int16.self)[index]) / Float(Int16.max)
        }
        return 0
    }
}

final class MicrophoneRecorder {
    private let engine = AVAudioEngine()
    private var recorder: PCMFloatRecorder?

    func start() throws {
        try requestMicrophonePermission()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpikeError.unsupportedFormat("Default microphone returned invalid format: \(format)")
        }

        let recorder = PCMFloatRecorder(sampleRate: format.sampleRate, channelCount: Int(format.channelCount))
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            do {
                try recorder.append(pcmBuffer: buffer)
            } catch {
                fputs("mic append failed: \(error)\n", stderr)
            }
        }
        self.recorder = recorder

        engine.prepare()
        try engine.start()
    }

    func stopAndWrite(to url: URL) throws -> FileMetadata {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        guard let recorder else {
            throw SpikeError.noFrames("Microphone recorder was not started")
        }
        return try recorder.writeWAV(to: url)
    }

    private func requestMicrophonePermission() throws {
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .granted {
            return
        }
        if permission == .denied {
            throw SpikeError.permissionDenied("Microphone permission is denied for this app")
        }

        let semaphore = DispatchSemaphore(value: 0)
        let result = PermissionResult()
        AVAudioApplication.requestRecordPermission { value in
            result.set(value)
            semaphore.signal()
        }
        semaphore.wait()

        if !result.get() {
            throw SpikeError.permissionDenied("Microphone permission was not granted")
        }
    }
}

@available(macOS 14.2, *)
final class SystemTapRecorder {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var recorder: PCMFloatRecorder?
    private var format = AudioStreamBasicDescription()

    func start() throws {
        let excluded = translateCurrentProcessToAudioObject().map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.name = "Podushka Capture Spike"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior(rawValue: 0)!

        try check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")
        format = try getTapFormat(tapID)
        let channelCount = max(1, Int(format.mChannelsPerFrame))
        recorder = PCMFloatRecorder(sampleRate: format.mSampleRate, channelCount: channelCount)

        let tapUID = try getStringProperty(tapID, selector: kAudioTapPropertyUID)
        let aggregateUID = "app.podushka.capture-spike.aggregate.\(UUID().uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Podushka Capture Spike Aggregate",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]

        try check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID),
            "AudioHardwareCreateAggregateDevice"
        )

        guard let recorder else {
            throw SpikeError.noFrames("System recorder was not initialized")
        }

        var localIOProcID: AudioDeviceIOProcID?
        let queue = DispatchQueue(label: "app.podushka.capture-spike.system-tap")
        let block: AudioDeviceIOBlock = { _, inputData, _, _, _ in
            do {
                try recorder.append(audioBufferList: inputData, format: self.format)
            } catch {
                fputs("system append failed: \(error)\n", stderr)
            }
        }

        try check(
            AudioDeviceCreateIOProcIDWithBlock(&localIOProcID, aggregateID, queue, block),
            "AudioDeviceCreateIOProcIDWithBlock"
        )
        ioProcID = localIOProcID
        try check(AudioDeviceStart(aggregateID, ioProcID), "AudioDeviceStart")
    }

    func stopAndWrite(to url: URL) throws -> FileMetadata {
        if aggregateID != kAudioObjectUnknown, let ioProcID {
            _ = AudioDeviceStop(aggregateID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        defer {
            cleanup()
        }
        guard let recorder else {
            throw SpikeError.noFrames("System recorder was not started")
        }
        return try recorder.writeWAV(to: url)
    }

    func cleanup() {
        if aggregateID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            _ = AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        ioProcID = nil
    }
}

func parseArguments(_ args: [String]) throws -> (String, RecordOptions) {
    guard let command = args.first else {
        return ("help", RecordOptions())
    }

    var options = RecordOptions()
    var index = 1
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--duration":
            guard index + 1 < args.count, let duration = TimeInterval(args[index + 1]) else {
                throw SpikeError.argument("--duration requires a number")
            }
            options.duration = duration
            index += 2
        case "--output-dir":
            guard index + 1 < args.count else {
                throw SpikeError.argument("--output-dir requires a path")
            }
            options.outputDir = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            index += 2
        case "--skip-mic":
            options.skipMic = true
            index += 1
        case "--skip-system":
            options.skipSystem = true
            index += 1
        default:
            throw SpikeError.argument("Unknown argument: \(arg)")
        }
    }

    return (command, options)
}

func runRecord(options: RecordOptions) throws {
    guard #available(macOS 14.2, *) else {
        throw SpikeError.unsupportedFormat("Native process taps require macOS 14.2 or newer")
    }

    let fileManager = FileManager.default
    let timestamp = outputTimestamp()
    let outputDir = options.outputDir
        ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("capture-output", isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)
    try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

    let started = Date()
    var systemRecorder: SystemTapRecorder?
    var micRecorder: MicrophoneRecorder?
    var systemMetadata: FileMetadata?
    var micMetadata: FileMetadata?

    do {
        if !options.skipSystem {
            let recorder = SystemTapRecorder()
            try recorder.start()
            systemRecorder = recorder
            print("system tap started")
        }

        if !options.skipMic {
            let recorder = MicrophoneRecorder()
            try recorder.start()
            micRecorder = recorder
            print("microphone started")
        }

        print("recording for \(options.duration)s")
        Thread.sleep(forTimeInterval: options.duration)

        let ended = Date()
        if let systemRecorder {
            systemMetadata = try systemRecorder.stopAndWrite(to: outputDir.appendingPathComponent("system.raw.wav"))
            print("wrote system.raw.wav")
        }
        if let micRecorder {
            micMetadata = try micRecorder.stopAndWrite(to: outputDir.appendingPathComponent("mic.raw.wav"))
            print("wrote mic.raw.wav")
        }

        let metadata = CaptureMetadata(
            startedAt: isoString(started),
            endedAt: isoString(ended),
            durationSec: ended.timeIntervalSince(started),
            system: systemMetadata,
            microphone: micMetadata
        )
        try writeJSON(metadata, to: outputDir.appendingPathComponent("session.json"))
        print("output: \(outputDir.path)")
    } catch {
        systemRecorder?.cleanup()
        throw error
    }
}

func runListDevices() throws {
    let devices = try getAudioDevices()
    let defaultInput = try? getDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
    let defaultOutput = try? getDefaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
    let defaultSystemOutput = try? getDefaultDevice(selector: kAudioHardwarePropertyDefaultSystemOutputDevice)

    print("Audio devices:")
    for device in devices {
        let name = (try? getStringProperty(device, selector: kAudioObjectPropertyName)) ?? "(unknown)"
        let uid = (try? getStringProperty(device, selector: kAudioDevicePropertyDeviceUID)) ?? "(no uid)"
        let markers = [
            device == defaultInput ? "default-input" : nil,
            device == defaultOutput ? "default-output" : nil,
            device == defaultSystemOutput ? "system-output" : nil
        ].compactMap { $0 }.joined(separator: ", ")
        let suffix = markers.isEmpty ? "" : " [\(markers)]"
        print("- \(device): \(name) \(uid)\(suffix)")
    }
}

func printHelp() {
    print("""
    CaptureSpike commands:
      list-devices
      record [--duration seconds] [--output-dir path] [--skip-mic] [--skip-system]
    """)
}

func getAudioDevices() throws -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size), "Get devices size")
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    try devices.withUnsafeMutableBufferPointer { pointer in
        guard let baseAddress = pointer.baseAddress else {
            return
        }
        try check(
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, baseAddress),
            "Get devices"
        )
    }
    return devices
}

func getDefaultDevice(selector: AudioObjectPropertySelector) throws -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var device = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device), "Get default device")
    return device
}

func getStringProperty(
    _ objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
) throws -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    try check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value), "Get string property \(selector)")
    return value?.takeRetainedValue() as String? ?? ""
}

func getTapFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format), "Get tap format")
    return format
}

func translateCurrentProcessToAudioObject() -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var pid = getpid()
    var objectID = AudioObjectID(kAudioObjectUnknown)
    var outputSize = UInt32(MemoryLayout<AudioObjectID>.size)
    let qualifierSize = UInt32(MemoryLayout<pid_t>.size)

    let status = withUnsafePointer(to: &pid) { pidPointer in
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            qualifierSize,
            pidPointer,
            &outputSize,
            &objectID
        )
    }

    guard status == noErr, objectID != kAudioObjectUnknown else {
        return nil
    }
    return objectID
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw SpikeError.audioStatus(operation, status)
    }
}

func fourCC(_ status: OSStatus) -> String {
    let value = UInt32(bitPattern: status)
    let chars = [
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff)
    ]
    if chars.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
        return String(bytes: chars, encoding: .macOSRoman) ?? "\(status)"
    }
    return "\(status)"
}

func isoString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

func outputTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}

func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url)
}

do {
    let (command, options) = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    switch command {
    case "list-devices":
        try runListDevices()
    case "record":
        try runRecord(options: options)
    case "help", "--help", "-h":
        printHelp()
    default:
        throw SpikeError.argument("Unknown command: \(command)")
    }
} catch {
    fputs("CaptureSpike error: \(error)\n", stderr)
    exit(1)
}
