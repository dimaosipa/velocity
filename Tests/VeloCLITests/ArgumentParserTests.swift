import XCTest
import ArgumentParser
@testable import VeloCLI
@testable import VeloSystem

final class ArgumentParserTests: XCTestCase {

    // MARK: - Error Cases for Command Parsing

    func testInstallCommandMissingArgument() throws {
        XCTAssertThrowsError(try Velo.Install.parseAsRoot([])) { error in
            XCTAssertTrue(error is ArgumentParser.ValidationError || error is CleanExit)
        }
    }

    func testSearchCommandMissingArgument() throws {
        XCTAssertThrowsError(try Velo.Search.parseAsRoot([])) { error in
            XCTAssertTrue(error is ArgumentParser.ValidationError || error is CleanExit)
        }
    }

    func testInfoCommandMissingArgument() throws {
        XCTAssertThrowsError(try Velo.Info.parseAsRoot([])) { error in
            XCTAssertTrue(error is ArgumentParser.ValidationError || error is CleanExit)
        }
    }

    func testInvalidFlag() throws {
        XCTAssertThrowsError(try Velo.Install.parseAsRoot(["wget", "--invalid-flag"])) { error in
            XCTAssertTrue(error is ArgumentParser.ValidationError || error is CleanExit)
        }
    }

    // MARK: - Integration Test: CLI Process Execution

    func testCLISyncCommands() async throws {
        // These should work based on our manual testing
        let doctorOutput = try await runCLICommand(["doctor"])
        XCTAssertTrue(doctorOutput.contains("Velo Doctor") || doctorOutput.contains("Checking"))

        let listOutput = try await runCLICommand(["list"])
        XCTAssertTrue(listOutput.contains("No packages installed") || listOutput.contains("package"))
    }

    func testCLIAsyncCommandsShowHelp() async throws {
        // These currently show help instead of executing - this is the bug we're testing
        let installOutput = try await runCLICommand(["install", "wget"])
        XCTAssertTrue(installOutput.contains("OVERVIEW: Install a package"),
                     "Install command should show help (this is the bug we're fixing)")

        let searchOutput = try await runCLICommand(["search", "test"])
        XCTAssertTrue(searchOutput.contains("OVERVIEW: Search for packages"),
                     "Search command should show help (this is the bug we're fixing)")
    }

    // MARK: - Helper Methods

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
            throw VeloError.systemError("Could not find velo binary in any of the expected locations: \(possiblePaths.joined(separator: ", "))")
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
