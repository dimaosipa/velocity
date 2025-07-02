import Foundation
import ArgumentParser
import VeloCore
import VeloFormula
import VeloSystem

extension Velo {
    struct Doctor: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check for system issues"
        )

        @Flag(help: "Show detailed diagnostic information")
        var verbose = false

        @Flag(help: "Attempt to fix detected issues")
        var fix = false

        func run() throws {
            print("🩺 Velo Doctor")
            print("===============")
            print()

            var issueCount = 0
            var warningCount = 0

            // Check architecture
            issueCount += checkArchitecture()

            // Check macOS version
            warningCount += checkMacOSVersion()

            // Check Velo directories
            issueCount += checkVeloDirectories()

            // Check PATH
            warningCount += checkPath()

            // Check permissions
            issueCount += checkPermissions()

            // Check installed packages
            issueCount += checkInstalledPackages()

            // Check disk space
            warningCount += checkDiskSpace()

            // Check context information (local vs global)
            checkContextInformation()

            // Summary
            print()
            print("Summary:")
            if issueCount == 0 && warningCount == 0 {
                print("✅ No issues found. Velo is ready to go!")
            } else {
                if issueCount > 0 {
                    print("❌ Found \(issueCount) issue(s)")
                }
                if warningCount > 0 {
                    print("⚠️  Found \(warningCount) warning(s)")
                }

                if fix {
                    print("\nAttempting to fix issues...")
                    try fixIssues()
                } else {
                    print("\nRun 'velo doctor --fix' to attempt automatic fixes")
                }
            }
        }

        private func checkArchitecture() -> Int {
            print("Checking architecture...")

            // Use uname -m to get the machine architecture
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/uname")
            process.arguments = ["-m"]

            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let arch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

                if arch == "arm64" {
                    print("  ✅ Running on Apple Silicon (\(arch))")
                    return 0
                } else {
                    print("  ❌ Not running on Apple Silicon (detected: \(arch))")
                    print("     Velo requires Apple Silicon Macs (M1/M2/M3)")
                    return 1
                }
            } catch {
                print("  ⚠️  Could not detect architecture: \(error.localizedDescription)")
                return 1
            }
        }

        private func checkMacOSVersion() -> Int {
            print("Checking macOS version...")

            let version = ProcessInfo.processInfo.operatingSystemVersion
            let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

            if version.majorVersion >= 12 {
                print("  ✅ macOS \(versionString) (compatible)")
                return 0
            } else {
                print("  ⚠️  macOS \(versionString) (may have compatibility issues)")
                print("     Velo works best on macOS 12+ (Monterey)")
                return 1
            }
        }

        private func checkVeloDirectories() -> Int {
            print("Checking Velo directories...")

            let pathHelper = PathHelper.shared
            let directories = [
                ("Velo home", pathHelper.veloHome),
                ("Cellar", pathHelper.cellarPath),
                ("Bin", pathHelper.binPath),
                ("Cache", pathHelper.cachePath),
                ("Taps", pathHelper.tapsPath),
                ("Logs", pathHelper.logsPath),
                ("Temp", pathHelper.tmpPath)
            ]

            var issues = 0

            for (name, path) in directories {
                if FileManager.default.fileExists(atPath: path.path) {
                    print("  ✅ \(name): \(path.path)")
                } else {
                    print("  ❌ \(name): \(path.path) (missing)")
                    issues += 1
                }
            }

            return issues
        }

        private func checkPath() -> Int {
            print("Checking PATH...")

            let pathHelper = PathHelper.shared

            if pathHelper.isInPath() {
                print("  ✅ ~/.velo/bin is in PATH")
                return 0
            } else {
                print("  ⚠️  ~/.velo/bin is not in PATH")
                print("     Add this to your shell profile:")
                print("     echo 'export PATH=\"$HOME/.velo/bin:$PATH\"' >> ~/.zshrc")
                return 1
            }
        }

        private func checkPermissions() -> Int {
            print("Checking permissions...")

            let pathHelper = PathHelper.shared
            let testFile = pathHelper.tmpPath.appendingPathComponent("permission_test")

            do {
                try "test".write(to: testFile, atomically: true, encoding: .utf8)
                try FileManager.default.removeItem(at: testFile)
                print("  ✅ Write permissions OK")
                return 0
            } catch {
                print("  ❌ Cannot write to Velo directories")
                print("     Error: \(error.localizedDescription)")
                return 1
            }
        }

        private func checkInstalledPackages() -> Int {
            print("Checking installed packages...")

            let pathHelper = PathHelper.shared
            let installer = Installer()
            let receiptManager = ReceiptManager(pathHelper: pathHelper)

            do {
                let packages = try FileManager.default.contentsOfDirectory(atPath: pathHelper.cellarPath.path)
                    .filter { !$0.hasPrefix(".") }

                if packages.isEmpty {
                    print("  ℹ️  No packages installed")
                    return 0
                }

                var issues = 0

                for package in packages {
                    let versions = pathHelper.installedVersions(for: package)
                    for version in versions {
                        // Create a dummy formula for verification
                        let formula = Formula(
                            name: package,
                            description: "",
                            homepage: "",
                            url: "",
                            sha256: "",
                            version: version
                        )

                        // Check receipt to determine if symlinks should be checked
                        let shouldCheckSymlinks: Bool
                        if let receipt = try? receiptManager.loadReceipt(for: package, version: version) {
                            // Use receipt to determine if symlinks should exist
                            shouldCheckSymlinks = receipt.installedAs == .explicit
                        } else {
                            // No receipt (legacy installation) - check symlinks by default
                            shouldCheckSymlinks = true
                        }
                        
                        let status = try installer.verifyInstallation(formula: formula, checkSymlinks: shouldCheckSymlinks)

                        switch status {
                        case .installed:
                            if verbose {
                                print("  ✅ \(package) \(version)")
                            }
                        case .corrupted(let reason):
                            print("  ❌ \(package) \(version): \(reason)")
                            issues += 1
                        case .notInstalled:
                            print("  ❌ \(package) \(version): Not properly installed")
                            issues += 1
                        }
                    }
                }

                if issues == 0 && !verbose {
                    print("  ✅ All \(packages.count) package(s) are properly installed")
                }

                return issues

            } catch {
                print("  ❌ Failed to check packages: \(error.localizedDescription)")
                return 1
            }
        }

        private func checkDiskSpace() -> Int {
            print("Checking disk space...")

            do {
                let pathHelper = PathHelper.shared
                let attributes = try FileManager.default.attributesOfFileSystem(forPath: pathHelper.veloHome.path)

                if let freeSpace = attributes[.systemFreeSize] as? Int64 {
                    let formatter = ByteCountFormatter()
                    formatter.countStyle = .binary

                    let freeSpaceString = formatter.string(fromByteCount: freeSpace)

                    // Warn if less than 1GB free
                    if freeSpace < 1_000_000_000 {
                        print("  ⚠️  Low disk space: \(freeSpaceString) available")
                        return 1
                    } else {
                        print("  ✅ Disk space: \(freeSpaceString) available")
                        return 0
                    }
                } else {
                    print("  ⚠️  Could not determine disk space")
                    return 1
                }

            } catch {
                print("  ❌ Failed to check disk space: \(error.localizedDescription)")
                return 1
            }
        }

        private func fixIssues() throws {
            print("Fixing detected issues...")

            let pathHelper = PathHelper.shared

            // Create missing directories
            do {
                try pathHelper.ensureVeloDirectories()
                print("  ✅ Created missing Velo directories")
            } catch {
                print("  ❌ Failed to create directories: \(error.localizedDescription)")
            }

            // TODO: Add more automatic fixes
            print("  ℹ️  Some issues may require manual intervention")
        }

        private func checkContextInformation() {
            print("Checking context information...")

            let context = ProjectContext()

            // Current directory
            let currentDir = FileManager.default.currentDirectoryPath
            print("  Current directory: \(currentDir)")

            // Project context detection
            if context.isProjectContext {
                print("  ✅ In project context (velo.json found)")

                if let projectRoot = context.projectRoot {
                    print("  📁 Project root: \(projectRoot.path)")
                }

                // Check velo.json and velo.lock
                if let manifestPath = context.manifestPath {
                    let manifestExists = FileManager.default.fileExists(atPath: manifestPath.path)
                    print("  📄 velo.json: \(manifestPath.path) \(manifestExists ? "✅" : "❌")")
                }

                if let lockPath = context.lockFilePath {
                    let lockExists = FileManager.default.fileExists(atPath: lockPath.path)
                    print("  🔒 velo.lock: \(lockPath.path) \(lockExists ? "✅" : "❌")")
                }

                // Local .velo directory
                let localVeloDir = URL(fileURLWithPath: currentDir).appendingPathComponent(".velo")
                let localVeloDirExists = FileManager.default.fileExists(atPath: localVeloDir.path)
                print("  📂 Local .velo: \(localVeloDir.path) \(localVeloDirExists ? "✅" : "❌")")

                // Local packages
                checkLocalPackages()

            } else {
                print("  ℹ️  In global context (no velo.json found)")
                print("     Run 'velo init' to create a new project")
            }

            // Global packages
            checkGlobalPackages()

            // Path resolution information
            checkPathResolution()
        }

        private func checkLocalPackages() {
            print("  📦 Local packages:")

            let localVeloDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".velo")
            let localCellarDir = localVeloDir.appendingPathComponent("Cellar")

            guard FileManager.default.fileExists(atPath: localCellarDir.path) else {
                print("     No local packages installed")
                return
            }

            do {
                let packages = try FileManager.default.contentsOfDirectory(atPath: localCellarDir.path)
                    .filter { !$0.hasPrefix(".") }

                if packages.isEmpty {
                    print("     No local packages installed")
                } else {
                    for package in packages.prefix(5) { // Show first 5
                        let packageDir = localCellarDir.appendingPathComponent(package)
                        let versions = (try? FileManager.default.contentsOfDirectory(atPath: packageDir.path)
                            .filter { !$0.hasPrefix(".") }) ?? []
                        print("     \(package): \(versions.joined(separator: ", "))")
                    }
                    if packages.count > 5 {
                        print("     ... and \(packages.count - 5) more")
                    }
                }
            } catch {
                print("     ❌ Failed to read local packages: \(error.localizedDescription)")
            }
        }

        private func checkGlobalPackages() {
            print("  🌍 Global packages:")

            let pathHelper = PathHelper.shared
            let globalCellarDir = pathHelper.cellarPath

            guard FileManager.default.fileExists(atPath: globalCellarDir.path) else {
                print("     No global packages installed")
                return
            }

            do {
                let packages = try FileManager.default.contentsOfDirectory(atPath: globalCellarDir.path)
                    .filter { !$0.hasPrefix(".") }

                if packages.isEmpty {
                    print("     No global packages installed")
                } else {
                    for package in packages.prefix(5) { // Show first 5
                        let versions = pathHelper.installedVersions(for: package)
                        print("     \(package): \(versions.joined(separator: ", "))")
                    }
                    if packages.count > 5 {
                        print("     ... and \(packages.count - 5) more")
                    }
                }
            } catch {
                print("     ❌ Failed to read global packages: \(error.localizedDescription)")
            }
        }

        private func checkPathResolution() {
            print("  🛤️  Path resolution:")

            let pathHelper = PathHelper.shared
            let context = ProjectContext()

            // Show PATH order
            if context.isProjectContext {
                let localBinDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(".velo")
                    .appendingPathComponent("bin")

                if FileManager.default.fileExists(atPath: localBinDir.path) {
                    print("     1. Local (.velo/bin): \(localBinDir.path)")
                } else {
                    print("     1. Local (.velo/bin): Not configured")
                }
            }

            print("     \(context.isProjectContext ? "2" : "1"). Global (~/.velo/bin): \(pathHelper.binPath.path)")
            print("     \(context.isProjectContext ? "3" : "2"). System PATH: /usr/local/bin, /usr/bin, etc.")

            // Example resolution for common tools
            let commonTools = ["wget", "node", "python"]
            for tool in commonTools {
                if let resolvedPath = resolveCommand(tool) {
                    let isLocal = resolvedPath.contains("/.velo/")
                    let scope = isLocal ? (resolvedPath.contains("/.velo/bin/") ? "global" : "local") : "system"
                    print("     \(tool) → \(scope): \(resolvedPath)")
                } else {
                    print("     \(tool) → not found")
                }
            }
        }

        private func resolveCommand(_ command: String) -> String? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [command]

            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else { return nil }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return nil
            }
        }
        
    }
}
