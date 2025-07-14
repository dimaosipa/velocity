import Foundation
import ArgumentParser
import VeloCore
import VeloFormula
import VeloSystem

extension Velo {
    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Display information about a package"
        )

        @Argument(help: "The package to show information for")
        var package: String

        @Flag(help: "Show detailed information")
        var verbose = false

        @Flag(help: "Show only installation status")
        var installed = false

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

            do {
                // Parse package specification (supports package@version syntax)
                let packageSpec = PackageSpecification.parse(package)
                guard packageSpec.isValid else {
                    fputs("error: Invalid package specification: \(package)\n", stderr)
                    OSLogger.shared.error("Invalid package specification: \(package)")
                    throw ExitCode.failure
                }

                if installed {
                    // Just show installation status - don't need to find formula
                    if pathHelper.isPackageInstalled(packageSpec.name) {
                        let versions = pathHelper.installedVersions(for: packageSpec.name)
                        print("Installed versions: \(versions.joined(separator: ", "))")
                    } else {
                        print("Not installed")
                    }
                    return
                }

                // Find formula (note: version is ignored for info, we show available version)
                guard let formula = try await findFormula(packageSpec.name) else {
                    fputs("error: Formula not found: \(packageSpec.name)\n", stderr)
                    OSLogger.shared.error("Formula not found: \(packageSpec.name)")
                    throw ExitCode.failure
                }

                // Show formula information
                print("==> \(formula.name): \(formula.description)")
                print("\(formula.homepage)")

                // Installation status
                let isInstalled = pathHelper.isPackageInstalled(packageSpec.name)
                if isInstalled {
                    let versions = pathHelper.installedVersions(for: packageSpec.name)
                    print("\nInstalled: \(versions.joined(separator: ", "))")

                    // Verify installation
                    let status = try installer.verifyInstallation(formula: formula)
                    switch status {
                    case .installed:
                        print("Status: ✅ Properly installed")
                    case .corrupted(let reason):
                        print("Status: ⚠️  Corrupted (\(reason))")
                    case .notInstalled:
                        print("Status: ❌ Not installed")
                    }
                } else {
                    print("\nNot installed")
                }

                // Version information
                print("\nAvailable version: \(formula.version)")
                print("Source URL: \(formula.url)")

                // Dependencies
                if !formula.dependencies.isEmpty {
                    print("\nDependencies:")
                    for dependency in formula.dependencies {
                        let typeStr = dependency.type == .required ? "" : " (\(dependency.type))"
                        print("  \(dependency.name)\(typeStr)")
                    }
                }

                // Bottle information
                if formula.hasCompatibleBottle {
                    print("\nBottles available for Apple Silicon:")
                    for bottle in formula.bottles {
                        let compatible = bottle.platform.isCompatible ? "✅" : "❌"
                        print("  \(bottle.platform.rawValue): \(compatible)")
                    }

                    if let preferred = formula.preferredBottle {
                        print("Preferred bottle: \(preferred.platform.rawValue)")
                    }
                } else {
                    print("\n⚠️  No compatible bottles available for Apple Silicon")
                }

                // Verbose information
                if verbose {
                    print("\nDetailed Information:")
                    print("SHA256: \(formula.sha256)")

                    if let preferred = formula.preferredBottle,
                       let bottleURL = formula.bottleURL(for: preferred) {
                        print("Bottle URL: \(bottleURL)")
                        print("Bottle SHA256: \(preferred.sha256)")
                    }

                    if isInstalled {
                        let packageDir = pathHelper.packagePath(for: formula.name, version: formula.version)
                        if let size = try? pathHelper.totalSize(of: packageDir) {
                            let formatter = ByteCountFormatter()
                            formatter.countStyle = .binary
                            print("Installed size: \(formatter.string(fromByteCount: size))")
                        }
                    }
                }

            } catch {
                fputs("error: Failed to get package info: \(error.localizedDescription)\n", stderr)
                OSLogger.shared.error("Failed to get package info: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        private func findFormula(_ name: String) async throws -> Formula? {
            // Use TapManager to find formula (same as Install command)
            let pathHelper = PathHelper.shared
            let tapManager = TapManager(pathHelper: pathHelper)

            return try tapManager.findFormula(name)
        }
    }
}
