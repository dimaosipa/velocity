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

        @Argument(parsing: .captureForPassthrough, help: "Arguments to pass to the command")
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
            // Ensure velo directories exist
            try PathHelper.shared.ensureVeloDirectories()

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
                OSLogger.shared.error("Command '\(command)' not found")

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

            // Inherit stdin/stdout/stderr for full terminal compatibility
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            
            // Ensure the process runs in its own process group for better signal handling
            // This helps with interactive commands and proper terminal control
            process.qualityOfService = .userInteractive

            // Set up signal forwarding
            let signalForwarder = SignalForwarder(process: process)
            signalForwarder.setupSignalHandling()

            do {
                try process.run()
                process.waitUntilExit()
                
                // Clean up signal handling
                signalForwarder.cleanupSignalHandling()

                // Always exit with the same code as the subprocess
                throw ExitCode(process.terminationStatus)
            } catch let exitCode as ExitCode {
                // Clean up signal handling on early exit
                signalForwarder.cleanupSignalHandling()
                // Re-throw ExitCode directly to preserve the subprocess exit code
                throw exitCode
            } catch {
                // Clean up signal handling on error
                signalForwarder.cleanupSignalHandling()
                OSLogger.shared.error("Failed to execute '\(command)': \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}

// MARK: - Signal Forwarding

private class SignalForwarder {
    private let process: Process
    private var signalSources: [DispatchSourceSignal] = []
    
    init(process: Process) {
        self.process = process
    }
    
    func setupSignalHandling() {
        // Handle common signals that should be forwarded to the child process
        let signalsToForward = [SIGINT, SIGTERM, SIGUSR1, SIGUSR2]
        
        for signal in signalsToForward {
            let signalSource = DispatchSource.makeSignalSource(signal: signal, queue: .main)
            
            signalSource.setEventHandler { [weak self] in
                self?.forwardSignal(signal)
            }
            
            signalSource.resume()
            signalSources.append(signalSource)
            
            // Ignore the signal in the parent process so we can handle it manually
            Darwin.signal(signal, SIG_IGN)
        }
    }
    
    func cleanupSignalHandling() {
        // Cancel all signal sources
        for signalSource in signalSources {
            signalSource.cancel()
        }
        signalSources.removeAll()
        
        // Restore default signal handling
        Darwin.signal(SIGINT, SIG_DFL)
        Darwin.signal(SIGTERM, SIG_DFL)
        Darwin.signal(SIGUSR1, SIG_DFL)
        Darwin.signal(SIGUSR2, SIG_DFL)
    }
    
    private func forwardSignal(_ signal: Int32) {
        guard process.isRunning else { return }
        
        // Forward the signal to the child process
        // Use negative PID to send signal to the process group
        kill(-process.processIdentifier, signal)
    }
}
