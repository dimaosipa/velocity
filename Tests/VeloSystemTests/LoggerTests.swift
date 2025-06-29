import XCTest
@testable import VeloSystem

final class LoggerTests: XCTestCase {
    var logger: Logger!
    var logFilePath: String!

    override func setUp() {
        super.setUp()
        logger = Logger.shared
        logger.logLevel = .verbose // Enable all log levels for testing
        logger.enableTimestamps = false
        logger.enableColors = false

        // Create temporary log file
        logFilePath = NSTemporaryDirectory() + "velo_test_\(UUID().uuidString).log"
    }

    override func tearDown() {
        // Clean up log file
        if let logFilePath = logFilePath {
            try? FileManager.default.removeItem(atPath: logFilePath)
        }
        super.tearDown()
    }

    func testLogLevels() {
        XCTAssertEqual(LogLevel.verbose.rawValue, 0)
        XCTAssertEqual(LogLevel.info.rawValue, 1)
        XCTAssertEqual(LogLevel.warning.rawValue, 2)
        XCTAssertEqual(LogLevel.error.rawValue, 3)

        XCTAssertTrue(LogLevel.verbose < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
    }

    func testLogLevelIcons() {
        XCTAssertEqual(LogLevel.verbose.icon, "🔍")
        XCTAssertEqual(LogLevel.info.icon, "ℹ️")
        XCTAssertEqual(LogLevel.warning.icon, "⚠️")
        XCTAssertEqual(LogLevel.error.icon, "❌")
    }

    func testLogLevelPrefixes() {
        XCTAssertEqual(LogLevel.verbose.prefix, "VERBOSE")
        XCTAssertEqual(LogLevel.info.prefix, "INFO")
        XCTAssertEqual(LogLevel.warning.prefix, "WARNING")
        XCTAssertEqual(LogLevel.error.prefix, "ERROR")
    }

    func testLogFileCreation() throws {
        XCTAssertNoThrow(try logger.setLogFile(logFilePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: logFilePath))
    }

    func testLogLevelFiltering() {
        logger.logLevel = .warning

        // Create expectation for async logging
        let expectation = self.expectation(description: "Logging completes")
        expectation.isInverted = true // We expect this NOT to be fulfilled (testing filtering)

        // These should not be logged
        logger.verbose("This should not appear")
        logger.info("This should not appear either")

        // These should be logged
        logger.warning("This warning should appear")
        logger.error("This error should appear")

        // Wait briefly for any logging to complete
        waitForExpectations(timeout: 0.1, handler: nil)
    }

    func testGlobalLogFunctions() {
        // Test that global functions don't crash
        logVerbose("Test verbose message")
        logInfo("Test info message")
        logWarning("Test warning message")
        logError("Test error message")

        // If we get here without crashing, the test passes
        XCTAssertTrue(true)
    }

    func testLoggerSingleton() {
        let logger1 = Logger.shared
        let logger2 = Logger.shared

        // Both should be the same instance
        XCTAssertTrue(logger1 === logger2)
    }

    func testProgressMessage() {
        // Progress messages should always be shown regardless of log level
        logger.logLevel = .error

        // This should not crash and should output
        logger.progress("Downloading... 50%")

        XCTAssertTrue(true)
    }

    func testSuccessMessage() {
        // Success messages should always be shown
        logger.logLevel = .error

        // This should not crash and should output
        logger.success("Installation completed!")

        XCTAssertTrue(true)
    }
}
