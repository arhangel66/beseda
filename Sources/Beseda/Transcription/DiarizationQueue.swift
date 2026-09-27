/// Serializes access to the shared diarizer. Interactive work jumps ahead of background work waiting to start.
actor DiarizationQueue {
    enum Priority {
        case user
        case background
    }

    private var isRunning = false
    private var users: [CheckedContinuation<Void, Never>] = []
    private var background: [CheckedContinuation<Void, Never>] = []

    func perform<T: Sendable>(
        priority: Priority,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire(priority)
        do {
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    private func acquire(_ priority: Priority) async {
        guard isRunning else {
            isRunning = true
            return
        }
        await withCheckedContinuation { continuation in
            switch priority {
            case .user: users.append(continuation)
            case .background: background.append(continuation)
            }
        }
    }

    private func release() {
        if !users.isEmpty {
            users.removeFirst().resume()
        } else if !background.isEmpty {
            background.removeFirst().resume()
        } else {
            isRunning = false
        }
    }
}
