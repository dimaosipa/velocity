import Foundation

public struct PathHelper {
    public static let shared = PathHelper()
    
    private let fileManager = FileManager.default
    
    // Base directories
    public var veloHome: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".velo")
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
    
    // MARK: - Symlink Management
    
    public func symlinkPath(for binary: String) -> URL {
        binPath.appendingPathComponent(binary)
    }
    
    public func createSymlink(from source: URL, to destination: URL) throws {
        // Remove existing symlink if it exists
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
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