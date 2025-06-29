import Foundation

public struct PathHelper {
    public static let shared = PathHelper()
    
    private let fileManager = FileManager.default
    
    // Base directories
    public var veloHome: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".velo")
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
    
    private init() {}
    
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