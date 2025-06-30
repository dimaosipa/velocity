import Foundation

/// Async/sync bridge for CLI commands
func runAsyncAndWait<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let runLoop = RunLoop.current
    var result: Result<T, Error>?

    let task = Task {
        do {
            let value = try await operation()
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        CFRunLoopStop(runLoop.getCFRunLoop())
    }

    while result == nil && !task.isCancelled {
        runLoop.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }

    if let result = result {
        return try result.get()
    } else {
        task.cancel()
        throw CancellationError()
    }
}
