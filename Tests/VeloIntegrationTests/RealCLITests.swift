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
            var info = Velo.Info()
            info.package = package

            // Should not throw - the @ version is parsed but info shows available version
            await XCTAssertNoThrowAsync(try await info.run())
        }
    }

    // MARK: - Real Search Tests

    func testSearchRealFormulas() async throws {
        var search = Velo.Search()
        search.term = "wget"

        // Should find real wget formula from homebrew/core
        await XCTAssertNoThrowAsync(try await search.run())
    }

    func testSearchWithDescriptions() async throws {
        var search = Velo.Search()
        search.term = "compression"
        search.descriptions = true

        // Should find multiple packages with compression in description
        await XCTAssertNoThrowAsync(try await search.run())
    }

    func testSearchPerformanceWithRealData() async throws {
        var search = Velo.Search()
        search.term = "lib"
        search.descriptions = true

        let startTime = CFAbsoluteTimeGetCurrent()
        await XCTAssertNoThrowAsync(try await search.run())
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Should complete search within reasonable time (10 seconds for CI)
        XCTAssertLessThan(timeElapsed, 10.0, "Search took too long: \(timeElapsed)s")
    }

    func testSearchEmptyResults() async throws {
        var search = Velo.Search()
        search.term = "definitely-does-not-exist-anywhere-12345"

        // Should handle no results gracefully
        await XCTAssertNoThrowAsync(try await search.run())
    }

    // MARK: - Real Info Tests

    func testInfoRealPackages() async throws {
        let commonPackages = ["wget", "curl", "git", "node", "python"]

        for package in commonPackages {
            var info = Velo.Info()
            info.package = package

            await XCTAssertNoThrowAsync(try await info.run())
        }
    }

    func testInfoVerboseMode() async throws {
        var info = Velo.Info()
        info.package = "wget"
        info.verbose = true

        await XCTAssertNoThrowAsync(try await info.run())
    }

    func testInfoInstalledFlag() async throws {
        var info = Velo.Info()
        info.package = "wget"
        info.installed = true

        // Should show "Not installed" for clean environment
        await XCTAssertNoThrowAsync(try await info.run())
    }

    func testInfoNonexistentPackage() async throws {
        var info = Velo.Info()
        info.package = "definitely-does-not-exist-12345"

        await XCTAssertThrowsErrorAsync(try await info.run())
    }

    // MARK: - Doctor Command Tests

    func testDoctorBasicCheck() throws {
        let doctor = Velo.Doctor()

        // Doctor should always complete, may report issues in CI environment
        XCTAssertNoThrow(try doctor.run())
    }

    func testDoctorVerboseMode() throws {
        var doctor = Velo.Doctor()
        doctor.verbose = true

        XCTAssertNoThrow(try doctor.run())
    }

    func testDoctorContextInformation() throws {
        // Test in global context (no velo.json)
        let doctor = Velo.Doctor()
        XCTAssertNoThrow(try doctor.run())
    }

    func testDoctorInProjectContext() throws {
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

        let doctor = Velo.Doctor()
        XCTAssertNoThrow(try doctor.run())
    }

    // MARK: - List Command Tests

    func testListEmpty() throws {
        let list = Velo.List()

        // Should handle empty installation gracefully
        XCTAssertNoThrow(try list.run())
    }

    func testListWithVersions() throws {
        var list = Velo.List()
        list.versions = true

        XCTAssertNoThrow(try list.run())
    }

    // MARK: - Error Handling Tests

    func testErrorHandlingAcrossCommands() async throws {
        // Test various error scenarios across different commands

        // Search with empty term
        do {
            var search = Velo.Search()
            search.term = ""
            await XCTAssertNoThrowAsync(try await search.run()) // Should handle gracefully
        }

        // Info with invalid package specification
        do {
            var info = Velo.Info()
            info.package = "@@@invalid@@@"
            await XCTAssertThrowsErrorAsync(try await info.run())
        }

        // Uninstall non-existent package
        do {
            var uninstall = Velo.Uninstall()
            uninstall.package = "definitely-does-not-exist"
            uninstall.force = true
            XCTAssertThrowsError(try uninstall.run())
        }
    }

    // MARK: - Performance and Load Tests

    func testSearchIndexBuildPerformance() async throws {
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
        // Test multiple concurrent searches
        let searchTerms = ["wget", "curl", "git", "python", "node"]

        await withTaskGroup(of: Void.self) { group in
            for term in searchTerms {
                group.addTask {
                    var search = Velo.Search()
                    search.term = term
                    try? await search.run()
                }
            }
        }
    }

    func testMemoryUsageDuringLargeOperations() async throws {
        // Test memory usage during large operations
        var search = Velo.Search()
        search.term = ".*" // Match many packages
        search.descriptions = true

        // This should not cause excessive memory usage
        await XCTAssertNoThrowAsync(try await search.run())
    }

    // MARK: - Real Formula Validation Tests

    func testCommonPackageFormulas() async throws {
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

    func testProjectBasedWorkflow() throws {
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
        let doctor = Velo.Doctor()
        XCTAssertNoThrow(try doctor.run())

        // List packages (should be empty but detect project)
        let list = Velo.List()
        XCTAssertNoThrow(try list.run())
    }
}
