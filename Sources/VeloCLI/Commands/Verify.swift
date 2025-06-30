import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct Verify: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Verify that installed packages match velo.lock"
        )

        @Flag(help: "Show detailed information about each package")
        var verbose = false

        @Flag(help: "Use global packages instead of local")
        var global = false

        func run() throws {
            // Use a simple blocking approach for async operations
            let group = DispatchGroup()
            var result: Result<Void, Error>?

            group.enter()
            Task {
                do {
                    try await self.runAsync()
                    result = .success(())
                } catch {
                    result = .failure(error)
                }
                group.leave()
            }

            group.wait()
            try result?.get()
        }

        private func runAsync() async throws {
            let context = ProjectContext()

            // Check if we're in a project context
            guard context.isProjectContext else {
                logError("Not in a project context. Run this command in a directory with velo.json")
                throw ExitCode.failure
            }

            guard let lockFilePath = context.lockFilePath else {
                logError("No velo.lock file found")
                throw ExitCode.failure
            }

            guard FileManager.default.fileExists(atPath: lockFilePath.path) else {
                logError("velo.lock file does not exist. Run 'velo install' to create it.")
                throw ExitCode.failure
            }

            print("🔍 Verifying installed packages against velo.lock...")
            print("")

            let pathHelper = context.getPathHelper(preferLocal: !global)
            let lockFileManager = VeloLockFileManager()

            // Read lock file
            let lockFile = try lockFileManager.read(from: lockFilePath)

            // Get all installed packages
            let installedPackages = try getInstalledPackages(pathHelper: pathHelper)

            // Verify installations
            let mismatches = lockFileManager.verifyInstallations(
                lockFile: lockFile,
                installedPackages: installedPackages
            )

            // Check for extra packages not in lock file
            let extraPackages = installedPackages.keys.filter { packageName in
                !lockFile.dependencies.keys.contains(packageName)
            }

            // Report results
            try reportVerificationResults(
                lockFile: lockFile,
                installedPackages: installedPackages,
                mismatches: mismatches,
                extraPackages: Array(extraPackages),
                verbose: verbose
            )
        }

        private func getInstalledPackages(pathHelper: PathHelper) throws -> [String: String] {
            var installedPackages: [String: String] = [:]

            let cellarPath = pathHelper.cellarPath
            guard FileManager.default.fileExists(atPath: cellarPath.path) else {
                return installedPackages
            }

            let packages = try FileManager.default.contentsOfDirectory(atPath: cellarPath.path)
                .filter { !$0.hasPrefix(".") }

            for package in packages {
                let versions = pathHelper.installedVersions(for: package)
                if let defaultVersion = pathHelper.getDefaultVersion(for: package) {
                    installedPackages[package] = defaultVersion
                } else if let latestVersion = versions.last {
                    installedPackages[package] = latestVersion
                }
            }

            return installedPackages
        }

        private func reportVerificationResults(
            lockFile: VeloLockFile,
            installedPackages: [String: String],
            mismatches: [String],
            extraPackages: [String],
            verbose: Bool
        ) throws {
            var hasIssues = false

            // Report mismatches
            if !mismatches.isEmpty {
                hasIssues = true
                print("❌ Mismatches found:")
                for mismatch in mismatches {
                    print("  • \(mismatch)")
                }
                print("")
            }

            // Report extra packages
            if !extraPackages.isEmpty {
                hasIssues = true
                print("⚠️  Extra packages (not in velo.lock):")
                for package in extraPackages.sorted() {
                    if let version = installedPackages[package] {
                        print("  • \(package): \(version)")
                    } else {
                        print("  • \(package)")
                    }
                }
                print("")
            }

            // Report packages that match
            if verbose {
                let matchingPackages = lockFile.dependencies.compactMap { (packageName, lockEntry) -> String? in
                    if let installedVersion = installedPackages[packageName],
                       installedVersion == lockEntry.version {
                        return packageName
                    }
                    return nil
                }

                if !matchingPackages.isEmpty {
                    print("✅ Matching packages:")
                    for package in matchingPackages.sorted() {
                        let lockEntry = lockFile.dependencies[package]!
                        print("  • \(package): \(lockEntry.version) (from \(lockEntry.tap))")
                    }
                    print("")
                }
            }

            // Summary
            if !hasIssues {
                Logger.shared.success("All packages match velo.lock! (\(lockFile.dependencies.count) packages)")
            } else {
                let issueCount = mismatches.count + extraPackages.count
                logError("Found \(issueCount) issue(s). Run 'velo install' to fix mismatches.")
                throw ExitCode.failure
            }
        }
    }
}
