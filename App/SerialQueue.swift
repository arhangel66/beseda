/// runs jobs one at a time in the order they came; a job added while one runs waits for it
@MainActor
final class SerialQueue<Job> {
    private let run: @MainActor (Job) async -> Void
    private var waiting: [Job] = []
    private var isRunning = false

    init(run: @escaping @MainActor (Job) async -> Void) {
        self.run = run
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
