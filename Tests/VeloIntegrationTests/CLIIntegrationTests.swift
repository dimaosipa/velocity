import XCTest
import Foundation
@testable import VeloCLI
@testable import VeloCore
@testable import VeloFormula
@testable import VeloSystem

final class CLIIntegrationTests: XCTestCase {
    var tempDirectory: URL!
    var veloHome: URL!

    override func setUp() {
        super.setUp()

        // Create temporary directory for testing
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo_integration_test_\(UUID().uuidString)")

        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Override velo home for testing
        veloHome = tempDirectory.appendingPathComponent(".velo")

        // Setup test environment
        setupTestEnvironment()
    }

    override func tearDown() {
        // Clean up
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func setupTestEnvironment() {
        // Create velo directories
        let pathHelper = PathHelper.shared
        try! pathHelper.ensureVeloDirectories()

        // Setup logger for testing
        Logger.shared.logLevel = .error // Quiet during tests
    }

    // MARK: - Doctor Command Tests

    func testDoctorCommand() throws {
        // Doctor should work even with empty installation
        let doctor = Velo.Doctor()

        // This should not throw
        XCTAssertNoThrow(try doctor.run())
    }

    // MARK: - List Command Tests

    func testListCommandEmpty() throws {
        let list = Velo.List()

        // Should handle empty installation gracefully
        XCTAssertNoThrow(try list.run())
    }

    func testListCommandWithVersions() throws {
        // Create mock installed package
        let pathHelper = PathHelper.shared
        let packageDir = pathHelper.packagePath(for: "test-package", version: "1.0.0")
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)

        var list = Velo.List()
        list.versions = true

        XCTAssertNoThrow(try list.run())
    }

    // MARK: - Search Command Tests

    func testSearchCommand() async throws {
        var search = Velo.Search()
        search.term = "simple"

        // Should find the simple.rb fixture
        await XCTAssertNoThrowAsync(try await search.run())
    }

    func testSearchWithDescriptions() async throws {
        var search = Velo.Search()
        search.term = "test"
        search.descriptions = true

        await XCTAssertNoThrowAsync(try await search.run())
    }

    // MARK: - Info Command Tests

    func testInfoCommand() async throws {
        var info = Velo.Info()
        info.package = "simple"

        // Should display info for simple.rb fixture
        await XCTAssertNoThrowAsync(try await info.run())
    }

    func testInfoCommandVerbose() async throws {
        var info = Velo.Info()
        info.package = "wget"
        info.verbose = true

        await XCTAssertNoThrowAsync(try await info.run())
    }

    func testInfoCommandNotFound() async throws {
        var info = Velo.Info()
        info.package = "nonexistent-package"

        // Should throw or exit with error code
        await XCTAssertThrowsErrorAsync(try await info.run())
    }

    // MARK: - Uninstall Command Tests

    func testUninstallNonexistentPackage() throws {
        var uninstall = Velo.Uninstall()
        uninstall.package = "nonexistent"
        uninstall.force = true // Skip confirmation

        XCTAssertThrowsError(try uninstall.run())
    }

    // MARK: - Update Command Tests

    func testUpdateCommand() async throws {
        let update = Velo.Update()

        // Should handle empty repository gracefully
        await XCTAssertNoThrowAsync(try await update.run())
    }

    func testUpdateDryRun() async throws {
        var update = Velo.Update()
        update.dryRun = true

        await XCTAssertNoThrowAsync(try await update.run())
    }

    // MARK: - End-to-End Workflow Tests

    func testCompleteWorkflow() async throws {
        // This test simulates a complete workflow but with mocked components

        // 1. Check doctor
        let doctor = Velo.Doctor()
        XCTAssertNoThrow(try doctor.run())

        // 2. Search for package
        var search = Velo.Search()
        search.term = "wget"
        await XCTAssertNoThrowAsync(try await search.run())

        // 3. Get info about package
        var info = Velo.Info()
        info.package = "wget"
        await XCTAssertNoThrowAsync(try await info.run())

        // 4. List packages (should be empty)
        let list = Velo.List()
        XCTAssertNoThrow(try list.run())

        // Note: We don't test actual installation since that requires network access
        // and real bottles. That would be covered by manual testing.
    }

    // MARK: - Performance Tests

    func testFormulaParsingPerformance() throws {
        let parser = FormulaParser()
        let content = """
        class Wget < Formula
          desc "Internet file retriever"
          homepage "https://www.gnu.org/software/wget/"
          url "https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz"
          sha256 "766e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784"

          depends_on "pkg-config" => :build
          depends_on "openssl@3"

          bottle do
            sha256 arm64_sonoma: "4d180cd4ead91a34e2c2672189fc366b87ae86e6caa3acbf4845b272f57c859a"
            sha256 arm64_ventura: "7fce09705a52a2aff61c4bdd81b9d2a1a110539718ded2ad45562254ef0f5c22"
            sha256 arm64_monterey: "498cea03c8c9f5ab7b90a0c333122415f0360c09f837cafae6d8685d6846ced2"
          end
        end
        """

        measure {
            for _ in 0..<100 {
                _ = try? parser.parse(rubyContent: content, formulaName: "wget")
            }
        }
    }

    func testSearchPerformance() async throws {
        var search = Velo.Search()
        search.term = "test"
        search.descriptions = true

        await measureAsync {
            try? await search.run()
        }
    }

    // MARK: - Error Handling Tests

    func testErrorHandlingInCommands() async throws {
        // Test various error conditions

        // Invalid package name
        var info = Velo.Info()
        info.package = "definitely-does-not-exist"
        await XCTAssertThrowsErrorAsync(try await info.run())

        // Force uninstall non-existent
        var uninstall = Velo.Uninstall()
        uninstall.package = "nonexistent"
        uninstall.force = true
        XCTAssertThrowsError(try uninstall.run())
    }

    // MARK: - Helper Methods

}

// MARK: - Test Utilities in TestUtilities.swift
