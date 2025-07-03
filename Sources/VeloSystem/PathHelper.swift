import Foundation

public struct PathHelper {
    public static let shared = PathHelper()

    private let fileManager = FileManager.default
    private let customHome: URL?

    // Base directories
    public var veloHome: URL {
        if let custom = customHome {
            return custom
        }
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".velo")
    }

    public var veloPrefix: URL {
        veloHome
    }

    public var cellarPath: URL {
        veloHome.appendingPathComponent("Cellar")
    }

    public var binPath: URL {
        veloHome.appendingPathComponent("bin")
    }

    public var cachePath: URL {
        veloHome.appendingPathComponent("cache")
    }

    public var tapsPath: URL {
        veloHome.appendingPathComponent("taps")
    }

    public var logsPath: URL {
        veloHome.appendingPathComponent("logs")
    }

    public var tmpPath: URL {
        veloHome.appendingPathComponent("tmp")
    }

    public var optPath: URL {
        veloHome.appendingPathComponent("opt")
    }
    
    public var receiptsPath: URL {
        veloHome.appendingPathComponent("receipts")
    }
    
    public var tapMetadataFile: URL {
        cachePath.appendingPathComponent("tap-metadata.json")
    }
    
    public func searchIndexCacheFile(for tapName: String) -> URL {
        cachePath.appendingPathComponent("search-index-\(tapName.replacingOccurrences(of: "/", with: "-")).velocache")
    }

    private init(customHome: URL? = nil) {
        self.customHome = customHome
    }

    public init(customHome: URL) {
        self.customHome = customHome
    }

    // MARK: - Directory Management

    public func ensureDirectoryExists(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    public func ensureVeloDirectories() throws {
        try ensureDirectoryExists(at: veloHome)
        try ensureDirectoryExists(at: cellarPath)
        try ensureDirectoryExists(at: binPath)
        try ensureDirectoryExists(at: cachePath)
        try ensureDirectoryExists(at: tapsPath)
        try ensureDirectoryExists(at: logsPath)
        try ensureDirectoryExists(at: tmpPath)
        try ensureDirectoryExists(at: optPath)
        try ensureDirectoryExists(at: receiptsPath)
    }

    // MARK: - Package Paths

    public func packagePath(for name: String, version: String) -> URL {
        cellarPath.appendingPathComponent(name).appendingPathComponent(version)
    }

    public func installedVersions(for package: String) -> [String] {
        let packageDir = cellarPath.appendingPathComponent(package)
        guard let versions = try? fileManager.contentsOfDirectory(atPath: packageDir.path) else {
            return []
        }
        return versions.filter { !$0.hasPrefix(".") }.sorted()
    }

    public func isPackageInstalled(_ package: String) -> Bool {
        let packageDir = cellarPath.appendingPathComponent(package)
        
        // Check if directory exists
        guard fileManager.fileExists(atPath: packageDir.path) else {
            return false
        }
        
        // Check if directory has version subdirectories and they are not empty
        do {
            let versionDirs = try fileManager.contentsOfDirectory(atPath: packageDir.path)
                .filter { !$0.hasPrefix(".") }
            
            // If no version directories, this is not a valid installation
            guard !versionDirs.isEmpty else {
                return false
            }
            
            // Check if at least one version directory is properly installed
            for versionDir in versionDirs {
                let versionPath = packageDir.appendingPathComponent(versionDir)
                
                // Check if version directory has content
                let versionContents = try fileManager.contentsOfDirectory(atPath: versionPath.path)
                if !versionContents.isEmpty {
                    return true
                }
            }
            
            return false
        } catch {
            return false
        }
    }
    
    /// Check if any equivalent package is installed
    public func isEquivalentPackageInstalled(_ package: String) -> Bool {
        // First check the package itself
        if isPackageInstalled(package) {
            return true
        }
        
        // Import PackageEquivalence here to avoid circular dependencies
        // This is a simplified check - in production we'd inject this dependency
        let equivalents = getEquivalentPackageNames(for: package)
        return equivalents.contains { isPackageInstalled($0) }
    }
    
    /// Find any installed equivalent package
    public func findInstalledEquivalentPackage(for package: String) -> String? {
        // First check the package itself
        if isPackageInstalled(package) {
            return package
        }
        
        let equivalents = getEquivalentPackageNames(for: package)
        return equivalents.first { isPackageInstalled($0) }
    }
    
    /// Get equivalent package names (simplified version for PathHelper)
    private func getEquivalentPackageNames(for package: String) -> [String] {
        // Simplified equivalence mapping - ideally this would use PackageEquivalence
        // but we avoid circular dependencies by having a minimal implementation here
        let commonEquivalencies: [String: [String]] = [
            "python@3.9": ["python3.9", "python39"],
            "python@3.10": ["python3.10", "python310"],
            "python@3.11": ["python3.11", "python311"],
            "python@3.12": ["python3.12", "python312"],
            "python@3.13": ["python3.13", "python313"],
            "python3.9": ["python@3.9", "python39"],
            "python3.10": ["python@3.10", "python310"],
            "python3.11": ["python@3.11", "python311"],
            "python3.12": ["python@3.12", "python312"],
            "python3.13": ["python@3.13", "python313"],
            "node@18": ["node18", "nodejs18"],
            "node@20": ["node20", "nodejs20"],
            "node@22": ["node22", "nodejs22"],
            "openssl@3": ["openssl3", "libssl3"],
            "openssl@1.1": ["openssl1.1", "libssl1.1"]
        ]
        
        if let equivalents = commonEquivalencies[package] {
            return [package] + equivalents
        }
        
        // Check if package is in any equivalency group
        for (canonical, equivalents) in commonEquivalencies {
            if equivalents.contains(package) {
                return [canonical] + equivalents
            }
        }
        
        return [package]
    }
    
    // MARK: - File Removal Helpers
    
    private func isSymlink(at url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            return resourceValues.isSymbolicLink ?? false
        } catch {
            return false
        }
    }
    
    private func clearExtendedAttributes(at url: URL) throws {
        let xattrProcess = Process()
        xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProcess.arguments = ["-c", url.path]
        
        // Suppress all output to avoid noise
        xattrProcess.standardOutput = Pipe()
        xattrProcess.standardError = Pipe()
        
        // Ignore errors - some files may not have extended attributes
        try? xattrProcess.run()
        xattrProcess.waitUntilExit()
    }
    
    private func makeFileWritable(at url: URL) throws {
        var attributes = try fileManager.attributesOfItem(atPath: url.path)
        if let permissions = attributes[.posixPermissions] as? NSNumber {
            let newPermissions = permissions.uint16Value | 0o200 // Add write permission for owner
            attributes[.posixPermissions] = NSNumber(value: newPermissions)
            try fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        }
    }
    
    private func aggressiveFileRemoval(at url: URL) throws {
        // Try using rm command as a last resort
        let rmProcess = Process()
        rmProcess.executableURL = URL(fileURLWithPath: "/bin/rm")
        rmProcess.arguments = ["-f", url.path]
        
        let pipe = Pipe()
        rmProcess.standardOutput = pipe
        rmProcess.standardError = pipe
        
        try rmProcess.run()
        rmProcess.waitUntilExit()
        
        if rmProcess.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw VeloError.symlinkFailed(from: url.path, to: "aggressive removal failed: \(errorOutput)")
        }
    }

    public func isSpecificVersionInstalled(_ package: String, version: String) -> Bool {
        let packageDir = packagePath(for: package, version: version)
        return fileManager.fileExists(atPath: packageDir.path)
    }

    // MARK: - Symlink Management

    public func symlinkPath(for binary: String) -> URL {
        binPath.appendingPathComponent(binary)
    }

    public func versionedSymlinkPath(for binary: String, package: String, version: String) -> URL {
        binPath.appendingPathComponent("\(binary)@\(version)")
    }

    public func createSymlink(from source: URL, to destination: URL) throws {
        // Remove existing symlink if it exists
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
    }
    
    /// Result of symlink creation attempt
    public enum SymlinkResult {
        case created
        case skipped(reason: String)
        case failed(error: Error)
    }
    
    /// Create symlink with conflict detection and resolution
    public func createSymlinkWithConflictDetection(
        from source: URL, 
        to destination: URL, 
        packageName: String,
        force: Bool = false
    ) -> SymlinkResult {
        let destinationPath = destination.path
        
        if force {
            OSLogger.shared.debug("🔧 Creating symlink with force=true: \(destination.lastPathComponent)", category: OSLogger.shared.general)
        }
        
        // Check if destination already exists
        if fileManager.fileExists(atPath: destinationPath) {
            if force {
                // Force mode - always replace, no questions asked
                OSLogger.shared.info("🔗 Force replacing existing file/symlink: \(destination.lastPathComponent)")
            } else {
                // Non-force mode - check package equivalence and skip conflicts (Homebrew-style)
                if let existingTarget = try? fileManager.destinationOfSymbolicLink(atPath: destinationPath) {
                    let existingPackage = extractPackageFromPath(existingTarget)
                    
                    if let existing = existingPackage {
                        // Check if packages are equivalent
                        let equivalents = getEquivalentPackageNames(for: packageName)
                        if !equivalents.contains(existing) {
                            // Different packages - skip symlink creation (Homebrew behavior)
                            return .skipped(reason: "conflicts with existing symlink from \(existing)")
                        }
                        // Equivalent packages - allow replacement
                        OSLogger.shared.info("🔗 Replacing symlink for equivalent package: \(existing) -> \(packageName)")
                    } else {
                        OSLogger.shared.warning("🔗 Replacing symlink from unknown package")
                    }
                } else {
                    // File exists but is not a symlink - skip creation (Homebrew behavior)
                    return .skipped(reason: "file already exists")
                }
            }
            
            // Remove existing symlink/file with robust cleanup
            OSLogger.shared.info("🔍 Attempting to remove existing file: \(destination.lastPathComponent)")
            do {
                // Clear extended attributes that might prevent removal
                try clearExtendedAttributes(at: destination)
                
                // Make the file writable if it's not a symlink
                if !isSymlink(at: destination) {
                    OSLogger.shared.debug("📝 Making file writable: \(destination.lastPathComponent)", category: OSLogger.shared.general)
                    try makeFileWritable(at: destination)
                }
                
                // Remove the file/symlink
                try fileManager.removeItem(at: destination)
                OSLogger.shared.info("🗑️ Successfully removed existing file/symlink: \(destination.lastPathComponent)")
            } catch {
                OSLogger.shared.warning("⚠️ Failed to remove existing file: \(destination.lastPathComponent) - \(error.localizedDescription)")
                
                // In force mode, try harder to remove the file
                if force {
                    OSLogger.shared.info("🔧 Force mode: attempting aggressive file removal")
                    do {
                        try aggressiveFileRemoval(at: destination)
                        OSLogger.shared.info("✅ Successfully removed stubborn file with aggressive removal")
                    } catch {
                        return .failed(error: VeloError.symlinkFailed(
                            from: source.path,
                            to: destination.path + " (failed to remove existing file even with force: \(error.localizedDescription))"
                        ))
                    }
                } else {
                    return .failed(error: VeloError.symlinkFailed(
                        from: source.path,
                        to: destination.path + " (failed to remove existing file: \(error.localizedDescription))"
                    ))
                }
            }
        }
        
        do {
            try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
            OSLogger.shared.debug("✅ Created symlink: \(destination.lastPathComponent) -> \(source.path)", category: OSLogger.shared.general)
            return .created
        } catch {
            // Double-check if the file still exists after our removal attempt
            let fileStillExists = fileManager.fileExists(atPath: destination.path)
            OSLogger.shared.warning("❌ Symlink creation failed. File still exists: \(fileStillExists)")
            
            return .failed(error: VeloError.symlinkFailed(
                from: source.path,
                to: destination.path + " (\(error.localizedDescription))"
            ))
        }
    }
    
    /// Extract package name from a file path
    private func extractPackageFromPath(_ path: String) -> String? {
        // Path format: ~/.velo/Cellar/package-name/version/bin/binary
        let components = path.components(separatedBy: "/")
        
        // Find "Cellar" in the path
        if let cellarIndex = components.firstIndex(of: "Cellar"),
           cellarIndex + 1 < components.count {
            return components[cellarIndex + 1]
        }
        
        return nil
    }
    
    public func findConflictingPackage(for binary: String) -> String? {
        let symlinkPath = symlinkPath(for: binary)
        
        // Check if symlink exists
        guard fileManager.fileExists(atPath: symlinkPath.path) else {
            return nil
        }
        
        // If it's a symlink, find the target package
        if let target = try? fileManager.destinationOfSymbolicLink(atPath: symlinkPath.path) {
            return extractPackageFromPath(target)
        }
        
        // If it's a regular file, we don't know which package it belongs to
        return "unknown"
    }

    public func createOptSymlink(for package: String, version: String) throws {
        let packageDir = packagePath(for: package, version: version)
        let optSymlinkPath = optPath.appendingPathComponent(package)

        // Remove existing opt symlink if it exists
        if fileManager.fileExists(atPath: optSymlinkPath.path) {
            try fileManager.removeItem(at: optSymlinkPath)
        }

        try fileManager.createSymbolicLink(at: optSymlinkPath, withDestinationURL: packageDir)
    }

    public func removeOptSymlink(for package: String) throws {
        let optSymlinkPath = optPath.appendingPathComponent(package)
        if fileManager.fileExists(atPath: optSymlinkPath.path) {
            try fileManager.removeItem(at: optSymlinkPath)
        }
    }

    public func ensureAllOptSymlinks() throws {
        // Create opt symlinks for all installed packages that don't have them
        guard fileManager.fileExists(atPath: cellarPath.path) else {
            return // No packages installed
        }

        let installedPackages = try fileManager.contentsOfDirectory(atPath: cellarPath.path)
            .filter { !$0.hasPrefix(".") }

        for package in installedPackages {
            let optSymlinkPath = optPath.appendingPathComponent(package)

            // Skip if opt symlink already exists
            if fileManager.fileExists(atPath: optSymlinkPath.path) {
                continue
            }

            // Find the version for this package
            let packageVersions = installedVersions(for: package)
            guard let latestVersion = packageVersions.last else { // Use latest version
                continue
            }

            // Create opt symlink for this package
            try createOptSymlink(for: package, version: latestVersion)
        }
    }

    // MARK: - Version Management

    public func getDefaultVersion(for package: String) -> String? {
        // Check if there's a stored preference, otherwise use latest
        let packageVersions = installedVersions(for: package)
        return packageVersions.last // Return latest as default for now
    }

    public func setDefaultVersion(for package: String, version: String) throws {
        // Verify the version is actually installed
        guard isSpecificVersionInstalled(package, version: version) else {
            throw VeloError.formulaNotFound(name: "\(package) v\(version)")
        }

        // Update opt symlink to point to the specified version
        try createOptSymlink(for: package, version: version)

        // Update default binary symlinks
        try updateDefaultBinarySymlinks(for: package, version: version)
    }

    private func updateDefaultBinarySymlinks(for package: String, version: String) throws {
        let packageDir = packagePath(for: package, version: version)
        let binDir = packageDir.appendingPathComponent("bin")

        guard fileManager.fileExists(atPath: binDir.path) else {
            return // No binaries to link
        }

        let binaries = try fileManager.contentsOfDirectory(atPath: binDir.path)
            .filter { !$0.hasPrefix(".") }

        for binary in binaries {
            let sourcePath = binDir.appendingPathComponent(binary)
            let defaultSymlinkPath = symlinkPath(for: binary)

            // Update the default symlink to point to this version
            let result = createSymlinkWithConflictDetection(from: sourcePath, to: defaultSymlinkPath, packageName: package, force: false)
            
            switch result {
            case .created:
                OSLogger.shared.debug("✅ Updated default symlink for \(binary) -> \(package) \(version)", category: OSLogger.shared.general)
            case .skipped(let reason):
                OSLogger.shared.info("⚠️ Skipped updating default symlink for \(binary): \(reason)", category: OSLogger.shared.general)
            case .failed(let error):
                OSLogger.shared.warning("❌ Failed to update default symlink for \(binary): \(error.localizedDescription)", category: OSLogger.shared.general)
                throw error // In this context, we should still fail if we can't update the default
            }
        }
    }

    // MARK: - Cache Management

    public func cacheFile(for key: String) -> URL {
        cachePath.appendingPathComponent("\(key).velocache")
    }

    public func clearCache() throws {
        let contents = try fileManager.contentsOfDirectory(at: cachePath, includingPropertiesForKeys: nil)
        for file in contents {
            try fileManager.removeItem(at: file)
        }
    }

    // MARK: - Temporary Files

    public func temporaryFile(prefix: String = "velo", extension ext: String? = nil) -> URL {
        let filename = "\(prefix)-\(UUID().uuidString)"
        let fullName = ext != nil ? "\(filename).\(ext!)" : filename
        return tmpPath.appendingPathComponent(fullName)
    }

    public func cleanTemporaryFiles() throws {
        let contents = try fileManager.contentsOfDirectory(at: tmpPath, includingPropertiesForKeys: [.creationDateKey])
        let oneDayAgo = Date().addingTimeInterval(-86400)

        for file in contents {
            if let attributes = try? file.resourceValues(forKeys: [.creationDateKey]),
               let creationDate = attributes.creationDate,
               creationDate < oneDayAgo {
                try fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - Utilities

    public func size(of url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }

    public func totalSize(of directory: URL) throws -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let attributes = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = attributes.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
    }

    public func isInPath() -> Bool {
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
            return false
        }
        return pathEnv.split(separator: ":").contains { String($0) == binPath.path }
    }
}
