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

@available(macOS 14.2, *)
final class SystemAudioTap: @unchecked Sendable {
    private let activityTracker: AudioActivityTracker?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var recorder: PCMFloatRecorder?
    private var format = AudioStreamBasicDescription()

    init(activityTracker: AudioActivityTracker? = nil) {
        self.activityTracker = activityTracker
    }

    var isPaused: Bool {
        get { recorder?.isPaused ?? false }
        set { recorder?.isPaused = newValue }
    }

    func start(expectedDuration: TimeInterval) throws {
        let excludedProcesses = translateCurrentProcessToAudioObject().map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        description.name = "Beseda System Audio"
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior(rawValue: 0)!

        try CoreAudioStatus.check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")
        format = try getTapFormat(tapID)

        let channelCount = max(1, Int(format.mChannelsPerFrame))
        let recorder = PCMFloatRecorder(
            sampleRate: format.mSampleRate,
            channelCount: channelCount,
            expectedDuration: expectedDuration,
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

    func stopAndWrite(to url: URL) throws -> AudioFileMetadata {
        if aggregateID != kAudioObjectUnknown, let ioProcID {
            _ = AudioDeviceStop(aggregateID, ioProcID)
            _ = AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        defer {
            cleanup()
        }
        guard let recorder else {
            throw AudioCaptureError.noFrames("System audio recorder was not started")
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

    private func getStringProperty(
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

    private func translateCurrentProcessToAudioObject() -> AudioObjectID? {
        CoreAudioProcessResolver.processObjectID(for: getpid())
    }
}
