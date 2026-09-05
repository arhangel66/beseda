import CoreAudio
import Foundation

@MainActor
final class CallDetector {
    struct Detection: Equatable, Sendable {
        let bundleID: String
        let appName: String
    }

    static let knownCallApps: [(bundleID: String, name: String)] = [
        ("us.zoom.xos", "Zoom"),
        ("com.microsoft.teams2", "Microsoft Teams"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.tdesktop.Telegram", "Telegram"),
        ("org.telegram.desktop", "Telegram"),
        ("ru.keepcoder.Telegram", "Telegram"),
        ("com.hnc.Discord", "Discord"),
        ("com.apple.FaceTime", "FaceTime"),
        ("ru.yandex.mobile.telemost", "Yandex Telemost"),
        ("com.google.Chrome", "Chrome / Google Meet")
    ]

    static let defaultEnabledBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.tinyspeck.slackmacgap",
        "com.tdesktop.Telegram",
        "org.telegram.desktop",
        "ru.keepcoder.Telegram",
        "com.hnc.Discord",
        "com.apple.FaceTime",
        "ru.yandex.mobile.telemost"
    ]

    var allowedBundleIDs: Set<String>
    /// answers whether the user is recording by hand right now; a manual recording wins over auto-start
    var isManualRecordingActive: () -> Bool = { false }

    var onShouldStart: ((Detection) -> Void)?
    var onShouldStop: (() -> Void)?
    var onDiagnostics: ((String) -> Void)?

    private(set) var isRunning = false
    private var policy = CallRecordingPolicy()
    private var watcher: MicrophoneProcessWatcher?
    private var micHolders: Set<String> = []
    private var evaluationTask: Task<Void, Never>?

    init(allowedBundleIDs: Set<String> = CallDetector.defaultEnabledBundleIDs) {
        self.allowedBundleIDs = allowedBundleIDs
    }

    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        let watcher = MicrophoneProcessWatcher { [weak self] bundleIDs in
            Task { @MainActor in
                self?.micHoldersChanged(bundleIDs)
            }
        }
        self.watcher = watcher
        watcher.start()
    }

    func stop() {
        guard isRunning else {
            return
        }
        isRunning = false
        watcher?.stop()
        watcher = nil
        evaluationTask?.cancel()
        evaluationTask = nil
        micHolders = []
        policy = CallRecordingPolicy()
    }

    /// the auto-recording ended for a reason the microphone flag cannot see (silence auto-stop, manual stop)
    func recordingEnded() {
        policy.recordingEnded(now: Date())
        evaluate()
    }

    static func displayName(for bundleID: String) -> String {
        knownCallApps.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    private func micHoldersChanged(_ bundleIDs: Set<String>) {
        micHolders = bundleIDs
        evaluate()
    }

    private func evaluate() {
        guard isRunning else {
            return
        }
        let holder = allowedMicrophoneHolder()
        let decision = policy.update(
            holder: holder,
            manualRecordingActive: isManualRecordingActive(),
            now: Date()
        )
        switch decision {
        case .start(let detection):
            onDiagnostics?("Auto-detect: \(detection.appName) took the microphone, starting")
            onShouldStart?(detection)
        case .stop:
            onDiagnostics?("Auto-detect: microphone released, stopping")
            onShouldStop?()
        case nil:
            break
        }
        scheduleReevaluation(waiting: holder != nil && !policy.isRecording)
    }

    private func scheduleReevaluation(waiting: Bool) {
        // the debounce and the minimum gap run out on their own; no CoreAudio event will wake us for them
        evaluationTask?.cancel()
        evaluationTask = nil
        guard waiting else {
            return
        }
        evaluationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            self?.evaluate()
        }
    }

    private func allowedMicrophoneHolder() -> Detection? {
        // several allowed apps can hold the microphone at once; pick one the same way every time
        guard let bundleID = micHolders.compactMap(matchingAllowedBundleID).sorted().first else {
            return nil
        }
        return Detection(bundleID: bundleID, appName: Self.displayName(for: bundleID))
    }

    private func matchingAllowedBundleID(for bundleID: String) -> String? {
        for allowed in allowedBundleIDs where bundleID == allowed || bundleID.hasPrefix("\(allowed).") {
            return allowed
        }
        return nil
    }
}

/// Reports which bundle ids hold the microphone, the way the B1 spike proved it works.
private final class MicrophoneProcessWatcher: @unchecked Sendable {
    // Verified on macOS 26.2: coreaudiod never posts a change for kAudioProcessPropertyIsRunningInput —
    // that listener registers with noErr and stays silent forever. The flip is announced as
    // kAudioProcessPropertyDevices, so we listen to every address of the process object and re-read the
    // flag ourselves.
    private static let anyProcessProperty = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertySelectorWildcard,
        mScope: kAudioObjectPropertyScopeWildcard,
        mElement: kAudioObjectPropertyElementWildcard
    )

    private let queue = DispatchQueue(label: "app.podushka.mic-watcher")
    private let onChange: @Sendable (Set<String>) -> Void

    private var inputByObject: [AudioObjectID: Bool] = [:]
    private var listeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var listListener: AudioObjectPropertyListenerBlock?
    private var sweepTimer: DispatchSourceTimer?
    private var reported: Set<String> = []

    init(onChange: @escaping @Sendable (Set<String>) -> Void) {
        self.onChange = onChange
    }

    func start() {
        queue.async {
            self.refreshProcessList()
            self.attachListListener()
            self.startSweep()
            self.publish()
        }
    }

    func stop() {
        queue.async {
            self.sweepTimer?.cancel()
            self.sweepTimer = nil
            self.detachListListener()
            for object in self.inputByObject.keys {
                self.detachListener(from: object)
            }
            self.inputByObject.removeAll()
            self.reported.removeAll()
        }
    }

    private func startSweep() {
        // a process that keeps the device attached and only starts IO flips the flag with no event at all
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            refreshProcessList()
            for object in Array(inputByObject.keys) {
                inputByObject[object] = readIsRunningInput(object)
            }
            publish()
        }
        sweepTimer = timer
        timer.resume()
    }

    private func refreshProcessList() {
        // process objects come and go, and a per-process listener dies with its object
        let current = Set(readProcessObjectList())
        for object in current where inputByObject[object] == nil {
            inputByObject[object] = readIsRunningInput(object)
            attachListener(to: object)
        }
        for object in Array(inputByObject.keys) where !current.contains(object) {
            detachListener(from: object)
            inputByObject[object] = nil
        }
    }

    private func publish() {
        let holders = Set(inputByObject.filter(\.value).keys.compactMap(readBundleID))
        guard holders != reported else {
            return
        }
        reported = holders
        onChange(holders)
    }

    private func attachListener(to object: AudioObjectID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, let previous = inputByObject[object] else {
                return
            }
            let input = readIsRunningInput(object)
            guard input != previous else {
                return
            }
            inputByObject[object] = input
            publish()
        }
        listeners[object] = block
        var address = Self.anyProcessProperty
        AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
    }

    private func detachListener(from object: AudioObjectID) {
        guard let block = listeners.removeValue(forKey: object) else {
            return
        }
        var address = Self.anyProcessProperty
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }

    private func attachListListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else {
                return
            }
            refreshProcessList()
            publish()
        }
        listListener = block
        var address = processListAddress()
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }

    private func detachListListener() {
        guard let block = listListener else {
            return
        }
        listListener = nil
        var address = processListAddress()
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }

    private func processListAddress() -> AudioObjectPropertyAddress {
        globalPropertyAddress(kAudioHardwarePropertyProcessObjectList)
    }
}

private func globalPropertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

private func readProcessObjectList() -> [AudioObjectID] {
    var address = globalPropertyAddress(kAudioHardwarePropertyProcessObjectList)
    let system = AudioObjectID(kAudioObjectSystemObject)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
        return []
    }
    var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard !objects.isEmpty,
          AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else {
        return []
    }
    return objects
}

private func readBundleID(_ object: AudioObjectID) -> String? {
    var address = globalPropertyAddress(kAudioProcessPropertyBundleID)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    guard status == noErr, let value, !(value as String).isEmpty else {
        return nil
    }
    return value as String
}

private func readIsRunningInput(_ object: AudioObjectID) -> Bool {
    var address = globalPropertyAddress(kAudioProcessPropertyIsRunningInput)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
        return false
    }
    return value != 0
}
