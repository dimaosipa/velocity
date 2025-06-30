import Foundation

/// Simple async/sync bridge for CLI commands that works with Swift 5.9 strict concurrency
func runAsyncAndWait<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<T, Error>?

    // Use a detached task to avoid capturing issues
    _ = Task.detached {
        do {
            let value = try await operation()
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }

    semaphore.wait()

    // Since we use detached task, no capture warnings
    return try result!.get()
}
