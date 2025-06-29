import XCTest
import Foundation

// Shared test utilities to avoid redeclaration errors
extension XCTestCase {
    func XCTAssertNoThrowAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
        } catch {
            XCTFail("Unexpected error thrown: \(error) - \(message())", file: file, line: line)
        }
    }

    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error to be thrown - \(message())", file: file, line: line)
        } catch {
            // Expected
        }
    }

    func measureAsync(
        _ block: @escaping () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            try await block()
        } catch {
            XCTFail("Async measurement block threw error: \(error)", file: file, line: line)
        }

        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("Time elapsed: \(timeElapsed) seconds")
    }

    func measureSync<T>(
        operation: String = "Operation",
        _ block: () throws -> T
    ) rethrows -> (result: T, duration: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        print("\(operation) completed in \(String(format: "%.3f", duration))s")
        return (result, duration)
    }
}
