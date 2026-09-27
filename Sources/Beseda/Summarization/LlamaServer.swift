import Foundation

/// The downloaded `llama-server` as a child process: started when a summary needs it, stopped
/// ten minutes after the last one. The model takes about 5 GB of memory while it runs, and the
/// app runs from login, so it does not stay loaded.
@MainActor
final class LlamaServer {
    /// same idle window as the speech model, for the same reason
    private static let idleTimeout: TimeInterval = 10 * 60
    private static let port = 8734
    /// the first start after an install compiles Metal shaders, which macOS then caches
    private static let startTimeout: TimeInterval = 300
    /// one summary at a time, so one slot; the whole context goes to it
    private static let contextTokens = 65_536

    static let baseURL = URL(string: "http://127.0.0.1:\(port)/v1")!
    private static let healthURL = URL(string: "http://127.0.0.1:\(port)/health")!

    var log: (String) -> Void = { _ in }

    private let paths: AppPaths
    private let artifacts: BundledSummary
    private var process: Process?
    private var logHandle: FileHandle?
    /// a second caller waits for the start already in flight instead of spawning a rival
    private var starting: Task<URL, Error>?
    private var idleStop: Task<Void, Never>?

    init(paths: AppPaths, artifacts: BundledSummary = .current) {
        self.paths = paths
        self.artifacts = artifacts
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    /// the base URL to send chat completions to, with the server up and answering
    func ensureRunning() async throws -> URL {
        idleStop?.cancel()
        idleStop = nil
        if isRunning {
            return Self.baseURL
        }
        if let starting {
            return try await starting.value
        }
        let task = Task { try await start() }
        starting = task
        defer { starting = nil }
        return try await task.value
    }

    /// the caller is done with the server for now; it goes away on its own if nothing else asks
    func noteIdle() {
        guard isRunning else {
            return
        }
        idleStop?.cancel()
        idleStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.idleTimeout))
            guard !Task.isCancelled else {
                return
            }
            self?.stop()
        }
    }

    func stop() {
        idleStop?.cancel()
        idleStop = nil
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
            log("Summary model unloaded")
        }
        process = nil
        try? logHandle?.close()
        logHandle = nil
    }

    private func spawn() throws -> Process {
        guard artifacts.isInstalled(paths) else {
            throw SummarizationError.modelMissing
        }
        let logURL = artifacts.serverLog(paths)
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        // truncated on every start: the interesting part is why this start failed
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = artifacts.serverExecutable(paths)
        process.arguments = [
            "-m", artifacts.modelFile(paths).path,
            "--host", "127.0.0.1",
            "--port", "\(Self.port)",
            "-c", "\(Self.contextTokens)",
            "-np", "1",
            "-ngl", "99",
            "-fa", "on",
            "--jinja",
            "--no-ui"
        ]
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        self.process = process
        self.logHandle = handle
        return process
    }

    private func start() async throws -> URL {
        let started = Date()
        let process = try spawn()
        do {
            try await waitHealthy(process)
        } catch {
            stop()
            throw error
        }
        log("Summary model ready in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        return Self.baseURL
    }

    private func waitHealthy(_ process: Process) async throws {
        let deadline = Date().addingTimeInterval(Self.startTimeout)
        while Date() < deadline {
            guard process.isRunning else {
                throw SummarizationError.serverDown("Встроенная модель не запустилась. \(logTail())")
            }
            var request = URLRequest(url: Self.healthURL)
            request.timeoutInterval = 2
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        throw SummarizationError.serverDown("Встроенная модель не поднялась за \(Int(Self.startTimeout)) с")
    }

    /// the end of the server log, which is where the reason for a failed start is
    private func logTail(_ limit: Int = 300) -> String {
        let text = (try? String(contentsOf: artifacts.serverLog(paths), encoding: .utf8)) ?? ""
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(limit))
    }
}
