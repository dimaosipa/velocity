import Foundation

/// Thread-safe async/sync bridge using Foundation synchronization primitives
func runAsyncAndWait<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let condition = NSCondition()
    var result: Result<T, Error>?

    Task.detached {
        let taskResult: Result<T, Error>
        do {
            let value = try await operation()
            taskResult = .success(value)
        } catch {
            taskResult = .failure(error)
        }

        // Use DispatchQueue.sync to avoid async context warnings
        DispatchQueue.global().sync {
            condition.lock()
            result = taskResult
            condition.signal()
            condition.unlock()
        }
    }

    condition.lock()
    while result == nil {
        condition.wait()
    }
    condition.unlock()

    return try result!.get()
}
