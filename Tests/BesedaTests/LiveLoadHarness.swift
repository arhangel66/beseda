import AVFAudio
import Foundation
import Testing

@testable import Beseda

// Opt-in load run for docs/architecture/live-transcription.md («Load»): a 10-minute synthetic call
// written at real-time pace through `PCMFloatRecorder`, the installed model on the live loop.
// BESEDA_LIVE_LOAD=1 nice -n 19 swift test --jobs 2 --filter liveModeLoadOfATenMinuteCall
private let callSeconds = Int(ProcessInfo.processInfo.environment["BESEDA_LIVE_LOAD_SECONDS"] ?? "") ?? 600

private let microphoneText = """
Привет, давай коротко пройдёмся по планам на неделю. Я закончил перенос базы и хочу завтра выкатить \
новую версию на стенд. Нужно, чтобы кто-то проверил миграции и посмотрел на отчёт по нагрузке. \
Ещё вопрос по бюджету: мы укладываемся, но облачные машины подорожали, и я предлагаю перейти на \
резервированные инстансы до конца квартала. Давай договоримся, что я подготовлю расчёт к пятнице.
"""

private let systemText = """
Sounds good. On my side the design review is done and the mobile team is waiting for the new API. \
I would like to ship the login changes first and keep the payments work for next sprint. \
Can you send me the migration checklist today? I will ask Anna to look at the load report, \
and we can meet again on Thursday to decide about the reserved instances.
"""

@Test(.enabled(if: ProcessInfo.processInfo.environment["BESEDA_LIVE_LOAD"] == "1"
    && SpeechModel.default.isDownloaded(in: AppPaths.current.modelsDirectory)))
func liveModeLoadOfATenMinuteCall() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-load-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let microphoneSpeech = try synthesizedSpeech(microphoneText, voice: "Milena", channelCount: 1, in: directory)
    let systemSpeech = try synthesizedSpeech(systemText, voice: "Samantha", channelCount: 2, in: directory)
    let microphoneURL = directory.appendingPathComponent("me.raw.wav")
    let systemURL = directory.appendingPathComponent("them.raw.wav")
    let microphone = try PCMFloatRecorder(url: microphoneURL, sampleRate: 48_000, channelCount: 1, activityTracker: nil)
    let system = try PCMFloatRecorder(url: systemURL, sampleRate: 48_000, channelCount: 2, activityTracker: nil)
    let transcriber = LocalTranscriber(paths: AppPaths.current)
    _ = try await transcriber.start()
    let stats = LoadStats()
    let keyPointsInstalled = BundledSummary.current.isInstalled(AppPaths.current)
    let llama = await LlamaServer(paths: AppPaths.current)

    let loop = LiveTranscriptionLoop(
        microphoneURL: microphoneURL,
        systemURL: systemURL,
        transcribe: { samples in
            let started = Date()
            let words = try await transcriber.transcribe(samples: samples).segments.flatMap { $0.words ?? [] }
            stats.chunkFinished(seconds: Date().timeIntervalSince(started))
            return words
        },
        droppedBuffers: { stats.droppedBuffers + microphone.droppedBufferCount + system.droppedBufferCount },
        isPaused: { false },
        log: { stats.note($0) },
        update: { lines, recordedSeconds in
            // upper bound: the newest line's start, not its last word, is compared with the recording
            stats.textShown(lagSeconds: recordedSeconds - (lines.map(\.start).max() ?? 0))
            let text = lines.map { "\($0.channel == .microphone ? "Я" : "Собеседник"): \($0.text)" }.joined(separator: "\n")
            guard keyPointsInstalled, stats.startKeyPointsRound(recordedSeconds: recordedSeconds, textLength: text.count) else {
                return
            }
            Task { @MainActor in
                let started = Date()
                do {
                    let provider = ChatCompletionsProvider(
                        baseURL: try await llama.ensureRunning(), model: BundledSummary.current.modelID,
                        prompt: LiveTranscription.keyPointsPrompt, serviceName: "load", timeout: 900
                    )
                    _ = try await provider.summarize(text: text)
                    stats.note("key points in \(Int(Date().timeIntervalSince(started))) s")
                } catch {
                    stats.note("key points failed: \(error.localizedDescription)")
                }
                stats.keyPointsRoundFinished()
            }
        }
    )

    let started = Date()
    let running = Task.detached(priority: .utility) { await loop.run() }
    let sampling = Task.detached { await sampleProcesses(every: 5, into: stats, since: started) }
    for second in 0..<callSeconds {
        stats.append(microphoneSpeech.second(second), to: microphone)
        stats.append(systemSpeech.second(second), to: system)
        try await Task.sleep(until: .now + .seconds(started.addingTimeInterval(Double(second + 1)).timeIntervalSinceNow))
    }
    running.cancel()
    await running.value
    sampling.cancel()
    await sampling.value
    await llama.stop()
    transcriber.shutdown()
    _ = try microphone.finish()
    _ = try system.finish()

    let report = stats.report(callSeconds: callSeconds, keyPointsInstalled: keyPointsInstalled)
    print(report)
    try report.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("beseda-live-load.md"), atomically: true, encoding: .utf8)
    #expect(stats.chunkCount > 0)
}

/// `say` straight to a 48 kHz Float32 file: nothing reaches the Mac's output device
private func synthesizedSpeech(_ text: String, voice: String, channelCount: Int, in directory: URL) throws -> SyntheticChannel {
    let url = directory.appendingPathComponent("\(voice).wav")
    let say = Process()
    say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    say.arguments = ["-v", voice, "-o", url.path, "--file-format=WAVE", "--data-format=LEF32@48000", text]
    try say.run()
    say.waitUntilExit()
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    // two seconds of silence between loops, like a pause before the next turn
    let speech = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))) + [Float](repeating: 0, count: 96_000)
    return SyntheticChannel(samples: speech, channelCount: channelCount)
}

/// one channel of the call, looped: one second at a time as the recorder's buffers
private struct SyntheticChannel {
    let samples: [Float]
    let channelCount: Int

    func second(_ index: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: AVAudioChannelCount(channelCount), interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for frame in 0..<48_000 {
            let sample = samples[(index * 48_000 + frame) % samples.count]
            for channel in 0..<channelCount {
                buffer.floatChannelData![channel][frame] = sample
            }
        }
        return buffer
    }
}

/// `ps` every few seconds for this process and llama-server, until cancelled
private func sampleProcesses(every seconds: Int, into stats: LoadStats, since started: Date) async {
    let pid = ProcessInfo.processInfo.processIdentifier
    while !Task.isCancelled {
        let own = shell("ps -o %cpu=,rss= -p \(pid)").split(separator: " ").compactMap { Double($0) }
        let llama = shell("ps -Ao rss=,comm= | grep llama-server | grep -v grep | awk '{s+=$1} END {print s+0}'")
        if own.count == 2 {
            stats.sample(at: Date().timeIntervalSince(started), cpu: own[0], rssKB: own[1], llamaRSSKB: Double(llama) ?? 0)
        }
        try? await Task.sleep(for: .seconds(seconds))
    }
}

private func shell(_ command: String) -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

private final class LoadStats: @unchecked Sendable {
    private struct Sample {
        let second: Double
        let cpu: Double
        let rssKB: Double
        let llamaRSSKB: Double
    }

    private let lock = NSLock()
    private var samples: [Sample] = []
    private var chunkSeconds: [Double] = []
    private var lags: [Double] = []
    private var notes: [String] = []
    private var dropped = 0
    private var schedule = KeyPointsSchedule()

    var droppedBuffers: Int { lock.withLock { dropped } }
    var chunkCount: Int { lock.withLock { chunkSeconds.count } }

    /// a buffer the recorder refused (wrong format); failed writes are counted by the recorder itself
    func append(_ buffer: AVAudioPCMBuffer, to recorder: PCMFloatRecorder) {
        do {
            try recorder.append(pcmBuffer: buffer)
        } catch {
            lock.withLock { dropped += 1 }
        }
    }

    func chunkFinished(seconds: Double) { lock.withLock { chunkSeconds.append(seconds) } }
    func textShown(lagSeconds: Double) { lock.withLock { lags.append(lagSeconds) } }
    func startKeyPointsRound(recordedSeconds: Double, textLength: Int) -> Bool {
        lock.withLock { schedule.startRound(recordedSeconds: recordedSeconds, textLength: textLength) }
    }

    func keyPointsRoundFinished() { lock.withLock { schedule.roundFinished() } }
    func note(_ message: String) { lock.withLock { notes.append(message) } }

    func sample(at second: Double, cpu: Double, rssKB: Double, llamaRSSKB: Double) {
        lock.withLock { samples.append(Sample(second: second, cpu: cpu, rssKB: rssKB, llamaRSSKB: llamaRSSKB)) }
    }

    func report(callSeconds: Int, keyPointsInstalled: Bool) -> String {
        lock.withLock {
            let cpu = samples.map(\.cpu)
            let slow = chunkSeconds.filter { $0 > LiveBackoff.chunkSeconds }.count
            // both channels, every chunk start 18 s after the previous one
            let possible = 2 * Int((Double(callSeconds) - LiveBackoff.overlapSeconds) / (LiveBackoff.chunkSeconds - LiveBackoff.overlapSeconds))
            func mb(_ kb: Double) -> Int { Int(kb / 1024) }
            return """
            model \(SpeechModel.default.id), call \(callSeconds) s, key points \(keyPointsInstalled ? "on (llama-server)" : "off: built-in model not installed")
            CPU mean \(Int(cpu.reduce(0, +) / Double(max(cpu.count, 1))))% peak \(Int(cpu.max() ?? 0))%
            RSS peak test \(mb(samples.map(\.rssKB).max() ?? 0)) MB, llama-server \(mb(samples.map(\.llamaRSSKB).max() ?? 0)) MB
            chunks \(chunkSeconds.count) of \(possible) possible, skipped \(possible - chunkSeconds.count); \
            chunk time mean \(String(format: "%.2f", chunkSeconds.reduce(0, +) / Double(max(chunkSeconds.count, 1)))) s \
            max \(String(format: "%.2f", chunkSeconds.max() ?? 0)) s vs \(Int(LiveBackoff.chunkSeconds)) s audio
            back-offs (chunk slower than its audio or dropped buffers) \(slow + (dropped > 0 ? 1 : 0)), dropped buffers \(dropped)
            live text lag mean \(Int(lags.reduce(0, +) / Double(max(lags.count, 1)))) s max \(Int(lags.max() ?? 0)) s
            notes: \(notes.joined(separator: "; "))
            samples (s, cpu %, rss MB, llama MB):
            \(samples.map { "\(Int($0.second)) \($0.cpu) \(mb($0.rssKB)) \(mb($0.llamaRSSKB))" }.joined(separator: "\n"))
            """
        }
    }
}
