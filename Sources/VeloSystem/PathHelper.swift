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
        return fileManager.fileExists(atPath: packageDir.path)
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
    
    /// Create symlink with conflict detection and resolution
    public func createSymlinkWithConflictDetection(
        from source: URL, 
        to destination: URL, 
        packageName: String
    ) throws {
        let destinationPath = destination.path
        
        // Check if destination already exists
        if fileManager.fileExists(atPath: destinationPath) {
            // Try to determine what package owns the existing symlink
            if let existingTarget = try? fileManager.destinationOfSymbolicLink(atPath: destinationPath) {
                let existingPackage = extractPackageFromPath(existingTarget)
                
                if let existing = existingPackage {
                    // Check if packages are equivalent
                    let equivalents = getEquivalentPackageNames(for: packageName)
                    if equivalents.contains(existing) {
                        // Equivalent packages - log replacement
                        OSLogger.shared.info("🔗 Replacing symlink for equivalent package: \(existing) -> \(packageName)")
                    } else {
                        // Different packages - warn about replacement
                        OSLogger.shared.warning("🔗 Replacing symlink from different package: \(existing) -> \(packageName)")
                    }
                } else {
                    OSLogger.shared.warning("🔗 Replacing symlink from unknown package")
                }
            }
            
            // Remove existing symlink/file
            try fileManager.removeItem(at: destination)
        }
        
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
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
            try createSymlink(from: sourcePath, to: defaultSymlinkPath)
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
