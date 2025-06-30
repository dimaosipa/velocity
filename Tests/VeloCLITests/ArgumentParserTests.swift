import XCTest
import ArgumentParser
@testable import VeloCLI
@testable import VeloSystem

final class ArgumentParserTests: XCTestCase {

    // MARK: - Error Cases for Command Parsing

    func testInstallCommandMissingArgument() async throws {
        let output = try await runCLICommand(["install"])
        XCTAssertTrue(output.contains("velo init") || output.contains("specify a package name"),
                     "Install without args should show error about missing package or velo.json")
    }

    func testSearchCommandMissingArgument() async throws {
        let output = try await runCLICommand(["search"])
        XCTAssertTrue(output.contains("Missing expected argument") || output.contains("<term>"),
                     "Search without args should show error about missing term")
    }

    func testInfoCommandMissingArgument() async throws {
        let output = try await runCLICommand(["info"])
        XCTAssertTrue(output.contains("Missing expected argument") || output.contains("<package>"),
                     "Info without args should show error about missing package")
    }

    func testInvalidFlag() async throws {
        let output = try await runCLICommand(["install", "wget", "--invalid-flag"])
        XCTAssertTrue(output.contains("Unknown option") || output.contains("invalid-flag"),
                     "Invalid flag should show error")
    }

    // MARK: - Integration Test: CLI Process Execution

    func testCLISyncCommands() async throws {
        // These should work based on our manual testing
        let doctorOutput = try await runCLICommand(["doctor"])
        XCTAssertTrue(doctorOutput.contains("Velo Doctor") || doctorOutput.contains("Checking"))

        let listOutput = try await runCLICommand(["list"])
        XCTAssertTrue(listOutput.contains("No packages installed") || listOutput.contains("package"))
    }

    func testCLIAsyncCommandsWork() async throws {
        // These commands should execute properly (not show help)
        let installOutput = try await runCLICommand(["install", "wget"])
        XCTAssertTrue(installOutput.contains("Installing wget") || installOutput.contains("already installed"),
                     "Install command should execute (not show help)")

        let searchOutput = try await runCLICommand(["search", "test"])
        XCTAssertTrue(searchOutput.contains("Search results for") || searchOutput.contains("found"),
                     "Search command should execute (not show help)")
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
