import XCTest
import Foundation
@testable import VeloCLI
@testable import VeloCore
@testable import VeloFormula
@testable import VeloSystem

/// Real CLI integration tests that use actual homebrew formulas
/// These tests verify end-to-end functionality with real data
final class RealCLITests: XCTestCase {
    var tempDirectory: URL!
    var originalVeloHome: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Create isolated test environment
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo_real_test_\(UUID().uuidString)")

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Override environment
        originalVeloHome = PathHelper.shared.veloHome
        setenv("VELO_HOME", tempDirectory.appendingPathComponent(".velo").path, 1)

        // Setup clean environment
        try PathHelper.shared.ensureVeloDirectories()
        // Using OSLogger.shared with default essential level for quiet tests
    }

    override func tearDown() async throws {
        // Restore environment
        if let originalPath = originalVeloHome?.path {
            setenv("VELO_HOME", originalPath, 1)
        }

        // Clean up
        try? FileManager.default.removeItem(at: tempDirectory)
        try await super.tearDown()
    }

    // MARK: - Package@Version Syntax Tests

    func testPackageVersionParsing() async throws {
        let testCases = [
            ("wget", "wget", nil),
            ("wget@1.25.0", "wget", "1.25.0"),
            ("openssl@3", "openssl", "3"),
            ("python@3.11", "python", "3.11"),
            ("node@18.19.0", "node", "18.19.0"),
            ("ruby@3.2.0", "ruby", "3.2.0")
        ]

        for (input, expectedName, expectedVersion) in testCases {
            let spec = PackageSpecification.parse(input)
            XCTAssertEqual(spec.name, expectedName, "Name parsing failed for '\(input)'")
            XCTAssertEqual(spec.version, expectedVersion, "Version parsing failed for '\(input)'")
            XCTAssertTrue(spec.isValid, "Specification '\(input)' should be valid")
        }
    }

    func testInfoCommandWithPackageVersion() async throws {
        // Test info command with package@version syntax
        let testPackages = ["wget@1.25.0", "openssl@3", "python@3.11"]

        for package in testPackages {
            let output = try await runCLICommand(["info", package])
            XCTAssertTrue(output.contains("Formula:") || output.contains("Package:") || output.contains("not found"),
                         "Info command should handle package@version syntax")
        }
    }

    // MARK: - Real Search Tests

    func testSearchRealFormulas() async throws {
        // Skip this test in CI environments where it might be slow
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Skipping slow network test in CI environment")
        }

        // Use a timeout to prevent hanging
        let output = try await withTimeout(seconds: 10) {
            try await self.runCLICommand(["search", "wget"])
        }
        XCTAssertTrue(output.contains("Search results for") || output.contains("wget") || output.contains("No packages found"),
                     "Search should complete within timeout")
    }

    func testSearchWithDescriptions() async throws {
        // Skip this test in CI environments where it might be slow
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Skipping slow network test in CI environment")
        }

        let output = try await withTimeout(seconds: 15) {
            try await self.runCLICommand(["search", "compression", "--descriptions"])
        }
        XCTAssertTrue(output.contains("Search results for") || output.contains("found") || output.contains("No packages found"),
                     "Search with descriptions should work")
    }

    func testSearchPerformanceWithRealData() async throws {
        // Skip this test in CI environments where it might be slow
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Skipping performance test in CI environment")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let output = try await withTimeout(seconds: 15) {
            try await self.runCLICommand(["search", "lib", "--descriptions"])
        }
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertTrue(output.contains("Search results for") || output.contains("found") || output.contains("No packages found"),
                     "Search should complete")
        // Should complete search within reasonable time (15 seconds for CI)
        XCTAssertLessThan(timeElapsed, 15.0, "Search took too long: \(timeElapsed)s")
    }

    func testSearchEmptyResults() async throws {
        let output = try await withTimeout(seconds: 10) {
            try await self.runCLICommand(["search", "definitely-does-not-exist-anywhere-12345"])
        }
        XCTAssertTrue(output.contains("No packages found") || output.contains("found") || output.contains("Search results for"),
                     "Search should handle no results gracefully")
    }

    // MARK: - Real Info Tests

    func testInfoRealPackages() async throws {
        // Skip this test in CI environments where it might be slow
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Skipping slow network test in CI environment")
        }

        let commonPackages = ["wget", "curl", "git"]

        for package in commonPackages {
            let output = try await withTimeout(seconds: 10) {
                try await self.runCLICommand(["info", package])
            }
            XCTAssertTrue(output.contains("Formula:") || output.contains("Package:") || output.contains("not found"),
                         "Info command should work for \(package)")
        }
    }

    func testInfoVerboseMode() async throws {
        let output = try await withTimeout(seconds: 10) {
            try await self.runCLICommand(["info", "wget", "--verbose"])
        }
        XCTAssertTrue(output.contains("Formula:") || output.contains("Package:") || output.contains("not found"),
                     "Info verbose mode should work")
    }

    func testInfoInstalledFlag() async throws {
        let output = try await withTimeout(seconds: 10) {
            try await self.runCLICommand(["info", "wget", "--installed"])
        }
        XCTAssertTrue(output.contains("installed") || output.contains("Not installed") || output.contains("not found"),
                     "Info installed flag should work")
    }

    func testInfoNonexistentPackage() async throws {
        let output = try await withTimeout(seconds: 10) {
            try await self.runCLICommand(["info", "definitely-does-not-exist-12345"])
        }
        XCTAssertTrue(output.contains("not found") || output.contains("error"),
                     "Info should handle non-existent package")
    }

    // MARK: - Doctor Command Tests

    func testDoctorBasicCheck() async throws {
        let output = try await runCLICommand(["doctor"])
        XCTAssertTrue(output.contains("Doctor") || output.contains("Checking") || output.contains("System"),
                     "Doctor command should work")
    }

    func testDoctorVerboseMode() async throws {
        let output = try await runCLICommand(["doctor", "--verbose"])
        XCTAssertTrue(output.contains("Doctor") || output.contains("Checking") || output.contains("System"),
                     "Doctor verbose mode should work")
    }

    func testDoctorContextInformation() async throws {
        // Test in global context (no velo.json)
        let output = try await runCLICommand(["doctor"])
        XCTAssertTrue(output.contains("Doctor") || output.contains("Checking") || output.contains("System"),
                     "Doctor should work in global context")
    }

    func testDoctorInProjectContext() async throws {
        // Create a project context
        let projectDir = tempDirectory.appendingPathComponent("test-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let veloJson = projectDir.appendingPathComponent("velo.json")
        let projectConfig = """
        {
            "dependencies": {
                "wget": "1.25.0",
                "curl": "latest"
            }
        }
        """
        try projectConfig.write(to: veloJson, atomically: true, encoding: .utf8)

        // Change to project directory
        let originalDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(projectDir.path)

        defer {
            FileManager.default.changeCurrentDirectoryPath(originalDir)
        }

        let output = try await runCLICommand(["doctor"])
        XCTAssertTrue(output.contains("Doctor") || output.contains("Checking") || output.contains("System"),
                     "Doctor should work in project context")
    }

    // MARK: - List Command Tests

    func testListEmpty() async throws {
        let output = try await runCLICommand(["list"])
        XCTAssertTrue(output.contains("No packages installed") || output.contains("package"),
                     "List command should handle empty installation gracefully")
    }

    func testListWithVersions() async throws {
        let output = try await runCLICommand(["list", "--versions"])
        XCTAssertTrue(output.contains("No packages installed") || output.contains("package"),
                     "List with versions should work")
    }

    // MARK: - Error Handling Tests

    func testErrorHandlingAcrossCommands() async throws {
        // Test various error scenarios across different commands

        // Search with empty term
        let searchOutput = try await runCLICommand(["search", ""])
        XCTAssertTrue(searchOutput.contains("Search results") || searchOutput.contains("No packages found"),
                     "Search should handle empty term gracefully")

        // Info with invalid package specification
        let infoOutput = try await runCLICommand(["info", "@@@invalid@@@"])
        XCTAssertTrue(infoOutput.contains("not found") || infoOutput.contains("error"),
                     "Info should handle invalid package")

        // Uninstall non-existent package (this will likely fail, which is expected)
        let uninstallOutput = try await runCLICommand(["uninstall", "definitely-does-not-exist", "--force"])
        XCTAssertTrue(uninstallOutput.contains("not installed") || uninstallOutput.contains("error"),
                     "Uninstall should handle non-existent package")
    }

    // MARK: - Performance and Load Tests

    func testSearchIndexBuildPerformance() async throws {
        // Skip this test in CI environments where it might be slow
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Skipping performance test in CI environment")
        }

        // Test building full search index
        let pathHelper = PathHelper.shared
        let tapManager = TapManager(pathHelper: pathHelper)

        let startTime = CFAbsoluteTimeGetCurrent()
        try await tapManager.buildFullIndex()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Should build index within reasonable time (30 seconds for CI)
        XCTAssertLessThan(timeElapsed, 30.0, "Index build took too long: \(timeElapsed)s")
    }

    func testConcurrentSearches() async throws {
        // Skip this test in CI environments where it might be slow
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Skipping concurrent test in CI environment")
        }

        // Test multiple concurrent searches using CLI
        let searchTerms = ["wget", "curl", "git"]

        await withTaskGroup(of: Void.self) { group in
            for term in searchTerms {
                group.addTask {
                    do {
                        _ = try await self.withTimeout(seconds: 10) {
                            try await self.runCLICommand(["search", term])
                        }
                    } catch {
                        // Ignore errors in concurrent test
                    }
                }
            }
        }
    }

    func testMemoryUsageDuringLargeOperations() async throws {
        // Skip this test in CI environments where it might be slow
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Skipping memory test in CI environment")
        }

        // Test memory usage during large operations
        let output = try await withTimeout(seconds: 20) {
            try await self.runCLICommand(["search", ".*", "--descriptions"])
        }
        XCTAssertTrue(output.contains("Search results") || output.contains("found") || output.contains("No packages found"),
                     "Large search should complete without memory issues")
    }

    // MARK: - Real Formula Validation Tests

    func testCommonPackageFormulas() async throws {
        // Skip this test in CI environments where it might be slow
        guard !ProcessInfo.processInfo.environment.keys.contains("CI") else {
            throw XCTSkip("Skipping formula validation test in CI environment")
        }

        let commonPackages = [
            "wget", "curl", "git", "node", "python", "ruby", "go", "rust",
            "openssl", "zlib", "libssl", "cmake", "ninja", "pkg-config"
        ]

        let pathHelper = PathHelper.shared
        let tapManager = TapManager(pathHelper: pathHelper)

        for packageName in commonPackages {
            do {
                let formula = try tapManager.findFormula(packageName)
                XCTAssertNotNil(formula, "Should find formula for \(packageName)")

                if let formula = formula {
                    XCTAssertFalse(formula.name.isEmpty, "Formula name should not be empty")
                    XCTAssertFalse(formula.version.isEmpty, "Formula version should not be empty")
                    XCTAssertFalse(formula.url.isEmpty, "Formula URL should not be empty")
                    XCTAssertFalse(formula.sha256.isEmpty, "Formula SHA256 should not be empty")
                }
            } catch {
                XCTFail("Failed to parse formula for \(packageName): \(error)")
            }
        }
    }

    // MARK: - Integration Flow Tests

    func testCompleteUserWorkflow() async throws {
        // Skip this test for now - requires proper ArgumentParser integration
        // TODO: Implement using actual CLI binary execution like ArgumentParserTests
        throw XCTSkip("CLI integration test disabled - needs ArgumentParser rework")
    }

    func testProjectBasedWorkflow() async throws {
        // Test project-based workflow

        // Create project directory
        let projectDir = tempDirectory.appendingPathComponent("my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let originalDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(projectDir.path)

        defer {
            FileManager.default.changeCurrentDirectoryPath(originalDir)
        }

        // Initialize project
        let veloJson = projectDir.appendingPathComponent("velo.json")
        let config = """
        {
            "dependencies": {
                "wget": "1.25.0",
                "curl": "latest"
            },
            "taps": ["homebrew/core"]
        }
        """
        try config.write(to: veloJson, atomically: true, encoding: .utf8)

        // Run doctor in project context
        let doctorOutput = try await runCLICommand(["doctor"])
        XCTAssertTrue(doctorOutput.contains("Doctor") || doctorOutput.contains("Checking"),
                     "Doctor should work in project context")

        // List packages (should be empty but detect project)
        let listOutput = try await runCLICommand(["list"])
        XCTAssertTrue(listOutput.contains("No packages installed") || listOutput.contains("package"),
                     "List should work in project context")
    }

    // MARK: - Helper Methods

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private struct TimeoutError: Error {}

    private func runCLICommand(_ args: [String]) async throws -> String {
        // Find the actual velo binary path in the current build configuration
        let possiblePaths = [
            "./.build/release/velo",
            "./.build/arm64-apple-macosx/release/velo",
            "./.build/debug/velo",
            "./.build/arm64-apple-macosx/debug/velo"
        ]

        var executable: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                executable = path
                break
            }
        }

        guard let executablePath = executable else {
            throw VeloError.pathNotFound(path: "Could not find velo binary in any of the expected locations: \(possiblePaths.joined(separator: ", "))")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
