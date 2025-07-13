import XCTest
import Foundation
@testable import VeloCore
@testable import VeloFormula
@testable import VeloSystem

final class InstallerTests: XCTestCase {
    var installer: Installer!
    var tempDirectory: URL!
    var testPathHelper: PathHelper!

    override func setUp() {
        super.setUp()

        // Create temporary directory
        tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo_installer_test_\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        // Create isolated test environment
        let testVeloHome = tempDirectory.appendingPathComponent(".velo")
        testPathHelper = PathHelper(customHome: testVeloHome)
        installer = Installer(pathHelper: testPathHelper)

        // Ensure test directories exist
        try! testPathHelper.ensureVeloDirectories()
    }

    override func tearDown() {
        // Clean up temporary directory and all test files
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Installation Tests

    func testInstallationWithMockBottle() async throws {
        let formula = createTestFormula()
        let mockBottle = createMockBottle(for: formula)
        let progress = MockInstallationProgress()

        try await installer.install(
            formula: formula,
            from: mockBottle,
            progress: progress
        )

        // Verify progress callbacks
        XCTAssertTrue(progress.didStart)
        XCTAssertTrue(progress.didComplete)

        // Verify installation
        let packageDir = testPathHelper.packagePath(for: formula.name, version: formula.version)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageDir.path))

        // Verify status
        let status = try installer.verifyInstallation(formula: formula)
        XCTAssertTrue(status.isInstalled)
    }

    func testAlreadyInstalledError() async throws {
        let formula = createTestFormula()
        let mockBottle = createMockBottle(for: formula)

        // Install the package first
        try await installer.install(formula: formula, from: mockBottle)

        // Now try to install it again - should throw an error
        do {
            try await installer.install(formula: formula, from: mockBottle)
            XCTFail("Expected alreadyInstalled error to be thrown")
        } catch VeloError.alreadyInstalled {
            // This is expected
        } catch {
            XCTFail("Expected alreadyInstalled error, got \(error)")
        }
    }

    func testUninstallation() throws {
        let formula = createTestFormula()

        // Create mock installation
        let packageDir = testPathHelper.packagePath(for: formula.name, version: formula.version)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)

        // Create mock binary and symlink
        let binDir = packageDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let binaryFile = binDir.appendingPathComponent("test-binary")
        try "#!/bin/bash\necho 'test'".write(to: binaryFile, atomically: true, encoding: .utf8)

        let symlinkPath = testPathHelper.symlinkPath(for: "test-binary")
        try testPathHelper.createSymlink(from: binaryFile, to: symlinkPath)

        // Verify setup
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkPath.path))

        // Uninstall
        try installer.uninstall(package: formula.name)

        // Verify cleanup
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: symlinkPath.path))
    }

    func testUninstallNonexistentPackage() throws {
        XCTAssertThrowsError(try installer.uninstall(package: "nonexistent-package")) { error in
            XCTAssertTrue(error is VeloError)
            if case VeloError.formulaNotFound(let name) = error {
                XCTAssertEqual(name, "nonexistent-package")
            } else {
                XCTFail("Expected formulaNotFound error")
            }
        }
    }

    // MARK: - Verification Tests

    func testVerifyInstallation() throws {
        let formula = createTestFormula()

        // Test not installed
        var status = try installer.verifyInstallation(formula: formula)
        XCTAssertEqual(status, .notInstalled)

        // Create mock installation
        let packageDir = testPathHelper.packagePath(for: formula.name, version: formula.version)
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)

        // Test installed but no binaries
        status = try installer.verifyInstallation(formula: formula)
        XCTAssertTrue(status.isInstalled)

        // Create binary and symlink
        let binDir = packageDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let binaryFile = binDir.appendingPathComponent("test-binary")
        try "test".write(to: binaryFile, atomically: true, encoding: .utf8)

        let symlinkPath = testPathHelper.symlinkPath(for: "test-binary")
        try testPathHelper.createSymlink(from: binaryFile, to: symlinkPath)

        // Test properly installed
        status = try installer.verifyInstallation(formula: formula)
        XCTAssertTrue(status.isInstalled)

        // Test corrupted (remove symlink)
        try FileManager.default.removeItem(at: symlinkPath)
        status = try installer.verifyInstallation(formula: formula)
        if case .corrupted = status {
            // Expected
        } else {
            XCTFail("Expected corrupted status")
        }
    }

    // MARK: - Upgrade Tests

    func testUpgradePackage() async throws {
        let oldFormula = createTestFormula(name: "test-upgrade", version: "1.0.0")
        let newFormula = createTestFormula(name: "test-upgrade", version: "2.0.0")

        // Install old version first using proper installation
        let oldBottle = createMockBottle(for: oldFormula)
        try await installer.install(formula: oldFormula, from: oldBottle)

        let newBottle = createMockBottle(for: newFormula)
        let progress = MockInstallationProgress()

        try await installer.upgradePackage(
            oldFormula: oldFormula,
            newFormula: newFormula,
            bottleFile: newBottle,
            progress: progress
        )

        // Verify old version is removed
        let oldPackageDir = testPathHelper.packagePath(for: oldFormula.name, version: oldFormula.version)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldPackageDir.path))

        // Verify new version is installed
        let newPackageDir = testPathHelper.packagePath(for: newFormula.name, version: newFormula.version)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newPackageDir.path))
    }

    // MARK: - Performance Tests

    func testInstallationPerformance() async throws {
        let formula = createTestFormula()
        let mockBottle = createMockBottle(for: formula)

        await measureAsync {
            try await self.installer.install(formula: formula, from: mockBottle)
        }

        // Clean up for accurate measurement
        try installer.uninstall(package: formula.name)
    }

    // MARK: - Helper Methods

    private func createTestFormula(name: String = "test-package", version: String = "1.0.0") -> Formula {
        return Formula(
            name: name,
            description: "Test package",
            homepage: "https://test.com",
            url: "https://test.com/\(name)-\(version).tar.gz",
            sha256: "abc123",
            version: version,
            dependencies: [],
            bottles: [
                Formula.Bottle(sha256: "def456", platform: .arm64_sonoma)
            ]
        )
    }

    private func createMockBottle(for formula: Formula) -> URL {
        let bottleFile = tempDirectory.appendingPathComponent("\(formula.name)-\(formula.version).tar.gz")

        // Create a proper tar.gz file for testing
        // First create a mock package structure
        let mockPackageDir = tempDirectory.appendingPathComponent("mock_package")
        try! FileManager.default.createDirectory(at: mockPackageDir, withIntermediateDirectories: true)

        // Create mock binary
        let binDir = mockPackageDir.appendingPathComponent("bin")
        try! FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let mockBinary = binDir.appendingPathComponent(formula.name)
        try! "#!/bin/bash\necho 'Mock \(formula.name)'\n".write(to: mockBinary, atomically: true, encoding: .utf8)

        // Create the tar.gz using system tar command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-czf", bottleFile.path, "-C", mockPackageDir.path, "."]
        process.currentDirectoryURL = tempDirectory

        try! process.run()
        process.waitUntilExit()

        // Clean up temporary package directory
        try! FileManager.default.removeItem(at: mockPackageDir)

        return bottleFile
    }
}

// MARK: - Mock Progress Handler

private class MockInstallationProgress: InstallationProgress {
    var didStart = false
    var didComplete = false
    var didFail = false
    var extractionStarted = false
    var linkingStarted = false

    func installationDidStart(package: String, version: String) {
        didStart = true
    }

    func extractionDidStart(totalFiles: Int?) {
        extractionStarted = true
    }

    func extractionDidUpdate(filesExtracted: Int, totalFiles: Int?) {
        // Track updates if needed
    }

    func processingDidStart(phase: String) {
        // Track processing start if needed
    }

    func processingDidUpdate(phase: String, progress: Double) {
        // Track processing updates if needed
    }

    func linkingDidStart(binariesCount: Int) {
        linkingStarted = true
    }

    func linkingDidUpdate(binariesLinked: Int, totalBinaries: Int) {
        // Track updates if needed
    }

    func installationDidComplete(package: String) {
        didComplete = true
    }

    func installationDidFail(package: String, error: Error) {
        didFail = true
    }
}

// MARK: - Test Utilities in TestUtilities.swift

// MARK: - Custom Assertions

extension Installer.InstallationStatus: Equatable {
    public static func == (lhs: Installer.InstallationStatus, rhs: Installer.InstallationStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notInstalled, .notInstalled), (.installed, .installed):
            return true
        case (.corrupted(let reason1), .corrupted(let reason2)):
            return reason1 == reason2
        default:
            return false
        }
    }
}

// MARK: - Test Utilities

extension XCTestCase {
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
}
