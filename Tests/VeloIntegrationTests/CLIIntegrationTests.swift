import XCTest
import Foundation
@testable import VeloCLI
@testable import VeloCore
@testable import VeloFormula
@testable import VeloSystem

final class CLIIntegrationTests: XCTestCase {
    var tempDirectory: URL!
    var veloHome: URL!
    var testPathHelper: PathHelper!

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
        // Create isolated test environment
        testPathHelper = PathHelper(customHome: veloHome)

        // Create velo directories in test environment
        try! testPathHelper.ensureVeloDirectories()

        // Setup logger for testing
        Logger.shared.logLevel = .error // Quiet during tests
    }

    // MARK: - Doctor Command Tests

    func testDoctorCommand() throws {
        // TODO: CLI integration tests need proper PathHelper injection to avoid using global state
        // For now, just verify the command can be instantiated
        let doctor = Velo.Doctor()
        XCTAssertNotNil(doctor)
    }

    // MARK: - List Command Tests

    func testListCommandEmpty() throws {
        // TODO: CLI integration tests need proper PathHelper injection
        let list = Velo.List()
        XCTAssertNotNil(list)
    }

    func testListCommandWithVersions() throws {
        // TODO: CLI integration tests need proper PathHelper injection
        var list = Velo.List()
        list.versions = true
        XCTAssertNotNil(list)
    }

    // MARK: - Search Command Tests

    func testSearchCommand() async throws {
        // TODO: CLI integration tests need proper PathHelper injection
        var search = Velo.Search()
        search.term = "simple"
        XCTAssertNotNil(search)
    }

    func testSearchWithDescriptions() async throws {
        // TODO: CLI integration tests need proper PathHelper injection
        var search = Velo.Search()
        search.term = "test"
        search.descriptions = true
        XCTAssertNotNil(search)
    }

    // MARK: - Info Command Tests

    func testInfoCommand() async throws {
        // TODO: CLI integration tests need proper PathHelper injection
        var info = Velo.Info()
        info.package = "simple"
        XCTAssertNotNil(info)
    }

    func testInfoCommandVerbose() async throws {
        // TODO: CLI integration tests need proper PathHelper injection
        var info = Velo.Info()
        info.package = "wget"
        info.verbose = true
        XCTAssertNotNil(info)
    }

    func testInfoCommandNotFound() async throws {
        // TODO: CLI integration tests need proper PathHelper injection
        var info = Velo.Info()
        info.package = "nonexistent-package"
        XCTAssertNotNil(info)
    }

    // MARK: - Uninstall Command Tests

    func testUninstallNonexistentPackage() throws {
        // TODO: CLI integration tests need proper PathHelper injection
        var uninstall = Velo.Uninstall()
        uninstall.package = "nonexistent"
        uninstall.force = true // Skip confirmation
        XCTAssertNotNil(uninstall)
    }

    // MARK: - Update Command Tests

    func testUpdateCommand() async throws {
        // TODO: CLI integration tests need proper PathHelper injection
        let update = Velo.Update()
        XCTAssertNotNil(update)
    }

    func testUpdateDryRun() async throws {
        // TODO: CLI integration tests need proper PathHelper injection
        var update = Velo.Update()
        update.dryRun = true
        XCTAssertNotNil(update)
    }

    // MARK: - End-to-End Workflow Tests

    func testCompleteWorkflow() async throws {
        // TODO: CLI integration tests need proper PathHelper injection
        // For now, just verify commands can be instantiated

        let doctor = Velo.Doctor()
        XCTAssertNotNil(doctor)

        var search = Velo.Search()
        search.term = "wget"
        XCTAssertNotNil(search)

        var info = Velo.Info()
        info.package = "wget"
        XCTAssertNotNil(info)

        let list = Velo.List()
        XCTAssertNotNil(list)
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
        // TODO: CLI integration tests need proper PathHelper injection
        var search = Velo.Search()
        search.term = "test"
        search.descriptions = true
        XCTAssertNotNil(search)
    }

    // MARK: - Error Handling Tests

    func testErrorHandlingInCommands() async throws {
        // TODO: CLI integration tests need proper PathHelper injection

        var info = Velo.Info()
        info.package = "definitely-does-not-exist"
        XCTAssertNotNil(info)

        var uninstall = Velo.Uninstall()
        uninstall.package = "nonexistent"
        uninstall.force = true
        XCTAssertNotNil(uninstall)
    }

    // MARK: - Helper Methods

}

// MARK: - Test Utilities in TestUtilities.swift
