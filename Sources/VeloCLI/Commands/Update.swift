import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct Update: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Update formula repositories and upgrade packages"
        )

        @Flag(help: "Update repositories only (don't upgrade packages)")
        var repositoryOnly = false

        @Flag(help: "Show what would be updated without doing it")
        var dryRun = false

        @Argument(help: "Specific packages to update (leave empty for all)")
        var packages: [String] = []

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
            logInfo("Updating Velo...")

            if !repositoryOnly {
                if dryRun {
                    try await showUpdates()
                } else {
                    try await performUpdates()
                }
            } else {
                try await updateRepositories()
            }
        }

        private func updateRepositories() async throws {
            logInfo("Updating formula repositories...")

            let tapManager = TapManager()
            try await tapManager.updateTaps()

            // Clear formula cache to force re-parsing with updated formulae
            let cache = FormulaCache()
            try cache.clear()

            Logger.shared.success("Formula repositories updated!")
        }

        private func showUpdates() async throws {
            logInfo("Checking for package updates...")

            // Update repositories first
            try await updateRepositories()

            let pathHelper = PathHelper.shared
            let installedPackages = try getInstalledPackages()

            if installedPackages.isEmpty {
                print("No packages installed")
                return
            }

            let tapManager = TapManager()
            var hasUpdates = false

            for package in installedPackages {
                let currentVersions = pathHelper.installedVersions(for: package)
                guard let currentVersion = currentVersions.first else { continue }

                do {
                    if let formula = try tapManager.findFormula(package) {
                        if formula.version != currentVersion {
                            print("🔄 \(package): \(currentVersion) -> \(formula.version)")
                            hasUpdates = true
                        } else {
                            print("✅ \(package): \(currentVersion) (up to date)")
                        }
                    } else {
                        print("❓ \(package): \(currentVersion) (formula not found)")
                    }
                } catch {
                    print("⚠️  \(package): \(currentVersion) (error checking: \(error.localizedDescription))")
                }
            }

            if !hasUpdates {
                print()
                Logger.shared.success("All packages are up to date!")
            } else {
                print()
                print("Run 'velo update' without --dry-run to upgrade packages")
            }
        }

        private func performUpdates() async throws {
            logInfo("Upgrading packages...")

            // Update repositories first
            try await updateRepositories()

            let installedPackages = try getInstalledPackages()

            if installedPackages.isEmpty {
                print("No packages installed")
                return
            }

            // Filter packages if specific ones were requested
            let packagesToUpdate = packages.isEmpty ? installedPackages : packages.filter { installedPackages.contains($0) }

            if packagesToUpdate.isEmpty {
                if !packages.isEmpty {
                    logError("None of the specified packages are installed")
                    throw ExitCode.failure
                }
                return
            }

            let tapManager = TapManager()
            let installer = Installer()
            let downloader = BottleDownloader()
            let pathHelper = PathHelper.shared
            var upgradeCount = 0

            for package in packagesToUpdate {
                let currentVersions = pathHelper.installedVersions(for: package)
                guard let currentVersion = currentVersions.first else { continue }

                do {
                    guard let formula = try tapManager.findFormula(package) else {
                        print("⚠️  \(package): formula not found, skipping")
                        continue
                    }

                    if formula.version == currentVersion {
                        print("✅ \(package) \(currentVersion) is already up to date")
                        continue
                    }

                    logInfo("Upgrading \(package): \(currentVersion) -> \(formula.version)")

                    // Check for compatible bottle
                    guard let bottle = formula.preferredBottle else {
                        print("⚠️  \(package): no compatible bottle found, skipping")
                        continue
                    }

                    guard let bottleURL = formula.bottleURL(for: bottle) else {
                        print("⚠️  \(package): could not generate bottle URL, skipping")
                        continue
                    }

                    // Download new version
                    let tempFile = pathHelper.temporaryFile(prefix: "bottle-\(package)", extension: "tar.gz")

                    try await downloader.download(
                        from: bottleURL,
                        to: tempFile,
                        expectedSHA256: bottle.sha256,
                        progress: nil
                    )

                    // Uninstall old version
                    try installer.uninstall(package: package)

                    // Install new version
                    try await installer.install(
                        formula: formula,
                        from: tempFile,
                        progress: nil
                    )

                    // Clean up
                    try? FileManager.default.removeItem(at: tempFile)

                    Logger.shared.success("\(package) upgraded to \(formula.version)")
                    upgradeCount += 1

                } catch {
                    logError("Failed to upgrade \(package): \(error.localizedDescription)")
                }
            }

            if upgradeCount == 0 {
                Logger.shared.success("All packages are up to date!")
            } else {
                Logger.shared.success("Upgraded \(upgradeCount) package(s)")
            }
        }

        private func getInstalledPackages() throws -> [String] {
            let pathHelper = PathHelper.shared
            let cellarPath = pathHelper.cellarPath

            guard FileManager.default.fileExists(atPath: cellarPath.path) else {
                return []
            }

            return try FileManager.default.contentsOfDirectory(atPath: cellarPath.path)
                .filter { !$0.hasPrefix(".") }
                .sorted()
        }
    }
}
