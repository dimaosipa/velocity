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
            let installer = Installer()
            let pathHelper = PathHelper.shared

            do {
                // Find formula
                guard let formula = try await findFormula(package) else {
                    logError("Formula not found: \(package)")
                    throw ExitCode.failure
                }

                if installed {
                    // Just show installation status
                    if pathHelper.isPackageInstalled(package) {
                        let versions = pathHelper.installedVersions(for: package)
                        print("Installed versions: \(versions.joined(separator: ", "))")
                    } else {
                        print("Not installed")
                    }
                    return
                }

                // Show formula information
                print("==> \(formula.name): \(formula.description)")
                print("\(formula.homepage)")

                // Installation status
                let isInstalled = pathHelper.isPackageInstalled(package)
                if isInstalled {
                    let versions = pathHelper.installedVersions(for: package)
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
                logError("Failed to get package info: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        private func findFormula(_ name: String) async throws -> Formula? {
            // Simulate finding a formula (same as Install command)
            let parser = FormulaParser()

            let testFormulaPath = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Tests")
                .appendingPathComponent("Fixtures")
                .appendingPathComponent("Formulae")
                .appendingPathComponent("\(name).rb")

            if FileManager.default.fileExists(atPath: testFormulaPath.path) {
                let content = try String(contentsOf: testFormulaPath)
                return try parser.parse(rubyContent: content, formulaName: name)
            }

            return nil
        }
    }
}
