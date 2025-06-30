import Foundation

/// Thread-safe result container for async/sync bridging
private final class AsyncResultBox<T> {
    private var result: Result<T, Error>?
    private let condition = NSCondition()

    func setResult(_ result: Result<T, Error>) {
        condition.lock()
        self.result = result
        condition.signal()
        condition.unlock()
    }

    func waitForResult() -> Result<T, Error> {
        condition.lock()
        while result == nil {
            condition.wait()
        }
        let finalResult = result!
        condition.unlock()
        return finalResult
    }
}

/// Thread-safe async/sync bridge using atomic reference and condition variable
func runAsyncAndWait<T>(_ operation: @escaping () async throws -> T) throws -> T {
    let resultBox = AsyncResultBox<T>()

    Task.detached {
        let taskResult: Result<T, Error>
        do {
            let value = try await operation()
            taskResult = .success(value)
        } catch {
            taskResult = .failure(error)
        }

        resultBox.setResult(taskResult)
    }

    return try resultBox.waitForResult().get()
}
