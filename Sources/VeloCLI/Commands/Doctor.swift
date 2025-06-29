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
                        
                        let status = try installer.verifyInstallation(formula: formula)
                        
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
    }
}