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
        progress: InstallationProgress? = nil,
        force: Bool = false,
        shouldCreateSymlinks: Bool = true
    ) async throws {
        progress?.installationDidStart(package: formula.name, version: formula.version)

        // Ensure Velo directories exist
        try pathHelper.ensureVeloDirectories()

        // Check if this specific version is already installed (unless force is used)
        if !force && pathHelper.isSpecificVersionInstalled(formula.name, version: formula.version) {
            throw VeloError.alreadyInstalled(package: "\(formula.name) v\(formula.version)")
        }

        // Create package directory
        let packageDir = pathHelper.packagePath(for: formula.name, version: formula.version)
        
        // If force is used and package directory exists, remove it first for clean reinstall
        if force && fileManager.fileExists(atPath: packageDir.path) {
            OSLogger.shared.info("🔧 Force mode: removing existing package directory for clean reinstall", category: OSLogger.shared.installer)
            
            // First remove any existing symlinks for this package/version
            try removeSymlinks(for: formula.name, version: formula.version, packageDir: packageDir)
            
            // Then remove the package directory
            try fileManager.removeItem(at: packageDir)
        }
        
        try pathHelper.ensureDirectoryExists(at: packageDir)

        do {
            // Extract bottle
            try await extractBottle(from: bottleFile, to: packageDir, progress: progress)

            // Small delay to avoid file system race conditions during heavy I/O
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Rewrite library paths for Homebrew bottle compatibility
            try await rewriteLibraryPaths(for: formula, packageDir: packageDir)
            
            // Rewrite script files with Homebrew placeholders
            try await rewriteScriptFiles(packageDir: packageDir)

            // Create symlinks (only if requested)
            if shouldCreateSymlinks {
                try await createSymlinks(for: formula, packageDir: packageDir, progress: progress, force: force)
            }

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
        progress: InstallationProgress?,
        force: Bool = false
    ) async throws {
        let binDir = packageDir.appendingPathComponent("bin")
        var totalBinaries = 0
        var linkedBinaries = 0

        // Count total binaries from bin/, libexec/bin/, and Framework bins
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
        
        // Also check for Framework binaries (for Python, etc.)
        let frameworkBinDirs = try findFrameworkBinDirectories(in: packageDir)
        for frameworkBinDir in frameworkBinDirs {
            binDirectories.append(frameworkBinDir)
            let frameworkBinaries = try fileManager.contentsOfDirectory(atPath: frameworkBinDir.path)
                .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".pyc") }
            totalBinaries += frameworkBinaries.count
        }

        progress?.linkingDidStart(binariesCount: totalBinaries)

        // Track symlink creation statistics
        var createdSymlinks = 0
        var skippedSymlinks: [String] = []
        var failedSymlinks: [String] = []
        
        // Detect if package contains frameworks
        let hasFrameworks = try hasFrameworkDependencies(packageDir: packageDir)
        
        // Process all bin directories
        for directory in binDirectories {
            let binaries = try fileManager.contentsOfDirectory(atPath: directory.path)
                .filter { !$0.hasPrefix(".") && !$0.hasSuffix(".pyc") }

            for binary in binaries {
                let sourcePath = directory.appendingPathComponent(binary)
                
                // Check if this is a framework binary
                let isFrameworkBinary = isFrameworkBinary(path: sourcePath, packageDir: packageDir)
                
                if isFrameworkBinary && hasFrameworks {
                    // Use wrapper script for framework binaries
                    let (versionedResult, defaultResult) = try await createFrameworkSymlinks(
                        binaryName: binary,
                        sourcePath: sourcePath,
                        formula: formula,
                        packageDir: packageDir,
                        force: force
                    )
                    
                    switch versionedResult {
                    case .created:
                        createdSymlinks += 1
                    case .skipped(let reason):
                        skippedSymlinks.append("\(binary)@\(formula.version) (\(reason))")
                    case .failed(let error):
                        if force {
                            throw error
                        } else {
                            failedSymlinks.append("\(binary)@\(formula.version)")
                        }
                    }
                    
                    switch defaultResult {
                    case .created:
                        createdSymlinks += 1
                    case .skipped(let reason):
                        skippedSymlinks.append("\(binary) (\(reason))")
                    case .failed(let error):
                        if force {
                            throw error
                        } else {
                            failedSymlinks.append(binary)
                        }
                    }
                } else {
                    // Standard symlink creation for non-framework binaries
                    // Create versioned symlink
                    let versionedPath = pathHelper.versionedSymlinkPath(for: binary, package: formula.name, version: formula.version)
                    let versionedResult = pathHelper.createSymlinkWithConflictDetection(from: sourcePath, to: versionedPath, packageName: formula.name, force: force)
                    
                    switch versionedResult {
                    case .created:
                        createdSymlinks += 1
                    case .skipped(let reason):
                        skippedSymlinks.append("\(binary)@\(formula.version) (\(reason))")
                    case .failed(let error):
                        if force {
                            throw error // In force mode, failures should still throw
                        } else {
                            failedSymlinks.append("\(binary)@\(formula.version)")
                        }
                    }

                    // Create or update default symlink
                    let defaultPath = pathHelper.symlinkPath(for: binary)
                    let defaultResult = pathHelper.createSymlinkWithConflictDetection(from: sourcePath, to: defaultPath, packageName: formula.name, force: force)
                    
                    switch defaultResult {
                    case .created:
                        createdSymlinks += 1
                    case .skipped(let reason):
                        skippedSymlinks.append("\(binary) (\(reason))")
                    case .failed(let error):
                        if force {
                            throw error // In force mode, failures should still throw
                        } else {
                            failedSymlinks.append(binary)
                        }
                    }
                }

                linkedBinaries += 1
                progress?.linkingDidUpdate(binariesLinked: linkedBinaries, totalBinaries: totalBinaries)
            }
        }
        
        // Log symlink creation summary
        if !skippedSymlinks.isEmpty {
            OSLogger.shared.info("⚠️ Skipped \(skippedSymlinks.count) symlinks due to conflicts: \(skippedSymlinks.joined(separator: ", "))", category: OSLogger.shared.installer)
            OSLogger.shared.info("💡 Use versioned symlinks or --force to override conflicts", category: OSLogger.shared.installer)
        }
        
        if !failedSymlinks.isEmpty {
            OSLogger.shared.warning("❌ Failed to create \(failedSymlinks.count) symlinks: \(failedSymlinks.joined(separator: ", "))", category: OSLogger.shared.installer)
        }
        
        OSLogger.shared.info("✅ Created \(createdSymlinks) symlinks for \(formula.name)", category: OSLogger.shared.installer)


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
            let result = pathHelper.createSymlinkWithConflictDetection(from: latestBinaryPath, to: defaultSymlinkPath, packageName: package, force: false)
            
            switch result {
            case .created:
                OSLogger.shared.debug("✅ Updated default symlink for \(binary) -> \(package) \(latestVersion)", category: OSLogger.shared.installer)
            case .skipped(let reason):
                OSLogger.shared.info("⚠️ Skipped updating default symlink for \(binary): \(reason)", category: OSLogger.shared.installer)
            case .failed(let error):
                OSLogger.shared.warning("❌ Failed to update default symlink for \(binary): \(error.localizedDescription)", category: OSLogger.shared.installer)
            }
        }
    }

    // MARK: - Library Path Rewriting

    private func rewriteLibraryPaths(for formula: Formula, packageDir: URL) async throws {
        // Use recursive discovery to process ALL files in the package
        let allFiles = try findAllProcessableFiles(in: packageDir)
        
        for filePath in allFiles {
            // Skip symlinks to avoid duplicate processing
            let attributes = try? fileManager.attributesOfItem(atPath: filePath.path)
            if let fileType = attributes?[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
                continue
            }
            
            if try await isMachOBinary(at: filePath) {
                try await rewriteBinaryLibraryPaths(binaryPath: filePath)
            } else if try await isTextScript(at: filePath) {
                try await rewriteTextScript(at: filePath)
            }
        }
    }

    private func rewriteBinaryLibraryPaths(binaryPath: URL) async throws {
        // Check if binary needs library path rewriting
        guard try await binaryNeedsPathRewriting(binaryPath: binaryPath) else {
            return // Skip if no placeholders found
        }
        OSLogger.shared.verbose("🔧 Rewriting library paths for \(binaryPath.lastPathComponent)", category: OSLogger.shared.installer)

        // Prepare binary for modification
        try prepareForModification(binaryPath: binaryPath)

        // Use install_name_tool to rewrite library paths
        // Replace @@HOMEBREW_PREFIX@@ with @rpath for portability

        // First, get the current library dependencies
        let otoolProcess = Process()
        otoolProcess.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        otoolProcess.arguments = ["-L", binaryPath.path]

        let otoolPipe = Pipe()
        let errorPipe = Pipe()
        otoolProcess.standardOutput = otoolPipe
        otoolProcess.standardError = errorPipe

        try otoolProcess.run()
        otoolProcess.waitUntilExit()

        // Read output and ensure file handles are closed
        let otoolOutput = otoolPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        // Explicitly close file handles to prevent descriptor leaks
        try? otoolPipe.fileHandleForReading.close()
        try? otoolPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForWriting.close()

        guard otoolProcess.terminationStatus == 0 else {
            let errorString = String(data: errorOutput, encoding: .utf8) ?? "Unknown error"
            throw VeloError.libraryPathRewriteFailed(
                binary: binaryPath.lastPathComponent,
                reason: "Failed to read library dependencies: \(errorString)"
            )
        }

        let dependencies = String(data: otoolOutput, encoding: .utf8) ?? ""

        // Find lines containing @@HOMEBREW_PREFIX@@ or @@HOMEBREW_CELLAR@@ and rewrite them
        let lines = dependencies.components(separatedBy: .newlines)
        var rewriteCount = 0

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("@@HOMEBREW_PREFIX@@") || trimmed.contains("@@HOMEBREW_CELLAR@@") {
                // Extract the old path (everything before the first space)
                let components = trimmed.components(separatedBy: " ")
                guard let oldPath = components.first else { continue }

                // Replace both Homebrew placeholders with @rpath for portability
                // For @@HOMEBREW_PREFIX@@/opt, we need to include the package version in the path
                var newPath = oldPath.replacingOccurrences(of: "@@HOMEBREW_PREFIX@@/opt/", with: "@rpath/Cellar/")
                // Then add the package version if it's missing (for framework libraries)
                if newPath.contains("@rpath/Cellar/") && binaryPath.path.contains("/Frameworks/") {
                    // Extract package name and version from the binary path
                    let pathComponents = binaryPath.pathComponents
                    if let cellarIndex = pathComponents.firstIndex(of: "Cellar"),
                       cellarIndex + 2 < pathComponents.count {
                        let packageName = pathComponents[cellarIndex + 1]
                        let packageVersion = pathComponents[cellarIndex + 2]
                        // Replace the package path to include version
                        newPath = newPath.replacingOccurrences(of: "@rpath/Cellar/\(packageName)/", with: "@rpath/Cellar/\(packageName)/\(packageVersion)/")
                    }
                }
                newPath = newPath.replacingOccurrences(of: "@@HOMEBREW_CELLAR@@", with: "@rpath/Cellar")

                // Check if this is the first line (install name) or a dependency
                let isInstallName = index == 1 // otool -L output: line 0 is the file path, line 1 is install name
                
                if isInstallName && (binaryPath.pathExtension == "dylib" || 
                                   binaryPath.pathExtension == "so" ||
                                   (binaryPath.path.contains("/Frameworks/") && binaryPath.path.contains(".framework/") && !binaryPath.path.contains("/bin/"))) {
                    // Fix the library's own install name (identity) for shared libraries
                    OSLogger.shared.debug("  Rewriting install name: \(oldPath) -> \(newPath)", category: OSLogger.shared.installer)
                    
                    let installNameProcess = Process()
                    installNameProcess.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
                    installNameProcess.arguments = ["-id", newPath, binaryPath.path]

                    let installNamePipe = Pipe()
                    let installNameErrorPipe = Pipe()
                    installNameProcess.standardOutput = installNamePipe
                    installNameProcess.standardError = installNameErrorPipe

                    try installNameProcess.run()
                    installNameProcess.waitUntilExit()

                    // Read output and close handles
                    _ = installNamePipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = installNameErrorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    try? installNamePipe.fileHandleForReading.close()
                    try? installNamePipe.fileHandleForWriting.close()
                    try? installNameErrorPipe.fileHandleForReading.close()
                    try? installNameErrorPipe.fileHandleForWriting.close()

                    if installNameProcess.terminationStatus != 0 {
                        let errorString = String(data: errorOutput, encoding: .utf8) ?? "Unknown error"
                        OSLogger.shared.installerWarning("install_name_tool -id failed for \(binaryPath.lastPathComponent): \(errorString)")
                    } else {
                        rewriteCount += 1
                    }
                } else {
                    // Fix dependency reference
                    OSLogger.shared.debug("  Rewriting dependency: \(oldPath) -> \(newPath)", category: OSLogger.shared.installer)

                    let installNameProcess = Process()
                    installNameProcess.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
                    installNameProcess.arguments = ["-change", oldPath, newPath, binaryPath.path]

                    let installNamePipe = Pipe()
                    let installNameErrorPipe = Pipe()
                    installNameProcess.standardOutput = installNamePipe
                    installNameProcess.standardError = installNameErrorPipe

                    try installNameProcess.run()
                    installNameProcess.waitUntilExit()

                    // Read output and close handles
                    _ = installNamePipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = installNameErrorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    try? installNamePipe.fileHandleForReading.close()
                    try? installNamePipe.fileHandleForWriting.close()
                    try? installNameErrorPipe.fileHandleForReading.close()
                    try? installNameErrorPipe.fileHandleForWriting.close()

                    if installNameProcess.terminationStatus != 0 {
                        let errorString = String(data: errorOutput, encoding: .utf8) ?? "Unknown error"
                        OSLogger.shared.installerWarning("install_name_tool -change failed for \(binaryPath.lastPathComponent): \(errorString)")
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
            OSLogger.shared.installerInfo("  ✓ Rewrote \(rewriteCount) library paths")
            
            // Verify the rewriting worked
            let verifySuccess = try await verifyPlaceholderReplacement(binaryPath: binaryPath)
            if !verifySuccess {
                OSLogger.shared.installerWarning("  ⚠️ Some placeholders remain unreplaced in \(binaryPath.lastPathComponent)")
            }
        }

        // Rewrite existing @rpath entries with placeholders
        try await rewriteRPathEntries(binaryPath: binaryPath)
        
        // Add @rpath entries for portable library resolution
        try await addRPathEntries(binaryPath: binaryPath)

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

    private func isMachOBinary(at path: URL) async throws -> Bool {
        // First check if file exists and is readable
        guard fileManager.fileExists(atPath: path.path) else {
            return false
        }
        
        // Check if file has some content (empty files can't be binaries)
        guard let attributes = try? fileManager.attributesOfItem(atPath: path.path),
              let fileSize = attributes[.size] as? Int64,
              fileSize > 0 else {
            return false
        }
        
        // Use file command to check if it's a Mach-O binary
        let fileProcess = Process()
        fileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        fileProcess.arguments = [path.path]
        
        let filePipe = Pipe()
        let errorPipe = Pipe()
        fileProcess.standardOutput = filePipe
        fileProcess.standardError = errorPipe
        
        do {
            try fileProcess.run()
            fileProcess.waitUntilExit()
            
            // Read output and ensure file handles are closed
            let output = filePipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            // Explicitly close file handles
            try? filePipe.fileHandleForReading.close()
            try? filePipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForWriting.close()
            
            guard fileProcess.terminationStatus == 0 else {
                let errorString = String(data: errorOutput, encoding: .utf8) ?? ""
                if errorString.contains("Bad file descriptor") {
                    OSLogger.shared.installerWarning("Bad file descriptor when checking \(path.lastPathComponent)")
                }
                return false
            }
            
            let outputString = String(data: output, encoding: .utf8) ?? ""
            
            // Check if it's a Mach-O executable, dynamic library, or bundle
            return outputString.contains("Mach-O") && 
                   (outputString.contains("executable") || 
                    outputString.contains("dynamically linked shared library") ||
                    outputString.contains("bundle"))
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain && nsError.code == EBADF {
                OSLogger.shared.installerWarning("EBADF error checking file type for \(path.lastPathComponent)")
            }
            return false
        }
    }

    private func binaryNeedsPathRewriting(binaryPath: URL) async throws -> Bool {
        // Only check actual Mach-O binaries
        guard try await isMachOBinary(at: binaryPath) else {
            return false // Not a binary, skip
        }
        
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
        // Only verify actual Mach-O binaries
        guard try await isMachOBinary(at: binaryPath) else {
            return true // Not a binary, nothing to verify
        }
        
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
            
            // Skip symlinks - only process actual files
            var isSymlink: ObjCBool = false
            if fileManager.fileExists(atPath: libraryPath.path, isDirectory: &isSymlink) {
                let attributes = try? fileManager.attributesOfItem(atPath: libraryPath.path)
                if let fileType = attributes?[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
                    OSLogger.shared.debug("Skipping symlink: \(libraryFile)", category: OSLogger.shared.installer)
                    continue
                }
            }
            
            // Only process actual Mach-O libraries
            guard try await isMachOBinary(at: libraryPath) else {
                OSLogger.shared.debug("Skipping non-binary library file: \(libraryFile)", category: OSLogger.shared.installer)
                continue
            }
            
            try await rewriteBinaryLibraryPaths(binaryPath: libraryPath)
        }
    }
    
    private func rewriteFrameworksDirectory(_ frameworksDir: URL) async throws {
        // Use recursive discovery instead of hardcoded paths
        let allFiles = try findAllProcessableFiles(in: frameworksDir)
        
        for filePath in allFiles {
            // Skip symlinks to avoid duplicate processing
            let attributes = try? fileManager.attributesOfItem(atPath: filePath.path)
            if let fileType = attributes?[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
                continue
            }
            
            if try await isMachOBinary(at: filePath) {
                try await rewriteBinaryLibraryPaths(binaryPath: filePath)
            } else if try await isTextScript(at: filePath) {
                try await rewriteTextScript(at: filePath)
            }
        }
    }
    
    // MARK: - Recursive File Discovery
    
    private func findAllProcessableFiles(in directory: URL) throws -> [URL] {
        var processableFiles: [URL] = []
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return processableFiles
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                
                // Only process regular files (not directories or symlinks)
                if resourceValues.isRegularFile == true && resourceValues.isSymbolicLink != true {
                    processableFiles.append(fileURL)
                }
            } catch {
                // Skip files we can't read attributes for
                continue
            }
        }
        
        return processableFiles
    }
    
    private func isTextScript(at fileURL: URL) async throws -> Bool {
        // Only process files that are likely to be text scripts
        let fileExtension = fileURL.pathExtension.lowercased()
        let fileName = fileURL.lastPathComponent
        
        // Skip binary file extensions
        let binaryExtensions = ["so", "dylib", "a", "o", "bin", "exe", "dll", "pkg", "dmg", "tar", "gz", "zip", "png", "jpg", "pdf"]
        if binaryExtensions.contains(fileExtension) {
            return false
        }
        
        // Skip common binary files
        if fileName.contains(".cpython-") || fileName.contains(".dylib") || fileName.hasPrefix("lib") {
            return false
        }
        
        // Check if file starts with shebang or contains Homebrew placeholders
        guard let fileHandle = FileHandle(forReadingAtPath: fileURL.path) else {
            return false
        }
        defer { fileHandle.closeFile() }
        
        // Read first 512 bytes to check for shebang and placeholders
        let data = fileHandle.readData(ofLength: 512)
        guard let content = String(data: data, encoding: .utf8) else {
            return false
        }
        
        // Check for null bytes (indicates binary file)
        if data.contains(0) {
            return false
        }
        
        // Check for shebang or Homebrew placeholders
        return content.hasPrefix("#!") || 
               content.contains("@@HOMEBREW_PREFIX@@") ||
               content.contains("@@HOMEBREW_CELLAR@@") ||
               content.contains("/opt/homebrew") ||
               content.contains("/usr/local/Cellar") ||
               content.contains("/usr/local/opt")
    }
    
    private func rewriteTextScript(at fileURL: URL) async throws {
        do {
            // Read the entire file
            let originalContent = try String(contentsOf: fileURL, encoding: .utf8)
            
            // Replace all Homebrew path variants with Velo paths
            var updatedContent = originalContent
            updatedContent = updatedContent.replacingOccurrences(of: "@@HOMEBREW_PREFIX@@", with: pathHelper.veloHome.path)
            updatedContent = updatedContent.replacingOccurrences(of: "@@HOMEBREW_CELLAR@@", with: pathHelper.cellarPath.path)
            updatedContent = updatedContent.replacingOccurrences(of: "/opt/homebrew", with: pathHelper.veloHome.path)
            updatedContent = updatedContent.replacingOccurrences(of: "/usr/local", with: pathHelper.veloHome.path)
            
            // Only write back if content changed
            if updatedContent != originalContent {
                try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)
                OSLogger.shared.debug("🔧 Updated text script: \(fileURL.lastPathComponent)", category: OSLogger.shared.installer)
            }
        } catch {
            // Skip files that can't be read/written as text
            OSLogger.shared.debug("⚠️ Skipping text processing for \(fileURL.lastPathComponent): \(error.localizedDescription)", category: OSLogger.shared.installer)
        }
    }

    private func addRPathEntries(binaryPath: URL) async throws {
        // Determine appropriate @rpath entries based on binary location
        let rpathEntries = calculateRPathEntries(for: binaryPath)
        
        for rpath in rpathEntries {
            OSLogger.shared.debug("  Adding @rpath: \(rpath)", category: OSLogger.shared.installer)
            
            let rpathProcess = Process()
            rpathProcess.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
            rpathProcess.arguments = ["-add_rpath", rpath, binaryPath.path]
            
            let rpathPipe = Pipe()
            rpathProcess.standardOutput = rpathPipe
            rpathProcess.standardError = rpathPipe
            
            try rpathProcess.run()
            rpathProcess.waitUntilExit()
            
            // Note: We don't treat rpath addition failures as fatal
            // Some binaries may already have these paths or may not need them
            if rpathProcess.terminationStatus != 0 {
                let errorOutput = rpathPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorOutput, encoding: .utf8) ?? "Unknown error"
                OSLogger.shared.debug("  @rpath addition warning for \(binaryPath.lastPathComponent): \(errorString)", category: OSLogger.shared.installer)
            }
        }
    }
    
    private func calculateRPathEntries(for binaryPath: URL) -> [String] {
        let pathComponents = binaryPath.pathComponents
        
        // Find where we are relative to .velo root
        guard let veloIndex = pathComponents.lastIndex(of: ".velo") else {
            // Fallback for binaries not in .velo structure
            return ["@loader_path/../opt", "@executable_path/../opt"]
        }
        
        let relativePath = Array(pathComponents[(veloIndex + 1)...])
        
        // Calculate depth from binary to .velo root
        let depth = relativePath.count - 1 // -1 because we don't count the binary filename
        let upPath = String(repeating: "../", count: depth)
        
        // Standard @rpath entries for portable library resolution
        // Point to .velo root so @rpath/lib/... and @rpath/Cellar/... resolve correctly
        let rootPath = upPath.isEmpty ? "." : String(upPath.dropLast()) // Remove trailing /
        
        var rpathEntries = [
            "@loader_path/\(rootPath)",      // For finding libraries relative to loader
            "@executable_path/\(rootPath)"   // For main executables finding libraries
        ]
        
        // Special handling for framework binaries to support symlinked access
        if binaryPath.path.contains("/Frameworks/") && binaryPath.path.contains(".framework/") {
            // Add additional rpath entries for symlinked framework binaries
            // These help when binaries are accessed through /opt/ symlinks
            rpathEntries.append("@loader_path/../../../../../../../..")
            rpathEntries.append("@executable_path/../../../../../../../..")
            
            // For python binaries, add direct path to the framework
            if binaryPath.path.contains("python") {
                rpathEntries.append("@loader_path/../../..")  // Relative to framework library
                rpathEntries.append("@executable_path/../../..")
            }
        }
        
        return rpathEntries
    }
    
    private func rewriteRPathEntries(binaryPath: URL) async throws {
        // Get current @rpath entries
        let otoolProcess = Process()
        otoolProcess.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
        otoolProcess.arguments = ["-l", binaryPath.path]

        let otoolPipe = Pipe()
        let errorPipe = Pipe()
        otoolProcess.standardOutput = otoolPipe
        otoolProcess.standardError = errorPipe

        try otoolProcess.run()
        otoolProcess.waitUntilExit()

        // Read output and ensure file handles are closed
        let otoolOutput = otoolPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        // Explicitly close file handles to prevent descriptor leaks
        try? otoolPipe.fileHandleForReading.close()
        try? otoolPipe.fileHandleForWriting.close()
        try? errorPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForWriting.close()

        guard otoolProcess.terminationStatus == 0 else {
            let errorString = String(data: errorOutput, encoding: .utf8) ?? "Unknown error"
            OSLogger.shared.debug("Failed to read @rpath entries for \(binaryPath.lastPathComponent): \(errorString)", category: OSLogger.shared.installer)
            return
        }

        let output = String(data: otoolOutput, encoding: .utf8) ?? ""
        let lines = output.components(separatedBy: .newlines)
        
        // Parse @rpath entries from otool -l output
        var rpathEntries: [String] = []
        var isInRPathCommand = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.starts(with: "cmd LC_RPATH") {
                isInRPathCommand = true
                continue
            }
            
            if isInRPathCommand && trimmed.starts(with: "path ") {
                // Extract path from "path /some/path (offset 12)"
                let pathLine = trimmed.replacingOccurrences(of: "path ", with: "")
                if let spaceIndex = pathLine.firstIndex(of: " ") {
                    let path = String(pathLine[..<spaceIndex])
                    rpathEntries.append(path)
                }
                isInRPathCommand = false
            }
        }
        
        // Check if any @rpath entries contain Homebrew placeholders
        var rewriteCount = 0
        for rpathEntry in rpathEntries {
            if rpathEntry.contains("@@HOMEBREW_PREFIX@@") || rpathEntry.contains("@@HOMEBREW_CELLAR@@") {
                // Create new path with Velo paths
                var newPath = rpathEntry
                newPath = newPath.replacingOccurrences(of: "@@HOMEBREW_PREFIX@@", with: pathHelper.veloHome.path)
                newPath = newPath.replacingOccurrences(of: "@@HOMEBREW_CELLAR@@", with: pathHelper.cellarPath.path)
                
                OSLogger.shared.debug("  Rewriting @rpath entry: \(rpathEntry) -> \(newPath)", category: OSLogger.shared.installer)
                
                // Remove old @rpath entry
                let deleteProcess = Process()
                deleteProcess.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
                deleteProcess.arguments = ["-delete_rpath", rpathEntry, binaryPath.path]
                
                let deletePipe = Pipe()
                deleteProcess.standardOutput = deletePipe
                deleteProcess.standardError = deletePipe
                
                try deleteProcess.run()
                deleteProcess.waitUntilExit()
                
                if deleteProcess.terminationStatus != 0 {
                    let errorOutput = deletePipe.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorOutput, encoding: .utf8) ?? "Unknown error"
                    OSLogger.shared.debug("Failed to delete @rpath entry \(rpathEntry): \(errorString)", category: OSLogger.shared.installer)
                    continue
                }
                
                // Add new @rpath entry
                let addProcess = Process()
                addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
                addProcess.arguments = ["-add_rpath", newPath, binaryPath.path]
                
                let addPipe = Pipe()
                addProcess.standardOutput = addPipe
                addProcess.standardError = addPipe
                
                try addProcess.run()
                addProcess.waitUntilExit()
                
                if addProcess.terminationStatus != 0 {
                    let errorOutput = addPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorString = String(data: errorOutput, encoding: .utf8) ?? "Unknown error"
                    OSLogger.shared.debug("Failed to add @rpath entry \(newPath): \(errorString)", category: OSLogger.shared.installer)
                } else {
                    rewriteCount += 1
                }
            }
        }
        
        if rewriteCount > 0 {
            OSLogger.shared.installerInfo("  ✓ Rewrote \(rewriteCount) @rpath entries")
        }
    }

    // MARK: - Script File Rewriting

    private func rewriteScriptFiles(packageDir: URL) async throws {
        OSLogger.shared.verbose("🔧 Rewriting script file placeholders", category: OSLogger.shared.installer)
        
        // Find all files with Homebrew placeholders recursively
        let filesWithPlaceholders = try await findFilesWithPlaceholders(in: packageDir)
        
        if filesWithPlaceholders.isEmpty {
            return
        }
        
        OSLogger.shared.verbose("  Found \(filesWithPlaceholders.count) files with placeholders", category: OSLogger.shared.installer)
        
        for filePath in filesWithPlaceholders {
            do {
                try await rewriteFileContent(filePath: filePath)
            } catch {
                OSLogger.shared.installerWarning("Failed to rewrite placeholders in \(filePath.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    private func findFilesWithPlaceholders(in directory: URL) async throws -> [URL] {
        // Use find command to search for files containing Homebrew placeholders
        let findProcess = Process()
        findProcess.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        findProcess.arguments = [
            "-r",  // Recursive
            "-l",  // Only show filenames, not content
            "--binary-files=without-match",  // Skip binary files
            "@@HOMEBREW_",  // Search pattern
            directory.path
        ]
        
        let findPipe = Pipe()
        findProcess.standardOutput = findPipe
        findProcess.standardError = Pipe() // Suppress error output
        
        try findProcess.run()
        findProcess.waitUntilExit()
        
        let output = findPipe.fileHandleForReading.readDataToEndOfFile()
        let outputString = String(data: output, encoding: .utf8) ?? ""
        
        // Parse file paths from grep output
        let filePaths = outputString.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
        
        return filePaths
    }
    
    private func rewriteFileContent(filePath: URL) async throws {
        let content = try String(contentsOf: filePath, encoding: .utf8)
        
        // Replace Homebrew placeholders with actual Velo paths (not @rpath - that's for binaries only)
        var newContent = content
        newContent = newContent.replacingOccurrences(of: "@@HOMEBREW_PREFIX@@", with: pathHelper.veloPrefix.path)
        newContent = newContent.replacingOccurrences(of: "@@HOMEBREW_CELLAR@@", with: pathHelper.cellarPath.path)
        
        // Only write if content actually changed
        if newContent != content {
            try newContent.write(to: filePath, atomically: true, encoding: .utf8)
            OSLogger.shared.debug("  ✓ Rewrote placeholders in \(filePath.lastPathComponent)", category: OSLogger.shared.installer)
        }
    }

    // MARK: - Verification

    public func verifyInstallation(formula: Formula, checkSymlinks: Bool = true) throws -> InstallationStatus {
        let packageDir = pathHelper.packagePath(for: formula.name, version: formula.version)

        guard fileManager.fileExists(atPath: packageDir.path) else {
            return .notInstalled
        }

        // Check if binaries are properly linked (only if symlink checking is enabled)
        if checkSymlinks {
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
    
    // MARK: - Framework Support
    
    private func findFrameworkBinDirectories(in packageDir: URL) throws -> [URL] {
        var frameworkBinDirs: [URL] = []
        
        // Look for Framework directories
        let frameworksDir = packageDir.appendingPathComponent("Frameworks")
        if fileManager.fileExists(atPath: frameworksDir.path) {
            let frameworks = try fileManager.contentsOfDirectory(atPath: frameworksDir.path)
                .filter { $0.hasSuffix(".framework") }
            
            for framework in frameworks {
                let frameworkDir = frameworksDir.appendingPathComponent(framework)
                
                // Look for Versions/*/bin directories in the framework
                let versionsDir = frameworkDir.appendingPathComponent("Versions")
                if fileManager.fileExists(atPath: versionsDir.path) {
                    let versions = try fileManager.contentsOfDirectory(atPath: versionsDir.path)
                        .filter { !$0.hasPrefix(".") }
                    
                    for version in versions {
                        let versionBinDir = versionsDir.appendingPathComponent(version).appendingPathComponent("bin")
                        if fileManager.fileExists(atPath: versionBinDir.path) {
                            frameworkBinDirs.append(versionBinDir)
                        }
                    }
                }
                
                // Also check for direct bin directory in framework
                let frameworkBinDir = frameworkDir.appendingPathComponent("bin")
                if fileManager.fileExists(atPath: frameworkBinDir.path) {
                    frameworkBinDirs.append(frameworkBinDir)
                }
            }
        }
        
        return frameworkBinDirs
    }
    
    // MARK: - Framework Detection
    
    private func hasFrameworkDependencies(packageDir: URL) throws -> Bool {
        let frameworksDir = packageDir.appendingPathComponent("Frameworks")
        return fileManager.fileExists(atPath: frameworksDir.path)
    }
    
    private func isFrameworkBinary(path: URL, packageDir: URL) -> Bool {
        let relativePath = path.path.replacingOccurrences(of: packageDir.path, with: "")
        return relativePath.contains("/Frameworks/") && relativePath.contains(".framework/")
    }
    
    private func createFrameworkSymlinks(
        binaryName: String,
        sourcePath: URL,
        formula: Formula,
        packageDir: URL,
        force: Bool
    ) async throws -> (PathHelper.SymlinkResult, PathHelper.SymlinkResult) {
        // Create wrapper scripts instead of direct symlinks for framework binaries
        let versionedPath = pathHelper.versionedSymlinkPath(for: binaryName, package: formula.name, version: formula.version)
        let defaultPath = pathHelper.symlinkPath(for: binaryName)
        
        // Generate wrapper script content
        let frameworkPath = packageDir.appendingPathComponent("Frameworks")
        let wrapperScript = generateFrameworkWrapperScript(
            binaryPath: sourcePath,
            frameworkPath: frameworkPath
        )
        
        // Create versioned wrapper
        let versionedResult = try createWrapperScript(
            content: wrapperScript,
            at: versionedPath,
            packageName: formula.name,
            force: force
        )
        
        // Create default wrapper
        let defaultResult = try createWrapperScript(
            content: wrapperScript,
            at: defaultPath,
            packageName: formula.name,
            force: force
        )
        
        return (versionedResult, defaultResult)
    }
    
    private func generateFrameworkWrapperScript(binaryPath: URL, frameworkPath: URL) -> String {
        return """
        #!/bin/bash
        # Velo framework wrapper script
        
        # Set framework path for dynamic library loading
        export DYLD_FRAMEWORK_PATH="\(frameworkPath.path):$DYLD_FRAMEWORK_PATH"
        
        # For Python specifically, set PYTHONHOME to help find the standard library
        if [[ "\(binaryPath.lastPathComponent)" == python* ]]; then
            export PYTHONHOME="\(frameworkPath.path)/Python.framework/Versions/Current"
        fi
        
        # Execute the actual binary
        exec "\(binaryPath.path)" "$@"
        """
    }
    
    private func createWrapperScript(
        content: String,
        at path: URL,
        packageName: String,
        force: Bool
    ) throws -> PathHelper.SymlinkResult {
        // Check for existing file/symlink
        if fileManager.fileExists(atPath: path.path) {
            if !force {
                // Check if it's owned by the same package
                let conflictingPackage = pathHelper.findConflictingPackage(for: path.lastPathComponent)
                if let conflictingPackage = conflictingPackage, conflictingPackage != packageName {
                    return .skipped(reason: "conflicts with \(conflictingPackage)")
                }
            }
            
            // Remove existing file
            try fileManager.removeItem(at: path)
        }
        
        // Ensure parent directory exists
        let parentDir = path.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        // Write wrapper script
        try content.write(to: path, atomically: true, encoding: .utf8)
        
        // Make executable
        let attributes = [FileAttributeKey.posixPermissions: 0o755]
        try fileManager.setAttributes(attributes, ofItemAtPath: path.path)
        
        return .created
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
    
    /// Create symlinks for an already installed package (used when converting dependency to explicit)
    public func createSymlinksForExistingPackage(formula: Formula, packageDir: URL) async throws {
        try await createSymlinks(for: formula, packageDir: packageDir, progress: nil, force: false)
    }
    
    /// Remove symlinks for a package without uninstalling it
    public func removeSymlinksForPackage(package: String, version: String, packageDir: URL) throws {
        try removeSymlinks(for: package, version: version, packageDir: packageDir)
    }
}
