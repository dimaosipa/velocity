import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct Exec: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Execute a command using locally installed packages"
        )

        @Argument(help: "The command to execute")
        var command: String

        @Argument(parsing: .remaining, help: "Arguments to pass to the command")
        var arguments: [String] = []

        @Flag(help: "Use global packages instead of local")
        var global = false

        @Flag(help: "Use system commands, bypassing Velo entirely")
        var system = false

        @Flag(help: "Show which binary will be executed without running it")
        var dryRun = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let context = ProjectContext()
            let resolver = PathResolver()

            // Determine scope
            let scope: PathResolutionConfig.PathScope? = {
                if system { return .system }
                if global { return .global }
                return nil // Use default resolution
            }()

            // Resolve the binary
            guard let binaryPath = resolver.resolveBinary(
                command,
                context: context,
                scope: scope
            ) else {
                logError("Command '\(command)' not found")

                // Show helpful information
                let whichResult = resolver.which(command, context: context)
                if !whichResult.matches.isEmpty {
                    print("\nAvailable in other scopes:")
                    for match in whichResult.matches {
                        let versionInfo = match.version.map { " (\($0))" } ?? ""
                        print("  \(match.scope): \(match.path.path)\(versionInfo)")
                    }
                }

                throw ExitCode.failure
            }

            if dryRun {
                print("Would execute: \(binaryPath.path)")
                if !arguments.isEmpty {
                    print("With arguments: \(arguments.joined(separator: " "))")
                }
                return
            }

            // Execute the command
            let process = Process()
            process.executableURL = binaryPath
            process.arguments = arguments

            // Set up environment to include local bin in PATH
            var environment = ProcessInfo.processInfo.environment
            if let localVeloPath = context.localVeloPath {
                let localBinPath = localVeloPath.appendingPathComponent("bin").path
                if let currentPath = environment["PATH"] {
                    environment["PATH"] = "\(localBinPath):\(currentPath)"
                } else {
                    environment["PATH"] = localBinPath
                }
            }
            process.environment = environment

            // Inherit stdin/stdout/stderr
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError

            do {
                try process.run()
                process.waitUntilExit()

                // Exit with the same code as the subprocess
                if process.terminationStatus != 0 {
                    throw ExitCode(process.terminationStatus)
                }
            } catch {
                logError("Failed to execute '\(command)': \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}
