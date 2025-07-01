import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Uninstall a package"
        )

        @Argument(help: "The package to uninstall")
        var package: String

        @Option(help: "Uninstall specific version only")
        var version: String?

        @Flag(help: "Force uninstall without confirmation")
        var force = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let installer = Installer()
            let pathHelper = PathHelper.shared

            // Ensure velo directories exist
            try pathHelper.ensureVeloDirectories()

            if let specificVersion = version {
                // Uninstall specific version
                OSLogger.shared.info("Uninstalling \(package) v\(specificVersion)...")

                // Check if this specific version is installed
                guard pathHelper.isSpecificVersionInstalled(package, version: specificVersion) else {
                    OSLogger.shared.error("Package '\(package)' version '\(specificVersion)' is not installed")
                    throw ExitCode.failure
                }

                // Confirm uninstall unless forced
                if !force {
                    print("\nAre you sure you want to uninstall \(package) v\(specificVersion)? [y/N]: ", terminator: "")
                    let input = readLine()?.lowercased()

                    if input != "y" && input != "yes" {
                        OSLogger.shared.info("Uninstall cancelled")
                        return
                    }
                }

                do {
                    try installer.uninstallVersion(package: package, version: specificVersion)
                    OSLogger.shared.success("\(package) v\(specificVersion) uninstalled successfully!")

                } catch {
                    OSLogger.shared.error("Uninstallation failed: \(error.localizedDescription)")
                    throw ExitCode.failure
                }

            } else {
                // Uninstall all versions
                OSLogger.shared.info("Uninstalling \(package)...")

                // Check if package is installed
                guard pathHelper.isPackageInstalled(package) else {
                    OSLogger.shared.error("Package '\(package)' is not installed")
                    throw ExitCode.failure
                }

                // Get installed versions
                let versions = pathHelper.installedVersions(for: package)

                // Confirm uninstall unless forced
                if !force {
                    print("The following versions will be uninstalled:")
                    for version in versions {
                        print("  \(package) \(version)")
                    }

                    print("\nAre you sure you want to uninstall \(package)? [y/N]: ", terminator: "")
                    let input = readLine()?.lowercased()

                    if input != "y" && input != "yes" {
                        OSLogger.shared.info("Uninstall cancelled")
                        return
                    }
                }

                do {
                    try installer.uninstall(package: package)
                    OSLogger.shared.success("\(package) uninstalled successfully!")

                } catch {
                    OSLogger.shared.error("Uninstallation failed: \(error.localizedDescription)")
                    throw ExitCode.failure
                }
            }

            // Show cleanup info
            OSLogger.shared.info("Run 'velo doctor' to check for any orphaned dependencies")
        }
    }
}
