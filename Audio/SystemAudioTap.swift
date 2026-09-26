import CoreAudio
import Foundation

enum CoreAudioStatus {
    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw AudioCaptureError.audioStatus(operation, status)
        }
    }

    static func fourCC(_ status: OSStatus) -> String {
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
}

final class SystemAudioTap: @unchecked Sendable {
    private let activityTracker: AudioActivityTracker?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private(set) var recorder: PCMFloatRecorder?
    private var format = AudioStreamBasicDescription()

    init(activityTracker: AudioActivityTracker? = nil) {
        self.activityTracker = activityTracker
    }

    var isPaused: Bool {
        get { recorder?.isPaused ?? false }
        set { recorder?.isPaused = newValue }
    }

    var droppedBufferCount: Int {
        recorder?.droppedBufferCount ?? 0
    }

    func start(writingTo url: URL? = nil) throws {
        let excludedProcesses = currentProcessAudioObject().map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        description.name = "Beseda System Audio"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior(rawValue: 0)!

        try CoreAudioStatus.check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")
        format = try getTapFormat(tapID)

        let channelCount = max(1, Int(format.mChannelsPerFrame))
        let recorder = try PCMFloatRecorder(
            url: url,
            sampleRate: format.mSampleRate,
            channelCount: channelCount,
            activityTracker: activityTracker
        )
        self.recorder = recorder

        let tapUID = try getStringProperty(tapID, selector: kAudioTapPropertyUID)
        let aggregateUID = "app.beseda.aggregate.\(UUID().uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Beseda System Audio Aggregate",
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

        try CoreAudioStatus.check(
            AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID),
            "AudioHardwareCreateAggregateDevice"
        )

        let streamFormat = format
        let queue = DispatchQueue(label: "app.beseda.system-audio-tap")
        var localIOProcID: AudioDeviceIOProcID?
        let block: AudioDeviceIOBlock = { _, inputData, _, _, _ in
            do {
                try recorder.append(audioBufferList: inputData, format: streamFormat)
            } catch {
                fputs("system audio append failed: \(error)\n", stderr)
            }
        }

        try CoreAudioStatus.check(
            AudioDeviceCreateIOProcIDWithBlock(&localIOProcID, aggregateID, queue, block),
            "AudioDeviceCreateIOProcIDWithBlock"
        )
        ioProcID = localIOProcID
        try CoreAudioStatus.check(AudioDeviceStart(aggregateID, ioProcID), "AudioDeviceStart")
    }

    func stop() throws -> AudioFileMetadata {
        if aggregateID != kAudioObjectUnknown, let ioProcID {
            _ = AudioDeviceStop(aggregateID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        defer {
            cleanup()
        }
        guard let recorder else {
            throw AudioCaptureError.noFrames("Запись системного звука не запустилась")
        }
        return try recorder.finish()
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

    private func getStringProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try CoreAudioStatus.check(
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value),
            "Get string property \(selector)"
        )
        return value?.takeRetainedValue() as String? ?? ""
    }

    private func getTapFormat(_ tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapFormat = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try CoreAudioStatus.check(
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &tapFormat),
            "Get tap format"
        )
        return tapFormat
    }

    private func currentProcessAudioObject() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid = getpid()
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &objectID
        )
        guard status == noErr, objectID != kAudioObjectUnknown else {
            return nil
        }
        return objectID
    }
}
