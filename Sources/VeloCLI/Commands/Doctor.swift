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

            // Check symlink health
            issueCount += checkSymlinkHealth()

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
            let veloPath = pathHelper.binPath.path

            // Check if Velo is in PATH at all
            guard pathHelper.isInPath() else {
                print("  ❌ ~/.velo/bin is not in PATH")
                print("     Add this to your shell profile:")
                print("     echo 'export PATH=\"$HOME/.velo/bin:$PATH\"' >> ~/.zshrc")
                print("     Or run: velo install-self")
                return 1
            }

            // Check PATH position
            let pathPosition = checkVeloPathPosition(veloPath: veloPath)

            switch pathPosition {
            case .first:
                print("  ✅ ~/.velo/bin is first in PATH")
                print("     ℹ️  This ensures #!/usr/bin/env python3 uses Velo Python")
                return 0
            case .notFirst(let position):
                print("  ⚠️  ~/.velo/bin is in PATH but not first (position \(position))")
                print("     This may prevent #!/usr/bin/env python3 from using Velo Python")
                print("     Run 'velo install-self' to fix PATH ordering")
                return 1
            case .notFound:
                print("  ❌ ~/.velo/bin not found in PATH (inconsistent state)")
                print("     Run 'velo install-self' to fix PATH setup")
                return 1
            }
        }

        private enum PathPosition {
            case first
            case notFirst(Int)
            case notFound
        }

        private func checkVeloPathPosition(veloPath: String) -> PathPosition {
            guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
                return .notFound
            }

            let pathComponents = pathEnv.components(separatedBy: ":")
                .filter { !$0.isEmpty }

            // Check for various Velo path representations
            let veloPathVariants = [
                veloPath,
                "$HOME/.velo/bin",
                "~/.velo/bin",
                NSString(string: veloPath).expandingTildeInPath
            ]

            for (index, component) in pathComponents.enumerated() {
                let expandedComponent = NSString(string: component).expandingTildeInPath

                if veloPathVariants.contains(component) || veloPathVariants.contains(expandedComponent) {
                    return index == 0 ? .first : .notFirst(index + 1)
                }
            }

            return .notFound
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

        private func checkSymlinkHealth() -> Int {
            print("Checking symlink health...")

            let pathHelper = PathHelper.shared
            let receiptManager = ReceiptManager(pathHelper: pathHelper)
            var issues = 0

            // Check if bin directory exists
            guard FileManager.default.fileExists(atPath: pathHelper.binPath.path) else {
                print("  ℹ️  No bin directory found (no symlinks to check)")
                return 0
            }

            do {
                // Get all symlinks in bin directory
                let binContents = try FileManager.default.contentsOfDirectory(atPath: pathHelper.binPath.path)
                let symlinks = binContents.filter { filename in
                    let symlinkPath = pathHelper.binPath.appendingPathComponent(filename)
                    return isSymlink(at: symlinkPath)
                }

                if symlinks.isEmpty {
                    print("  ℹ️  No symlinks found in bin directory")
                    return 0
                }

                if verbose {
                    print("  📊 Found \(symlinks.count) symlinks to check")
                }

                var brokenSymlinks: [String] = []
                var orphanedSymlinks: [String] = []
                var validSymlinks = 0

                // Check each symlink
                for symlink in symlinks {
                    let symlinkPath = pathHelper.binPath.appendingPathComponent(symlink)

                    do {
                        let targetPath = try FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath.path)

                        // Check if target exists
                        if !FileManager.default.fileExists(atPath: targetPath) {
                            brokenSymlinks.append("\(symlink) → \(targetPath)")
                            issues += 1
                        } else {
                            // Check if target is part of a valid Velo package
                            if targetPath.contains("/.velo/Cellar/") {
                                let packageName = extractPackageNameFromSymlinkTarget(targetPath)
                                if let pkg = packageName, !pathHelper.isPackageInstalled(pkg) {
                                    orphanedSymlinks.append("\(symlink) → \(pkg) (package not installed)")
                                    issues += 1
                                } else {
                                    validSymlinks += 1
                                    if verbose {
                                        print("  ✅ \(symlink) → \(targetPath)")
                                    }
                                }
                            } else {
                                // Non-Velo symlink (might be system tool or custom)
                                validSymlinks += 1
                                if verbose {
                                    print("  ✅ \(symlink) → \(targetPath) (external)")
                                }
                            }
                        }
                    } catch {
                        brokenSymlinks.append("\(symlink) (unreadable: \(error.localizedDescription))")
                        issues += 1
                    }
                }

                // Report results
                if !brokenSymlinks.isEmpty {
                    print("  ❌ Broken symlinks (\(brokenSymlinks.count)):")
                    for broken in brokenSymlinks.prefix(5) {
                        print("     \(broken)")
                    }
                    if brokenSymlinks.count > 5 {
                        print("     ... and \(brokenSymlinks.count - 5) more")
                    }
                }

                if !orphanedSymlinks.isEmpty {
                    print("  ⚠️  Orphaned symlinks (\(orphanedSymlinks.count)):")
                    for orphaned in orphanedSymlinks.prefix(5) {
                        print("     \(orphaned)")
                    }
                    if orphanedSymlinks.count > 5 {
                        print("     ... and \(orphanedSymlinks.count - 5) more")
                    }
                }

                if issues == 0 {
                    print("  ✅ All \(validSymlinks) symlinks are healthy")
                }

                // Check for missing symlinks
                issues += checkForMissingSymlinks(pathHelper: pathHelper, receiptManager: receiptManager)

                return issues

            } catch {
                print("  ❌ Failed to check symlinks: \(error.localizedDescription)")
                return 1
            }
        }

        private func checkForMissingSymlinks(pathHelper: PathHelper, receiptManager: ReceiptManager) -> Int {
            var issues = 0

            do {
                // Check all installed packages for missing symlinks
                let packages = try FileManager.default.contentsOfDirectory(atPath: pathHelper.cellarPath.path)
                    .filter { !$0.hasPrefix(".") }

                var missingSymlinks: [(package: String, version: String, binary: String)] = []

                for package in packages {
                    let versions = pathHelper.installedVersions(for: package)

                    for version in versions {
                        // Check if this package should have symlinks
                        let shouldHaveSymlinks: Bool
                        if let receipt = try? receiptManager.loadReceipt(for: package, version: version) {
                            shouldHaveSymlinks = receipt.installedAs == .explicit
                        } else {
                            // No receipt - assume explicit installation for older packages
                            shouldHaveSymlinks = true
                        }

                        if shouldHaveSymlinks {
                            let packageDir = pathHelper.packagePath(for: package, version: version)
                            let binDir = packageDir.appendingPathComponent("bin")

                            if FileManager.default.fileExists(atPath: binDir.path) {
                                let binaries = try FileManager.default.contentsOfDirectory(atPath: binDir.path)
                                    .filter { !$0.hasPrefix(".") }

                                for binary in binaries {
                                    let symlinkPath = pathHelper.symlinkPath(for: binary)

                                    if !FileManager.default.fileExists(atPath: symlinkPath.path) {
                                        missingSymlinks.append((package: package, version: version, binary: binary))
                                        issues += 1
                                    }
                                }
                            }
                        }
                    }
                }

                if !missingSymlinks.isEmpty {
                    print("  ⚠️  Missing symlinks for explicitly installed packages (\(missingSymlinks.count)):")
                    for missing in missingSymlinks.prefix(5) {
                        print("     \(missing.binary) (from \(missing.package) \(missing.version))")
                    }
                    if missingSymlinks.count > 5 {
                        print("     ... and \(missingSymlinks.count - 5) more")
                    }
                    if fix {
                        print("     💡 Run 'velo doctor --fix' to recreate missing symlinks")
                    }
                }

                return issues

            } catch {
                if verbose {
                    print("  ⚠️  Could not check for missing symlinks: \(error.localizedDescription)")
                }
                return 0
            }
        }

        private func extractPackageNameFromSymlinkTarget(_ targetPath: String) -> String? {
            // Extract package name from path like ~/.velo/Cellar/package-name/version/bin/binary
            let components = targetPath.components(separatedBy: "/")

            if let cellarIndex = components.lastIndex(of: "Cellar"),
               cellarIndex + 1 < components.count {
                return components[cellarIndex + 1]
            }

            return nil
        }

        private func isSymlink(at url: URL) -> Bool {
            do {
                let resourceValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                return resourceValues.isSymbolicLink ?? false
            } catch {
                return false
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
            try runAsyncAndWait {
                try await self.fixIssuesAsync()
            }
        }

        private func fixIssuesAsync() async throws {
            print("Fixing detected issues...")

            let pathHelper = PathHelper.shared
            let installer = Installer(pathHelper: pathHelper)
            let receiptManager = ReceiptManager(pathHelper: pathHelper)

            // Create missing directories
            do {
                try pathHelper.ensureVeloDirectories()
                print("  ✅ Created missing Velo directories")
            } catch {
                print("  ❌ Failed to create directories: \(error.localizedDescription)")
            }

            // Fix symlink issues
            try await fixSymlinkIssues(pathHelper: pathHelper, installer: installer, receiptManager: receiptManager)

            print("  ℹ️  Some issues may require manual intervention")
        }

        private func fixSymlinkIssues(pathHelper: PathHelper, installer: Installer, receiptManager: ReceiptManager) async throws {
            print("  🔗 Fixing symlink issues...")

            guard FileManager.default.fileExists(atPath: pathHelper.binPath.path) else {
                return // No bin directory to fix
            }

            var fixedCount = 0
            var failedCount = 0

            // Remove broken symlinks
            do {
                let binContents = try FileManager.default.contentsOfDirectory(atPath: pathHelper.binPath.path)
                let symlinks = binContents.filter { filename in
                    let symlinkPath = pathHelper.binPath.appendingPathComponent(filename)
                    return isSymlink(at: symlinkPath)
                }

                for symlink in symlinks {
                    let symlinkPath = pathHelper.binPath.appendingPathComponent(symlink)

                    do {
                        let targetPath = try FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath.path)

                        // Remove broken symlinks
                        if !FileManager.default.fileExists(atPath: targetPath) {
                            try FileManager.default.removeItem(at: symlinkPath)
                            print("    ✅ Removed broken symlink: \(symlink)")
                            fixedCount += 1
                        }
                    } catch {
                        // Symlink is unreadable, remove it
                        try? FileManager.default.removeItem(at: symlinkPath)
                        print("    ✅ Removed unreadable symlink: \(symlink)")
                        fixedCount += 1
                    }
                }
            } catch {
                print("    ❌ Failed to clean broken symlinks: \(error.localizedDescription)")
                failedCount += 1
            }

            // Recreate missing symlinks for explicitly installed packages
            do {
                let packages = try FileManager.default.contentsOfDirectory(atPath: pathHelper.cellarPath.path)
                    .filter { !$0.hasPrefix(".") }

                for package in packages {
                    let versions = pathHelper.installedVersions(for: package)

                    for version in versions {
                        // Check if this package should have symlinks
                        let shouldHaveSymlinks: Bool
                        if let receipt = try? receiptManager.loadReceipt(for: package, version: version) {
                            shouldHaveSymlinks = receipt.installedAs == .explicit
                        } else {
                            // No receipt - assume explicit installation for older packages
                            shouldHaveSymlinks = true
                        }

                        if shouldHaveSymlinks {
                            let packageDir = pathHelper.packagePath(for: package, version: version)

                            do {
                                // Create a formula for symlink creation
                                let formula = Formula(
                                    name: package,
                                    description: "",
                                    homepage: "",
                                    url: "",
                                    sha256: "",
                                    version: version
                                )

                                // Use installer to recreate symlinks
                                try await installer.createSymlinksForExistingPackage(formula: formula, packageDir: packageDir)
                                print("    ✅ Recreated symlinks for \(package) \(version)")
                                fixedCount += 1
                            } catch {
                                print("    ❌ Failed to recreate symlinks for \(package) \(version): \(error.localizedDescription)")
                                failedCount += 1
                            }
                        }
                    }
                }
            } catch {
                print("    ❌ Failed to recreate missing symlinks: \(error.localizedDescription)")
                failedCount += 1
            }

            if fixedCount > 0 {
                print("    ✅ Fixed \(fixedCount) symlink issue(s)")
            }
            if failedCount > 0 {
                print("    ❌ Failed to fix \(failedCount) symlink issue(s)")
            }
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
            let commonTools = ["wget", "node", "python3"]
            for tool in commonTools {
                if let resolvedPath = resolveCommand(tool) {
                    let isLocal = resolvedPath.contains("/.velo/")
                    let scope = isLocal ? (resolvedPath.contains("/.velo/bin/") ? "global" : "local") : "system"
                    let status = (tool == "python3" && scope == "global") ? "✅" : ""
                    print("     \(tool) → \(scope): \(resolvedPath) \(status)")

                    // Special check for python3 resolution
                    if tool == "python3" && scope != "global" {
                        print("       ⚠️  python3 should resolve to Velo for #!/usr/bin/env python3 scripts")
                    }
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
