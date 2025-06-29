import XCTest
@testable import VeloSystem

final class VeloErrorTests: XCTestCase {

    func testFormulaNotFoundError() {
        let error = VeloError.formulaNotFound(name: "wget")
        XCTAssertEqual(error.errorDescription, "Formula not found: wget")
    }

    func testFormulaParseError() {
        let error = VeloError.formulaParseError(formula: "wget", details: "Invalid syntax at line 10")
        XCTAssertEqual(error.errorDescription, "Failed to parse formula 'wget': Invalid syntax at line 10")
    }

    func testChecksumMismatchError() {
        let error = VeloError.checksumMismatch(expected: "abc123", actual: "def456")
        XCTAssertEqual(error.errorDescription, "Checksum mismatch. Expected: abc123, got: def456")
    }

    func testAlreadyInstalledError() {
        let error = VeloError.alreadyInstalled(package: "curl")
        XCTAssertEqual(error.errorDescription, "Package 'curl' is already installed")
    }

    func testUnsupportedArchitectureError() {
        let error = VeloError.unsupportedArchitecture(current: "x86_64")
        XCTAssertEqual(error.errorDescription, "Unsupported architecture: x86_64. Velo requires Apple Silicon (arm64)")
    }

    func testCircularDependencyError() {
        let error = VeloError.circularDependency(packages: ["a", "b", "c", "a"])
        XCTAssertEqual(error.errorDescription, "Circular dependency detected: a → b → c → a")
    }

    func testNetworkError() {
        let underlyingError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
        let error = VeloError.networkError(underlyingError)
        XCTAssertTrue(error.errorDescription?.contains("Network error") ?? false)
    }

    func testSymlinkFailedError() {
        let error = VeloError.symlinkFailed(from: "/usr/local/bin/wget", to: "~/.velo/bin/wget")
        XCTAssertEqual(error.errorDescription, "Failed to create symlink from /usr/local/bin/wget to ~/.velo/bin/wget")
    }

    func testAllErrorCasesHaveDescriptions() {
        // This test ensures we handle all cases
        let testCases: [VeloError] = [
            .formulaNotFound(name: "test"),
            .formulaParseError(formula: "test", details: "details"),
            .invalidFormulaFormat(details: "details"),
            .downloadFailed(url: "url", error: NSError(domain: "", code: 0)),
            .checksumMismatch(expected: "a", actual: "b"),
            .networkError(NSError(domain: "", code: 0)),
            .installationFailed(package: "pkg", reason: "reason"),
            .alreadyInstalled(package: "pkg"),
            .extractionFailed(reason: "reason"),
            .symlinkFailed(from: "a", to: "b"),
            .unsupportedArchitecture(current: "arch"),
            .insufficientPermissions(path: "path"),
            .pathNotFound(path: "path"),
            .ioError(NSError(domain: "", code: 0)),
            .dependencyNotFound(dependency: "dep", package: "pkg"),
            .circularDependency(packages: ["a", "b"]),
            .tapCloneFailed(url: "url", error: NSError(domain: "", code: 0)),
            .tapUpdateFailed(tap: "tap", error: NSError(domain: "", code: 0))
        ]

        for error in testCases {
            XCTAssertNotNil(error.errorDescription, "Error case \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error case \(error) should have a non-empty description")
        }
    }
}
