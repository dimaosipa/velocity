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
                logError("Package '\(packageName)' is not installed")
                throw ExitCode.failure
            }

            let versions = pathHelper.installedVersions(for: packageName)
            logInfo("Repairing \(packageName) (\(versions.count) version(s))...")

            for version in versions {
                try await repairPackageVersion(packageName, version: version, pathHelper: pathHelper)
            }

            Logger.shared.success("\(packageName) repair completed!")
        }

        private func repairAllPackages(pathHelper: PathHelper) async throws {
            let cellarPath = pathHelper.cellarPath
            guard FileManager.default.fileExists(atPath: cellarPath.path) else {
                logInfo("No packages installed to repair")
                return
            }

            let packages = try FileManager.default.contentsOfDirectory(atPath: cellarPath.path)
                .filter { !$0.hasPrefix(".") }
                .sorted()

            if packages.isEmpty {
                logInfo("No packages installed to repair")
                return
            }

            logInfo("Scanning \(packages.count) packages for repair issues...")

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
                Logger.shared.success("✅ All packages are healthy - no repairs needed!")
            } else {
                if dryRun {
                    logInfo("Found \(issuesFound) packages with issues that could be repaired")
                } else {
                    Logger.shared.success("✅ Repair completed: \(repairedCount)/\(issuesFound) packages fixed")
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
                    logInfo("  \(packageDisplayName): No issues found (forced repair skipped)")
                }
                return (hasIssues: false, fixed: false)
            }

            logInfo("  \(packageDisplayName): Found \(filesToRepair.count) files with unreplaced placeholders")

            if dryRun {
                for file in filesToRepair {
                    let relativePath = file.path.replacingOccurrences(of: packageDir.path + "/", with: "")
                    logInfo("    - \(relativePath)")
                }
                return (hasIssues: true, fixed: false)
            }

            // Perform the repair
            var fixedCount = 0
            let installer = Installer(pathHelper: pathHelper)

            for file in filesToRepair {
                do {
                    let relativePath = file.path.replacingOccurrences(of: packageDir.path + "/", with: "")
                    logInfo("    Repairing \(relativePath)...")
                    
                    try await installer.repairBinaryLibraryPaths(binaryPath: file)
                    fixedCount += 1
                } catch {
                    logWarning("    Failed to repair \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if fixedCount == filesToRepair.count {
                logInfo("  ✅ \(packageDisplayName): All \(fixedCount) files repaired successfully")
                return (hasIssues: true, fixed: true)
            } else {
                logWarning("  ⚠️ \(packageDisplayName): \(fixedCount)/\(filesToRepair.count) files repaired")
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

            return filesToRepair
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