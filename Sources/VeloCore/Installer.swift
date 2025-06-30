import Foundation
import VeloSystem
import VeloFormula

public protocol InstallationProgress {
    func installationDidStart(package: String, version: String)
    func extractionDidStart(totalFiles: Int?)
    func extractionDidUpdate(filesExtracted: Int, totalFiles: Int?)
    func linkingDidStart(binariesCount: Int)
    func linkingDidUpdate(binariesLinked: Int, totalBinaries: Int)
    func installationDidComplete(package: String)
    func installationDidFail(package: String, error: Error)
}

public final class Installer {
    private let pathHelper: PathHelper
    private let fileManager = FileManager.default

    public init(pathHelper: PathHelper = PathHelper.shared) {
        self.pathHelper = pathHelper
    }

    public func install(
        formula: Formula,
        from bottleFile: URL,
        progress: InstallationProgress? = nil
    ) async throws {
        progress?.installationDidStart(package: formula.name, version: formula.version)

        // Ensure Velo directories exist
        try pathHelper.ensureVeloDirectories()

        // Check if this specific version is already installed
        if pathHelper.isSpecificVersionInstalled(formula.name, version: formula.version) {
            throw VeloError.alreadyInstalled(package: "\(formula.name) v\(formula.version)")
        }

        // Create package directory
        let packageDir = pathHelper.packagePath(for: formula.name, version: formula.version)
        try pathHelper.ensureDirectoryExists(at: packageDir)

        do {
            // Extract bottle
            try await extractBottle(from: bottleFile, to: packageDir, progress: progress)

            // Rewrite library paths for Homebrew bottle compatibility
            try await rewriteLibraryPaths(for: formula, packageDir: packageDir)

            // Create symlinks
            try await createSymlinks(for: formula, packageDir: packageDir, progress: progress)

            // Create opt symlink for Homebrew compatibility
            try pathHelper.createOptSymlink(for: formula.name, version: formula.version)

            // Ensure all existing packages have opt symlinks (retroactive fix)
            try pathHelper.ensureAllOptSymlinks()

            progress?.installationDidComplete(package: formula.name)

        } catch {
            // Clean up on failure
            try? fileManager.removeItem(at: packageDir)
            progress?.installationDidFail(package: formula.name, error: error)
            throw error
        }
    }

    public func uninstall(package: String) throws {
        guard pathHelper.isPackageInstalled(package) else {
            throw VeloError.formulaNotFound(name: package)
        }

        let packageBaseDir = pathHelper.cellarPath.appendingPathComponent(package)
        let versions = pathHelper.installedVersions(for: package)

        // Remove all symlinks for this package
        for version in versions {
            let packageDir = pathHelper.packagePath(for: package, version: version)
            try removeSymlinks(for: package, version: version, packageDir: packageDir)
        }

        // Remove opt symlink
        try pathHelper.removeOptSymlink(for: package)

        // Remove package directory
        try fileManager.removeItem(at: packageBaseDir)
    }

    public func uninstallVersion(package: String, version: String) throws {
        guard pathHelper.isSpecificVersionInstalled(package, version: version) else {
            throw VeloError.formulaNotFound(name: "\(package) v\(version)")
        }

        let packageDir = pathHelper.packagePath(for: package, version: version)

        // Remove symlinks for this specific version
        try removeSymlinks(for: package, version: version, packageDir: packageDir)

        // Remove this version's directory
        try fileManager.removeItem(at: packageDir)

        // Check remaining versions after removal
        let remainingVersions = pathHelper.installedVersions(for: package)
        if remainingVersions.isEmpty {
            // This was the last version, remove opt symlink
            try pathHelper.removeOptSymlink(for: package)
        } else if let latestVersion = remainingVersions.last {
            // Update opt symlink to point to latest remaining version
            try pathHelper.createOptSymlink(for: package, version: latestVersion)

            // Also update default binary symlinks to point to latest version
            try pathHelper.setDefaultVersion(for: package, version: latestVersion)
        }
    }

    // MARK: - Extraction

    private func extractBottle(
        from bottleFile: URL,
        to destination: URL,
        progress: InstallationProgress?
    ) async throws {
        progress?.extractionDidStart(totalFiles: nil)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-xf", bottleFile.path,
            "-C", destination.path,  // Extract to destination directory
            "--strip-components=2"  // Strip 2 levels: package/version/...
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw VeloError.extractionFailed(reason: errorOutput)
        }

        // Count extracted files for progress
        let extractedFiles = try countFiles(in: destination)
        progress?.extractionDidUpdate(filesExtracted: extractedFiles, totalFiles: extractedFiles)
    }

    // MARK: - Symlink Management

    private func createSymlinks(
        for formula: Formula,
        packageDir: URL,
        progress: InstallationProgress?
    ) async throws {
        let binDir = packageDir.appendingPathComponent("bin")
        var totalBinaries = 0
        var linkedBinaries = 0

        // Count total binaries from both bin/ and libexec/bin/
        var binDirectories: [URL] = []
        
        if fileManager.fileExists(atPath: binDir.path) {
            binDirectories.append(binDir)
            let binaries = try fileManager.contentsOfDirectory(atPath: binDir.path)
                .filter { !$0.hasPrefix(".") }
            totalBinaries += binaries.count
        }

        let libexecBinDir = packageDir.appendingPathComponent("libexec/bin")
        if fileManager.fileExists(atPath: libexecBinDir.path) {
            binDirectories.append(libexecBinDir)
            let libexecBinaries = try fileManager.contentsOfDirectory(atPath: libexecBinDir.path)
                .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".pyc") }
            totalBinaries += libexecBinaries.count
        }

        progress?.linkingDidStart(binariesCount: totalBinaries)

        // Process main bin directory first
        if fileManager.fileExists(atPath: binDir.path) {
            let binaries = try fileManager.contentsOfDirectory(atPath: binDir.path)
                .filter { !$0.hasPrefix(".") }

            for binary in binaries {
                let sourcePath = binDir.appendingPathComponent(binary)

                // Create versioned symlink (e.g., python3.9@3.9.23)
                let versionedPath = pathHelper.versionedSymlinkPath(for: binary, package: formula.name, version: formula.version)
                try pathHelper.createSymlink(from: sourcePath, to: versionedPath)

                // Create or update default symlink (e.g., python3.9)
                let defaultPath = pathHelper.symlinkPath(for: binary)
                try pathHelper.createSymlink(from: sourcePath, to: defaultPath)

                linkedBinaries += 1
                progress?.linkingDidUpdate(binariesLinked: linkedBinaries, totalBinaries: totalBinaries)
            }
        }

        // Process libexec/bin directory for unversioned command aliases
        if fileManager.fileExists(atPath: libexecBinDir.path) {
            let libexecBinaries = try fileManager.contentsOfDirectory(atPath: libexecBinDir.path)
                .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".pyc") }

            for binary in libexecBinaries {
                let sourcePath = libexecBinDir.appendingPathComponent(binary)
                
                // For libexec/bin entries, check if they are symlinks to bin/ directory
                let linkTarget: URL
                if fileManager.fileExists(atPath: sourcePath.path) {
                    do {
                        // Try to resolve the symlink target
                        let targetPath = try fileManager.destinationOfSymbolicLink(atPath: sourcePath.path)
                        linkTarget = URL(fileURLWithPath: targetPath, relativeTo: sourcePath.deletingLastPathComponent())
                    } catch {
                        // If not a symlink, use the file directly
                        linkTarget = sourcePath
                    }
                } else {
                    linkTarget = sourcePath
                }

                // Create versioned symlink for unversioned command (e.g., python@3.9.23_3)
                let versionedPath = pathHelper.versionedSymlinkPath(for: binary, package: formula.name, version: formula.version)
                try pathHelper.createSymlink(from: linkTarget, to: versionedPath)

                // Create or update default symlink for unversioned command (e.g., python)
                let defaultPath = pathHelper.symlinkPath(for: binary)
                try pathHelper.createSymlink(from: linkTarget, to: defaultPath)

                linkedBinaries += 1
                progress?.linkingDidUpdate(binariesLinked: linkedBinaries, totalBinaries: totalBinaries)
            }
        }

        if totalBinaries == 0 {
            progress?.linkingDidStart(binariesCount: 0)
        }
    }

    private func removeSymlinks(for package: String, version: String, packageDir: URL) throws {
        // Process both bin/ and libexec/bin/ directories
        let directories = [
            packageDir.appendingPathComponent("bin"),
            packageDir.appendingPathComponent("libexec/bin")
        ]

        for directory in directories {
            guard fileManager.fileExists(atPath: directory.path) else {
                continue
            }

            let binaries = try fileManager.contentsOfDirectory(atPath: directory.path)
                .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".pyc") }

            for binary in binaries {
                // Remove versioned symlink (e.g., python@3.9.23_3)
                let versionedSymlinkPath = pathHelper.versionedSymlinkPath(for: binary, package: package, version: version)
                if fileManager.fileExists(atPath: versionedSymlinkPath.path) {
                    try fileManager.removeItem(at: versionedSymlinkPath)
                }

                // Only remove default symlink if it points to this version
                let defaultSymlinkPath = pathHelper.symlinkPath(for: binary)
                if fileManager.fileExists(atPath: defaultSymlinkPath.path) {
                    let targetBinary = directory.appendingPathComponent(binary)
                    
                    // For libexec/bin symlinks, need to resolve the actual target
                    let actualTarget: URL
                    if directory.lastPathComponent == "bin" && directory.deletingLastPathComponent().lastPathComponent == "libexec" {
                        // This is from libexec/bin, need to resolve symlink target
                        do {
                            let targetPath = try fileManager.destinationOfSymbolicLink(atPath: targetBinary.path)
                            actualTarget = URL(fileURLWithPath: targetPath, relativeTo: targetBinary.deletingLastPathComponent())
                        } catch {
                            actualTarget = targetBinary
                        }
                    } else {
                        actualTarget = targetBinary
                    }
                    
                    if let resolvedPath = try? fileManager.destinationOfSymbolicLink(atPath: defaultSymlinkPath.path),
                       resolvedPath == actualTarget.path {
                        try fileManager.removeItem(at: defaultSymlinkPath)

                        // Try to find another version to link as default
                        try updateDefaultSymlinkAfterRemoval(for: package, binary: binary)
                    }
                }
            }
        }
    }

    private func updateDefaultSymlinkAfterRemoval(for package: String, binary: String) throws {
        let remainingVersions = pathHelper.installedVersions(for: package)
        guard let latestVersion = remainingVersions.last else {
            return // No versions left
        }

        let latestPackageDir = pathHelper.packagePath(for: package, version: latestVersion)
        let latestBinDir = latestPackageDir.appendingPathComponent("bin")
        let latestBinaryPath = latestBinDir.appendingPathComponent(binary)

        // Only create default symlink if this binary exists in the latest version
        if fileManager.fileExists(atPath: latestBinaryPath.path) {
            let defaultSymlinkPath = pathHelper.symlinkPath(for: binary)
            try pathHelper.createSymlink(from: latestBinaryPath, to: defaultSymlinkPath)
        }
    }

    // MARK: - Library Path Rewriting

    private func rewriteLibraryPaths(for formula: Formula, packageDir: URL) async throws {
        // Find all binaries in the package
        let binDir = packageDir.appendingPathComponent("bin")

        guard fileManager.fileExists(atPath: binDir.path) else {
            return // No binaries to rewrite
        }

        let binaries = try fileManager.contentsOfDirectory(atPath: binDir.path)
            .filter { !$0.hasPrefix(".") }

        for binary in binaries {
            let binaryPath = binDir.appendingPathComponent(binary)
            try await rewriteBinaryLibraryPaths(binaryPath: binaryPath)
        }

        // Also rewrite any dynamic libraries in the package
        let libDir = packageDir.appendingPathComponent("lib")
        if fileManager.fileExists(atPath: libDir.path) {
            try await rewriteLibraryDirectory(libDir)
        }
    }

    private func rewriteBinaryLibraryPaths(binaryPath: URL) async throws {
        // Check if binary needs library path rewriting
        guard try await binaryNeedsPathRewriting(binaryPath: binaryPath) else {
            return // Skip if no placeholders found
        }

        logInfo("🔧 Rewriting library paths for \(binaryPath.lastPathComponent)")

        // Prepare binary for modification
        try prepareForModification(binaryPath: binaryPath)

        // Use install_name_tool to rewrite library paths
        // Replace @@HOMEBREW_PREFIX@@ with our Velo prefix
        let veloPrefix = pathHelper.veloPrefix

        // First, get the current library dependencies
        let otoolProcess = Process()
        otoolProcess.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        otoolProcess.arguments = ["-L", binaryPath.path]

        let otoolPipe = Pipe()
        otoolProcess.standardOutput = otoolPipe
        otoolProcess.standardError = otoolPipe

        try otoolProcess.run()
        otoolProcess.waitUntilExit()

        guard otoolProcess.terminationStatus == 0 else {
            throw VeloError.libraryPathRewriteFailed(
                binary: binaryPath.lastPathComponent,
                reason: "Failed to read library dependencies"
            )
        }

        let otoolOutput = otoolPipe.fileHandleForReading.readDataToEndOfFile()
        let dependencies = String(data: otoolOutput, encoding: .utf8) ?? ""

        // Find lines containing @@HOMEBREW_PREFIX@@ or @@HOMEBREW_CELLAR@@ and rewrite them
        let lines = dependencies.components(separatedBy: .newlines)
        var rewriteCount = 0
        var installNameFixed = false

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("@@HOMEBREW_PREFIX@@") || trimmed.contains("@@HOMEBREW_CELLAR@@") {
                // Extract the old path (everything before the first space)
                let components = trimmed.components(separatedBy: " ")
                guard let oldPath = components.first else { continue }

                // Replace both Homebrew placeholders with our Velo prefix
                var newPath = oldPath.replacingOccurrences(of: "@@HOMEBREW_PREFIX@@", with: veloPrefix.path)
                newPath = newPath.replacingOccurrences(of: "@@HOMEBREW_CELLAR@@", with: veloPrefix.path + "/Cellar")

                // Check if this is the first line (install name) or a dependency
                let isInstallName = index == 1 // otool -L output: line 0 is the file path, line 1 is install name
                
                if isInstallName && binaryPath.pathExtension == "dylib" {
                    // Fix the library's own install name (identity)
                    logInfo("  Rewriting install name: \(oldPath) -> \(newPath)")
                    
                    let installNameProcess = Process()
                    installNameProcess.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
                    installNameProcess.arguments = ["-id", newPath, binaryPath.path]

                    let installNamePipe = Pipe()
                    installNameProcess.standardOutput = installNamePipe
                    installNameProcess.standardError = installNamePipe

                    try installNameProcess.run()
                    installNameProcess.waitUntilExit()

                    if installNameProcess.terminationStatus != 0 {
                        let errorOutput = installNamePipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: errorOutput, encoding: .utf8) ?? "Unknown error"
                        logWarning("install_name_tool -id failed for \(binaryPath.lastPathComponent): \(errorString)")
                    } else {
                        rewriteCount += 1
                        installNameFixed = true
                    }
                } else {
                    // Fix dependency reference
                    logInfo("  Rewriting dependency: \(oldPath) -> \(newPath)")

                    let installNameProcess = Process()
                    installNameProcess.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
                    installNameProcess.arguments = ["-change", oldPath, newPath, binaryPath.path]

                    let installNamePipe = Pipe()
                    installNameProcess.standardOutput = installNamePipe
                    installNameProcess.standardError = installNamePipe

                    try installNameProcess.run()
                    installNameProcess.waitUntilExit()

                    if installNameProcess.terminationStatus != 0 {
                        let errorOutput = installNamePipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: errorOutput, encoding: .utf8) ?? "Unknown error"
                        logWarning("install_name_tool -change failed for \(binaryPath.lastPathComponent): \(errorString)")
                        throw VeloError.libraryPathRewriteFailed(
                            binary: binaryPath.lastPathComponent,
                            reason: "install_name_tool failed: \(errorString)"
                        )
                    } else {
                        rewriteCount += 1
                    }
                }
            }
        }

        if rewriteCount > 0 {
            logInfo("  ✓ Rewrote \(rewriteCount) library paths")
            
            // Verify the rewriting worked
            let verifySuccess = try await verifyPlaceholderReplacement(binaryPath: binaryPath)
            if !verifySuccess {
                logWarning("  ⚠️ Some placeholders remain unreplaced in \(binaryPath.lastPathComponent)")
            }
        }

        // Re-sign the binary after modifying library paths
        try await resignBinaryWithFallback(binaryPath: binaryPath)
    }

    private func resignBinary(binaryPath: URL) async throws {
        let codesignProcess = Process()
        codesignProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesignProcess.arguments = ["-s", "-", binaryPath.path, "--force"]

        let codesignPipe = Pipe()
        codesignProcess.standardOutput = codesignPipe
        codesignProcess.standardError = codesignPipe

        try codesignProcess.run()
        codesignProcess.waitUntilExit()

        if codesignProcess.terminationStatus != 0 {
            let errorOutput = codesignPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorOutput, encoding: .utf8) ?? "Unknown error"
            throw VeloError.libraryPathRewriteFailed(
                binary: binaryPath.lastPathComponent,
                reason: "Code signing failed: \(errorString)"
            )
        }
    }

    private func binaryNeedsPathRewriting(binaryPath: URL) async throws -> Bool {
        // Check if binary contains Homebrew placeholders
        let otoolProcess = Process()
        otoolProcess.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        otoolProcess.arguments = ["-L", binaryPath.path]

        let otoolPipe = Pipe()
        otoolProcess.standardOutput = otoolPipe
        otoolProcess.standardError = otoolPipe

        try otoolProcess.run()
        otoolProcess.waitUntilExit()

        guard otoolProcess.terminationStatus == 0 else {
            return false // Can't read dependencies, skip
        }

        let otoolOutput = otoolPipe.fileHandleForReading.readDataToEndOfFile()
        let dependencies = String(data: otoolOutput, encoding: .utf8) ?? ""

        return dependencies.contains("@@HOMEBREW_PREFIX@@") || dependencies.contains("@@HOMEBREW_CELLAR@@")
    }

    private func verifyPlaceholderReplacement(binaryPath: URL) async throws -> Bool {
        // Check if any Homebrew placeholders remain after rewriting
        let otoolProcess = Process()
        otoolProcess.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        otoolProcess.arguments = ["-L", binaryPath.path]

        let otoolPipe = Pipe()
        otoolProcess.standardOutput = otoolPipe
        otoolProcess.standardError = otoolPipe

        try otoolProcess.run()
        otoolProcess.waitUntilExit()

        guard otoolProcess.terminationStatus == 0 else {
            return false // Can't verify, assume failure
        }

        let otoolOutput = otoolPipe.fileHandleForReading.readDataToEndOfFile()
        let dependencies = String(data: otoolOutput, encoding: .utf8) ?? ""

        // Return true if NO placeholders remain (success), false if placeholders still exist
        return !dependencies.contains("@@HOMEBREW_PREFIX@@") && !dependencies.contains("@@HOMEBREW_CELLAR@@")
    }

    private func prepareForModification(binaryPath: URL) throws {
        // Make file writable first
        try makeFileWritable(at: binaryPath)

        // Remove existing signature if present
        try removeExistingSignature(binaryPath: binaryPath)

        // Clear extended attributes that might interfere with signing
        try clearExtendedAttributes(binaryPath: binaryPath)
    }

    private func clearExtendedAttributes(binaryPath: URL) throws {
        let xattrProcess = Process()
        xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProcess.arguments = ["-c", binaryPath.path]

        // Suppress all output to avoid noise
        xattrProcess.standardOutput = Pipe()
        xattrProcess.standardError = Pipe()

        // Ignore errors - some files may not have extended attributes
        try? xattrProcess.run()
        xattrProcess.waitUntilExit()
    }

    private func removeExistingSignature(binaryPath: URL) throws {
        let codesignProcess = Process()
        codesignProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesignProcess.arguments = ["--remove-signature", binaryPath.path]

        // Ignore errors - some files may not be signed
        try? codesignProcess.run()
        codesignProcess.waitUntilExit()
    }

    private func resignBinaryWithFallback(binaryPath: URL) async throws {
        do {
            try await resignBinary(binaryPath: binaryPath)
        } catch {
            // If signing fails, check if binary works without signing
            let binaryName = binaryPath.lastPathComponent
            print("⚠️  Warning: Could not sign \(binaryName), but installation will continue")
            print("   Reason: \(error.localizedDescription)")
            // Don't throw - allow installation to continue
        }
    }

    private func makeFileWritable(at url: URL) throws {
        var attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let permissions = attributes[.posixPermissions] as? NSNumber {
            let newPermissions = permissions.uint16Value | 0o200 // Add write permission for owner
            attributes[.posixPermissions] = NSNumber(value: newPermissions)
            try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        }
    }

    private func rewriteLibraryDirectory(_ libDir: URL) async throws {
        // Rewrite library paths in .dylib files too
        let libraryFiles = try fileManager.contentsOfDirectory(atPath: libDir.path)
            .filter { $0.hasSuffix(".dylib") }

        for libraryFile in libraryFiles {
            let libraryPath = libDir.appendingPathComponent(libraryFile)
            try await rewriteBinaryLibraryPaths(binaryPath: libraryPath)
        }
    }

    // MARK: - Verification

    public func verifyInstallation(formula: Formula) throws -> InstallationStatus {
        let packageDir = pathHelper.packagePath(for: formula.name, version: formula.version)

        guard fileManager.fileExists(atPath: packageDir.path) else {
            return .notInstalled
        }

        // Check if binaries are properly linked
        let binDir = packageDir.appendingPathComponent("bin")
        if fileManager.fileExists(atPath: binDir.path) {
            let binaries = try fileManager.contentsOfDirectory(atPath: binDir.path)
                .filter { !$0.hasPrefix(".") }

            for binary in binaries {
                let symlinkPath = pathHelper.symlinkPath(for: binary)
                if !fileManager.fileExists(atPath: symlinkPath.path) {
                    return .corrupted(reason: "Missing symlink for \(binary)")
                }

                // Verify symlink points to correct location
                let resolvedPath = try fileManager.destinationOfSymbolicLink(atPath: symlinkPath.path)
                let expectedPath = binDir.appendingPathComponent(binary).path
                if resolvedPath != expectedPath {
                    return .corrupted(reason: "Symlink \(binary) points to wrong location")
                }
            }
        }

        return .installed
    }

    // MARK: - Helper Methods

    private func countFiles(in directory: URL) throws -> Int {
        var count = 0
        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for _ in enumerator {
                count += 1
            }
        }
        return count
    }

    public enum InstallationStatus {
        case notInstalled
        case installed
        case corrupted(reason: String)

        public var isInstalled: Bool {
            switch self {
            case .installed:
                return true
            case .notInstalled, .corrupted:
                return false
            }
        }
    }
}

// MARK: - Convenience Extensions

extension Installer {
    /// Repair library paths for a specific binary or dylib file
    public func repairBinaryLibraryPaths(binaryPath: URL) async throws {
        try await rewriteBinaryLibraryPaths(binaryPath: binaryPath)
    }

    public func repairInstallation(formula: Formula, bottleFile: URL) async throws {
        // Uninstall if partially installed
        if pathHelper.isPackageInstalled(formula.name) {
            try uninstall(package: formula.name)
        }

        // Reinstall
        try await install(formula: formula, from: bottleFile)
    }

    public func upgradePackage(
        oldFormula: Formula,
        newFormula: Formula,
        bottleFile: URL,
        progress: InstallationProgress? = nil
    ) async throws {
        // Install new version first
        try await install(formula: newFormula, from: bottleFile, progress: progress)

        // Remove only the old version (not all versions)
        try uninstallVersion(package: oldFormula.name, version: oldFormula.version)
    }
}
