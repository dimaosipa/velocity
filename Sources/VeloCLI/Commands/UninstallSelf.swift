import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct UninstallSelf: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Uninstall velo binary and optionally remove all data"
        )

        @Flag(help: "Remove only velo binary and PATH entries")
        var binaryOnly = false

        @Flag(help: "Remove entire ~/.velo directory and all data")
        var purge = false

        func run() throws {
            // Use a simple blocking approach for async operations
            let semaphore = DispatchSemaphore(value: 0)
            var thrownError: Error?

            Task {
                do {
                    try await self.runAsync()
                } catch {
                    thrownError = error
                }
                semaphore.signal()
            }

            semaphore.wait()

            if let error = thrownError {
                throw error
            }
        }

        private func runAsync() async throws {
            let pathHelper = PathHelper.shared
            let fileManager = FileManager.default
            let veloBinaryPath = pathHelper.binPath.appendingPathComponent("velo")

            // Check if velo is installed
            guard fileManager.fileExists(atPath: veloBinaryPath.path) else {
                logError("Velo is not installed in ~/.velo/bin/")
                throw ExitCode.failure
            }

            // Determine what to remove
            let removeAll: Bool

            if binaryOnly && purge {
                logError("Cannot specify both --binary-only and --purge")
                throw ExitCode.failure
            } else if binaryOnly {
                removeAll = false
            } else if purge {
                removeAll = true
            } else {
                // Interactive mode
                removeAll = try askUserChoice()
            }

            if removeAll {
                try removeAllData(pathHelper: pathHelper)
            } else {
                try removeBinaryOnly(veloBinaryPath: veloBinaryPath, pathHelper: pathHelper)
            }
        }

        private func askUserChoice() throws -> Bool {
            print("What would you like to remove?")
            print("")
            print("1. Velo binary only (keep packages and data)")
            print("2. Everything (~/.velo directory and all data)")
            print("3. Cancel")
            print("")
            print("Enter your choice [1-3]: ", terminator: "")

            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                print("Invalid input")
                throw ExitCode.failure
            }

            switch input {
            case "1", "binary":
                return false
            case "2", "all", "everything":
                // Ask for confirmation
                print("")
                print("⚠️  WARNING: This will remove:")
                print("   • All installed packages")
                print("   • Download cache")
                print("   • Configuration files")
                print("   • The entire ~/.velo directory")
                print("")
                print("This action cannot be undone. Continue? [y/N]: ", terminator: "")

                guard let confirmation = readLine()?.lowercased() else {
                    print("Cancelled")
                    throw ExitCode.success
                }

                if confirmation == "y" || confirmation == "yes" {
                    return true
                } else {
                    print("Cancelled")
                    throw ExitCode.success
                }
            case "3", "cancel", "c":
                print("Cancelled")
                throw ExitCode.success
            default:
                print("Invalid choice. Please enter 1, 2, or 3")
                throw ExitCode.failure
            }
        }

        private func removeBinaryOnly(veloBinaryPath: URL, pathHelper: PathHelper) throws {
            let fileManager = FileManager.default

            logInfo("Removing velo binary...")

            // Remove the binary
            try fileManager.removeItem(at: veloBinaryPath)

            // Clean PATH from shell profiles
            try cleanPathFromShellProfiles(pathHelper: pathHelper)

            Logger.shared.success("Velo binary removed successfully!")
            print("")
            print("Your packages and data in ~/.velo/ have been preserved.")
            print("To reinstall velo, run the installation script again.")
        }

        private func removeAllData(pathHelper: PathHelper) throws {
            let fileManager = FileManager.default
            let veloHome = pathHelper.veloHome

            logInfo("Removing entire ~/.velo directory...")

            // Remove the entire velo directory
            if fileManager.fileExists(atPath: veloHome.path) {
                try fileManager.removeItem(at: veloHome)
            }

            // Clean PATH from shell profiles
            try cleanPathFromShellProfiles(pathHelper: pathHelper)

            Logger.shared.success("Velo completely removed!")
            print("")
            print("All packages, cache, and configuration have been deleted.")
            print("To reinstall velo, run the installation script again.")
        }

        private func cleanPathFromShellProfiles(pathHelper: PathHelper) throws {
            let veloPath = pathHelper.binPath.path
            var profilesCleaned: [String] = []

            // List of shell profile files to clean
            let profileFiles = [
                ("~/.zshrc", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")),
                ("~/.bashrc", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bashrc")),
                ("~/.bash_profile", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bash_profile")),
                ("~/.profile", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".profile"))
            ]

            for (displayName, profilePath) in profileFiles {
                if FileManager.default.fileExists(atPath: profilePath.path) {
                    let content = try String(contentsOf: profilePath)

                    // Remove lines containing velo path
                    let lines = content.components(separatedBy: .newlines)
                    let filteredLines = lines.filter { line in
                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

                        // Skip lines that reference velo paths
                        if trimmedLine.contains(veloPath) ||
                           trimmedLine.contains("$HOME/.velo/bin") ||
                           trimmedLine.contains("~/.velo/bin") {
                            return false
                        }

                        // Skip the comment line added by installer
                        if trimmedLine == "# Added by Velo installer" {
                            return false
                        }

                        return true
                    }

                    // Remove consecutive empty lines at the end
                    var cleanedLines = filteredLines
                    while cleanedLines.last?.isEmpty == true {
                        cleanedLines.removeLast()
                    }

                    let newContent = cleanedLines.joined(separator: "\n")
                    if newContent != content {
                        // Add a final newline if the file isn't empty
                        let finalContent = newContent.isEmpty ? "" : newContent + "\n"
                        try finalContent.write(to: profilePath, atomically: true, encoding: .utf8)
                        profilesCleaned.append(displayName)
                    }
                }
            }

            if !profilesCleaned.isEmpty {
                logInfo("Cleaned PATH from: \(profilesCleaned.joined(separator: ", "))")
                print("You may need to restart your terminal for PATH changes to take effect.")
            }
        }
    }
}
