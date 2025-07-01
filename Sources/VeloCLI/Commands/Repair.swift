import Foundation
import ArgumentParser
import VeloCore
import VeloFormula
import VeloSystem

extension Velo {
    struct Repair: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Repair existing package installations"
        )

        @Argument(help: "The package to repair (optional, repairs all if not specified)")
        var package: String?

        @Flag(help: "Show what would be repaired without making changes")
        var dryRun = false

        @Flag(help: "Force repair even if no issues are detected")
        var force = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let context = ProjectContext()
            let pathHelper = context.getPathHelper(preferLocal: false) // Always use global for repair

            if let packageName = package {
                // Repair specific package
                try await repairPackage(packageName, pathHelper: pathHelper)
            } else {
                // Repair all packages
                try await repairAllPackages(pathHelper: pathHelper)
            }
        }

        private func repairPackage(_ packageName: String, pathHelper: PathHelper) async throws {
            guard pathHelper.isPackageInstalled(packageName) else {
                OSLogger.shared.error("Package '\(packageName)' is not installed")
                throw ExitCode.failure
            }

            let versions = pathHelper.installedVersions(for: packageName)
            OSLogger.shared.info("Repairing \(packageName) (\(versions.count) version(s))...")

            for version in versions {
                try await repairPackageVersion(packageName, version: version, pathHelper: pathHelper)
            }

            OSLogger.shared.success("\(packageName) repair completed!")
        }

        private func repairAllPackages(pathHelper: PathHelper) async throws {
            let cellarPath = pathHelper.cellarPath
            guard FileManager.default.fileExists(atPath: cellarPath.path) else {
                OSLogger.shared.info("No packages installed to repair")
                return
            }

            let packages = try FileManager.default.contentsOfDirectory(atPath: cellarPath.path)
                .filter { !$0.hasPrefix(".") }
                .sorted()

            if packages.isEmpty {
                OSLogger.shared.info("No packages installed to repair")
                return
            }

            OSLogger.shared.info("Scanning \(packages.count) packages for repair issues...")

            var repairedCount = 0
            var issuesFound = 0

            for packageName in packages {
                let versions = pathHelper.installedVersions(for: packageName)
                
                for version in versions {
                    let (hasIssues, fixed) = try await repairPackageVersion(
                        packageName, 
                        version: version, 
                        pathHelper: pathHelper
                    )
                    
                    if hasIssues {
                        issuesFound += 1
                        if fixed {
                            repairedCount += 1
                        }
                    }
                }
            }

            if issuesFound == 0 {
                OSLogger.shared.success("✅ All packages are healthy - no repairs needed!")
            } else {
                if dryRun {
                    OSLogger.shared.info("Found \(issuesFound) packages with issues that could be repaired")
                } else {
                    OSLogger.shared.success("✅ Repair completed: \(repairedCount)/\(issuesFound) packages fixed")
                }
            }
        }

        @discardableResult
        private func repairPackageVersion(
            _ packageName: String, 
            version: String, 
            pathHelper: PathHelper
        ) async throws -> (hasIssues: Bool, fixed: Bool) {
            let packageDir = pathHelper.packagePath(for: packageName, version: version)
            let packageDisplayName = "\(packageName) \(version)"

            // Find all binary and dylib files that need repair
            let filesToRepair = try findFilesNeedingRepair(in: packageDir)

            if filesToRepair.isEmpty {
                if force {
                    OSLogger.shared.info("  \(packageDisplayName): No issues found (forced repair skipped)")
                }
                return (hasIssues: false, fixed: false)
            }

            OSLogger.shared.info("  \(packageDisplayName): Found \(filesToRepair.count) files with unreplaced placeholders")

            if dryRun {
                for file in filesToRepair {
                    let relativePath = file.path.replacingOccurrences(of: packageDir.path + "/", with: "")
                    OSLogger.shared.info("    - \(relativePath)")
                }
                return (hasIssues: true, fixed: false)
            }

            // Perform the repair
            var fixedCount = 0
            let installer = Installer(pathHelper: pathHelper)

            for file in filesToRepair {
                do {
                    let relativePath = file.path.replacingOccurrences(of: packageDir.path + "/", with: "")
                    OSLogger.shared.info("    Repairing \(relativePath)...")
                    
                    try await installer.repairBinaryLibraryPaths(binaryPath: file)
                    fixedCount += 1
                } catch {
                    OSLogger.shared.warning("    Failed to repair \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if fixedCount == filesToRepair.count {
                OSLogger.shared.info("  ✅ \(packageDisplayName): All \(fixedCount) files repaired successfully")
                return (hasIssues: true, fixed: true)
            } else {
                OSLogger.shared.warning("  ⚠️ \(packageDisplayName): \(fixedCount)/\(filesToRepair.count) files repaired")
                return (hasIssues: true, fixed: false)
            }
        }

        private func findFilesNeedingRepair(in packageDir: URL) throws -> [URL] {
            var filesToRepair: [URL] = []
            let fileManager = FileManager.default

            // Check binaries in bin/
            let binDir = packageDir.appendingPathComponent("bin")
            if fileManager.fileExists(atPath: binDir.path) {
                let binaries = try fileManager.contentsOfDirectory(atPath: binDir.path)
                    .filter { !$0.hasPrefix(".") }
                
                for binary in binaries {
                    let binaryPath = binDir.appendingPathComponent(binary)
                    if try fileNeedsRepair(binaryPath) {
                        filesToRepair.append(binaryPath)
                    }
                }
            }

            // Check dylib files in lib/
            let libDir = packageDir.appendingPathComponent("lib")
            if fileManager.fileExists(atPath: libDir.path) {
                let libraries = try fileManager.contentsOfDirectory(atPath: libDir.path)
                    .filter { $0.hasSuffix(".dylib") }
                
                for library in libraries {
                    let libraryPath = libDir.appendingPathComponent(library)
                    if try fileNeedsRepair(libraryPath) {
                        filesToRepair.append(libraryPath)
                    }
                }
            }

            // Check framework binaries (especially for Python, Node.js, etc.)
            let frameworksDir = packageDir.appendingPathComponent("Frameworks")
            if fileManager.fileExists(atPath: frameworksDir.path) {
                try scanFrameworksDirectory(frameworksDir, filesToRepair: &filesToRepair)
            }

            return filesToRepair
        }

        private func scanFrameworksDirectory(_ frameworksDir: URL, filesToRepair: inout [URL]) throws {
            let fileManager = FileManager.default
            
            // Recursively scan the Frameworks directory for Mach-O files
            if let enumerator = fileManager.enumerator(at: frameworksDir, includingPropertiesForKeys: [.isRegularFileKey, .isExecutableKey]) {
                for case let fileURL as URL in enumerator {
                    // Skip directories, symlinks, and obviously non-binary files
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey]),
                          resourceValues.isRegularFile == true else {
                        continue
                    }
                    
                    let fileName = fileURL.lastPathComponent
                    
                    // Check for framework executables and dynamic libraries
                    let isFrameworkBinary = fileName.hasSuffix(".dylib") || 
                                           fileName.hasSuffix(".so") ||
                                           resourceValues.isExecutable == true ||
                                           fileURL.pathExtension.isEmpty // Framework main binary (e.g., Python)
                    
                    // Skip obvious non-binary files
                    let skipExtensions = ["txt", "py", "pyc", "pyo", "h", "plist", "strings", "md", "rst", "html", "xml", "json"]
                    if skipExtensions.contains(fileURL.pathExtension.lowercased()) {
                        continue
                    }
                    
                    if isFrameworkBinary {
                        do {
                            if try fileNeedsRepair(fileURL) {
                                filesToRepair.append(fileURL)
                            }
                        } catch {
                            // If we can't read the file with otool, it's probably not a Mach-O binary
                            continue
                        }
                    }
                }
            }
        }

        private func fileNeedsRepair(_ filePath: URL) throws -> Bool {
            let otoolProcess = Process()
            otoolProcess.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
            otoolProcess.arguments = ["-L", filePath.path]

            let otoolPipe = Pipe()
            otoolProcess.standardOutput = otoolPipe
            otoolProcess.standardError = otoolPipe

            try otoolProcess.run()
            otoolProcess.waitUntilExit()

            guard otoolProcess.terminationStatus == 0 else {
                return false // Can't read, assume no repair needed
            }

            let otoolOutput = otoolPipe.fileHandleForReading.readDataToEndOfFile()
            let dependencies = String(data: otoolOutput, encoding: .utf8) ?? ""

            return dependencies.contains("@@HOMEBREW_PREFIX@@") || dependencies.contains("@@HOMEBREW_CELLAR@@")
        }
    }
}