import XCTest
import ArgumentParser
@testable import VeloCLI
@testable import VeloSystem
@testable import VeloIntegrationTests // For TestUtilities

final class ArgumentParserTests: XCTestCase {
    
    // MARK: - Error Cases for Command Parsing
    
    func testInstallCommandMissingArgument() throws {
        XCTAssertThrowsError(try Install.parseAsRoot([])) { error in
            XCTAssertTrue(error is ArgumentParser.ValidationError || error is CleanExit)
        }
    }
    
    func testSearchCommandMissingArgument() throws {
        XCTAssertThrowsError(try Search.parseAsRoot([])) { error in
            XCTAssertTrue(error is ArgumentParser.ValidationError || error is CleanExit)
        }
    }
    
    func testInfoCommandMissingArgument() throws {
        XCTAssertThrowsError(try Info.parseAsRoot([])) { error in
            XCTAssertTrue(error is ArgumentParser.ValidationError || error is CleanExit)
        }
    }
    
    func testInvalidFlag() throws {
        XCTAssertThrowsError(try Install.parseAsRoot(["wget", "--invalid-flag"])) { error in
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
        let executable = "/Users/dmitry/Developer/velo/.build/arm64-apple-macosx/release/velo"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
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

