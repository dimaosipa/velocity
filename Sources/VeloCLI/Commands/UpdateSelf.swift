import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct UpdateSelf: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update velo to the latest version from GitHub releases"
        )

        @Flag(help: "Check for updates without installing")
        var check = false

        @Flag(help: "Force update even if already on latest version")
        var force = false

        @Flag(help: "Include pre-release versions in update check")
        var preRelease = false

        @Flag(help: "Skip creating backup before update")
        var skipBackup = false

        @Option(help: "GitHub repository owner (default: dimaosipa)")
        var owner: String = "dimaosipa"

        @Option(help: "GitHub repository name (default: velocity)")
        var repo: String = "velocity"

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let updater = SelfUpdater()
            let config = SelfUpdateConfig(
                owner: owner,
                repo: repo,
                includePrerelease: preRelease,
                skipBackup: skipBackup,
                force: force
            )

            // Get current installation info
            let (currentPath, currentVersion, isSymlinked) = updater.getCurrentInstallationInfo()

            print("🔍 Checking for Velo updates...")
            print("Current version: \(currentVersion.description)")

            if let path = currentPath {
                print("Installation path: \(path.path)")
                if isSymlinked {
                    print("Installation type: Symlinked (development mode)")
                } else {
                    print("Installation type: Binary copy")
                }
            }

            print("")

            // Handle symlinked installations
            if isSymlinked {
                print("⚠️  Detected symlinked installation (development mode)")
                print("Symlinked installations cannot be updated automatically.")
                print("To update:")
                print("  1. cd to your velo source directory")
                print("  2. git pull origin main")
                print("  3. swift build -c release")
                print("  4. The symlink will automatically point to the new binary")
                return
            }

            do {
                // Check for updates
                OSLogger.shared.info("Fetching latest release information from GitHub...")
                let result = try await updater.checkForUpdates(config: config)

                switch result {
                case .upToDate(let current):
                    OSLogger.shared.success("✅ Velo is up to date! (v\(current.description))")

                case .updateAvailable(let current, let latest):
                    guard let latestVersion = latest.version else {
                        throw VeloError.updateCheckFailed(reason: "Invalid version in latest release")
                    }

                    print("🚀 Update available!")
                    print("Current version: v\(current.description)")
                    print("Latest version: v\(latestVersion.description)")

                    if latestVersion.isMajorUpdateFrom(current) {
                        print("⚠️  This is a major version update")
                    } else if latestVersion.isMinorUpdateFrom(current) {
                        print("✨ This is a feature update")
                    } else {
                        print("🔧 This is a bug fix update")
                    }

                    if let body = latest.body, !body.isEmpty {
                        print("\nRelease notes:")
                        print(formatReleaseNotes(body))
                    }

                    if check {
                        print("\nRun 'velo update-self' to install the update")
                        return
                    }

                    print("")
                    try await performUpdate(updater: updater, to: latest, config: config)

                case .prereleaseAvailable(let current, let latest):
                    guard let latestVersion = latest.version else {
                        throw VeloError.updateCheckFailed(reason: "Invalid version in latest release")
                    }

                    print("🧪 Pre-release update available!")
                    print("Current version: v\(current.description)")
                    print("Latest pre-release: v\(latestVersion.description)")
                    print("⚠️  This is a pre-release version and may be unstable")

                    if let body = latest.body, !body.isEmpty {
                        print("\nRelease notes:")
                        print(formatReleaseNotes(body))
                    }

                    if check {
                        print("\nRun 'velo update-self --pre-release' to install the pre-release")
                        return
                    }

                    print("")
                    try await performUpdate(updater: updater, to: latest, config: config)
                }

            } catch {
                OSLogger.shared.error("Failed to check for updates: \(error.localizedDescription)")
                print("")
                print("Troubleshooting:")
                print("• Check your internet connection")
                print("• Verify the repository exists: https://github.com/\(owner)/\(repo)")
                print("• Try again in a few minutes (GitHub API rate limiting)")
                throw ExitCode.failure
            }
        }

        private func performUpdate(
            updater: SelfUpdater,
            to release: GitHubRelease,
            config: SelfUpdateConfig
        ) async throws {
            guard let latestVersion = release.version else {
                throw VeloError.updateCheckFailed(reason: "Invalid version in release")
            }

            // Ask for confirmation unless forced
            if !config.force && !askForConfirmation(version: latestVersion, isPrerelease: release.prerelease) {
                print("Update cancelled")
                return
            }

            print("📦 Starting update process...")

            do {
                try await updater.performUpdate(to: release, config: config) { message in
                    print("  \(message)")
                }

                print("")
                OSLogger.shared.success("🎉 Velo has been updated to v\(latestVersion.description)!")
                print("")
                print("The update is complete. You can now use the new version of Velo.")

                // Show what's new if there are release notes
                if let body = release.body, !body.isEmpty {
                    print("\nWhat's new in v\(latestVersion.description):")
                    print(formatReleaseNotes(body))
                }

            } catch {
                OSLogger.shared.error("Update failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        private func askForConfirmation(version: SemanticVersion, isPrerelease: Bool) -> Bool {
            let versionType = isPrerelease ? "pre-release" : "version"
            print("Do you want to update to \(versionType) v\(version.description)? [Y/n]: ", terminator: "")

            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
                return false
            }

            return input.isEmpty || input == "y" || input == "yes"
        }

        private func formatReleaseNotes(_ body: String) -> String {
            let lines = body.components(separatedBy: .newlines)
            let limitedLines = Array(lines.prefix(10)) // Show first 10 lines

            var formatted = limitedLines.map { "  \($0)" }.joined(separator: "\n")

            if lines.count > 10 {
                formatted += "\n  ... (see full release notes on GitHub)"
            }

            return formatted
        }
    }
}
