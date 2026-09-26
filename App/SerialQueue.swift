/// runs jobs one at a time in the order they came; a job added while one runs waits for it
@MainActor
final class SerialQueue<Job> {
    private let run: @MainActor (Job) async -> Void
    private var waiting: [Job] = []
    private var isRunning = false

    init(run: @escaping @MainActor (Job) async -> Void) {
        self.run = run
    }

    /// drops jobs not started yet; the running one is not touched
    func removeWaiting(where shouldRemove: (Job) -> Bool) {
        waiting.removeAll(where: shouldRemove)
    }

    func enqueue(_ job: Job) {
        waiting.append(job)
        guard !isRunning else {
            return
        }
        isRunning = true
        Task {
            while !waiting.isEmpty {
                await run(waiting.removeFirst())
            }
            isRunning = false
        }
    }
}
