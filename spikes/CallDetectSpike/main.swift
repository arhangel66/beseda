// Spike for docs/auto-start-plan.md B1: can a CoreAudio process object tell us a call started?
// Reads identity and the mic flag straight off the process objects, driven by property listeners.
// No audio taps, no aggregate devices — so no TCC permission should be required.
// Listeners do the work; a 2 s sweep only marks (with a star) what the listeners failed to report.

import CoreAudio
import Darwin
import Foundation

// MARK: - property reads

private func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
}

private func processObjectList() -> [AudioObjectID] {
    var address = globalAddress(kAudioHardwarePropertyProcessObjectList)
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

private func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = globalAddress(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
    }
    guard status == noErr, let value else {
        return nil
    }
    return value as String
}

private func pidProperty(_ object: AudioObjectID) -> pid_t {
    var address = globalAddress(kAudioProcessPropertyPID)
    var size = UInt32(MemoryLayout<pid_t>.size)
    var value: pid_t = -1
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
        return -1
    }
    return value
}

private func flagProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
    var address = globalAddress(selector)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
        return false
    }
    return value != 0
}

private func executableName(_ pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    return proc_name(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : "?"
}

// MARK: - watcher

private struct ProcessState {
    let label: String
    let pid: pid_t
    var input: Bool
    var output: Bool
}

private final class MicWatcher {
    // Verified on macOS 26.2: coreaudiod never posts a change for kAudioProcessPropertyIsRunningInput
    // or ...Output — the listener registers with noErr and stays silent forever. The mic flip is
    // announced as kAudioProcessPropertyDevices with scope 'inpt', so we listen to every address of
    // the process object and re-read the two flags ourselves.
    private static let anyProcessProperty = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertySelectorWildcard,
        mScope: kAudioObjectPropertyScopeWildcard,
        mElement: kAudioObjectPropertyElementWildcard
    )

    private let queue = DispatchQueue(label: "app.podushka.call-detect-spike")
    private let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var states: [AudioObjectID: ProcessState] = [:]
    private var flagListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var listListener: AudioObjectPropertyListenerBlock?
    private var sweepTimer: DispatchSourceTimer?

    func start() {
        queue.async {
            for object in processObjectList() {
                self.states[object] = self.read(object)
                self.attachFlagListener(to: object)
            }
            self.printStartupDump()
            self.attachListListener()
            self.startSweep()
        }
    }

    private func read(_ object: AudioObjectID) -> ProcessState {
        let pid = pidProperty(object)
        let bundleID = stringProperty(object, kAudioProcessPropertyBundleID)
        return ProcessState(
            label: (bundleID?.isEmpty == false ? bundleID : nil) ?? executableName(pid),
            pid: pid,
            input: flagProperty(object, kAudioProcessPropertyIsRunningInput),
            output: flagProperty(object, kAudioProcessPropertyIsRunningOutput)
        )
    }

    // MARK: listeners

    private func attachFlagListener(to object: AudioObjectID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.flagsChanged(object)
        }
        flagListeners[object] = block
        var address = Self.anyProcessProperty
        AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
    }

    private func detachFlagListener(from object: AudioObjectID) {
        guard let block = flagListeners.removeValue(forKey: object) else {
            return
        }
        var address = Self.anyProcessProperty
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }

    private func attachListListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.processListChanged()
        }
        listListener = block
        var address = globalAddress(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }

    private func startSweep() {
        // safety net: a process that keeps the device attached flips the flag without notifying anyone,
        // so anything the listeners missed still shows up, marked with a star
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            processListChanged()
            for object in Array(states.keys) {
                flagsChanged(object, missedByListener: true)
            }
        }
        sweepTimer = timer
        timer.resume()
    }

    // MARK: events

    private func flagsChanged(_ object: AudioObjectID, missedByListener: Bool = false) {
        // both flags are re-read on every callback, so an output-only change keeps the mic line honest
        guard var state = states[object] else {
            return
        }
        let input = flagProperty(object, kAudioProcessPropertyIsRunningInput)
        let output = flagProperty(object, kAudioProcessPropertyIsRunningOutput)
        guard input != state.input || output != state.output else {
            return
        }
        let inputChanged = input != state.input
        state.input = input
        state.output = output
        states[object] = state
        // a star means the sweep found it and no listener callback ever arrived
        let star = missedByListener ? "*" : ""

        if inputChanged {
            log((input ? "mic ON" : "mic OFF") + star, state)
        } else if input {
            log("output" + star, state)
        }
    }

    private func processListChanged() {
        // process objects come and go, and per-process listeners die with them
        let current = Set(processObjectList())
        for object in current where states[object] == nil {
            let state = read(object)
            states[object] = state
            attachFlagListener(to: object)
            log(state.input ? "mic ON" : "+ proc", state)
        }
        for (object, state) in states where !current.contains(object) {
            detachFlagListener(from: object)
            states[object] = nil
            log("- proc", state, note: state.input ? "held the mic until it went away" : nil)
        }
    }

    // MARK: output

    private func log(_ event: String, _ state: ProcessState, note: String? = nil) {
        let time = clock.string(from: Date())
        let padded = event.padding(toLength: 8, withPad: " ", startingAt: 0)
        let suffix = note.map { "  <- \($0)" } ?? ""
        print("\(time)  \(padded) \(state.label) (pid \(state.pid))  output=\(state.output ? "on" : "off")\(suffix)")
    }

    private func printStartupDump() {
        let sorted = states.values.sorted { $0.label.lowercased() < $1.label.lowercased() }
        print("=== podushka call-detection spike ===")
        print("\(clock.string(from: Date()))  \(sorted.count) CoreAudio process objects\n")
        for state in sorted {
            let mic = state.input ? "mic ON " : "       "
            print("  \(mic) \(state.label) (pid \(state.pid))  output=\(state.output ? "on" : "off")")
        }
        let holders = sorted.filter(\.input)
        print("\nholding the mic now: \(holders.isEmpty ? "nobody" : holders.map(\.label).joined(separator: ", "))")
        print("watching for changes, Ctrl-C to stop\n")
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
private let watcher = MicWatcher()
watcher.start()
dispatchMain()
