import Foundation
import VeloSystem
import VeloFormula

/// Represents a lock file entry for a package
public struct LockEntry: Codable {
    public let version: String
    public let resolved: String  // Download URL
    public let sha256: String
    public let dependencies: [String: String]?
    
    public init(
        version: String,
        resolved: String,
        sha256: String,
        dependencies: [String: String]? = nil
    ) {
        self.version = version
        self.resolved = resolved
        self.sha256 = sha256
        self.dependencies = dependencies
    }
}

/// Represents the velo.lock file
public struct VeloLockFile: Codable {
    public let lockfileVersion: Int
    public var dependencies: [String: LockEntry]
    
    public init(lockfileVersion: Int = 1, dependencies: [String: LockEntry] = [:]) {
        self.lockfileVersion = lockfileVersion
        self.dependencies = dependencies
    }
}

/// Manages reading and writing velo.lock files
public final class VeloLockFileManager {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    public init() {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }
    
    /// Read lock file from a URL
    public func read(from url: URL) throws -> VeloLockFile {
        let data = try Data(contentsOf: url)
        return try decoder.decode(VeloLockFile.self, from: data)
    }
    
    /// Write lock file to a URL
    public func write(_ lockFile: VeloLockFile, to url: URL) throws {
        let data = try encoder.encode(lockFile)
        try data.write(to: url)
    }
    
    /// Create or update lock file with installed packages
    public func updateLockFile(
        at url: URL,
        with installedPackages: [(formula: Formula, bottleURL: String)]
    ) throws {
        var lockFile: VeloLockFile
        
        // Read existing lock file or create new one
        if fileManager.fileExists(atPath: url.path) {
            lockFile = try read(from: url)
        } else {
            lockFile = VeloLockFile()
        }
        
        // Update entries for installed packages
        for (formula, bottleURL) in installedPackages {
            let dependencies = formula.dependencies
                .filter { $0.type == .required }
                .reduce(into: [String: String]()) { result, dep in
                    // For now, we'll use "*" for dependency versions
                    // In a full implementation, we'd resolve exact versions
                    result[dep.name] = "*"
                }
            
            let entry = LockEntry(
                version: formula.version,
                resolved: bottleURL,
                sha256: formula.preferredBottle?.sha256 ?? formula.sha256,
                dependencies: dependencies.isEmpty ? nil : dependencies
            )
            
            lockFile.dependencies[formula.name] = entry
        }
        
        // Write updated lock file
        try write(lockFile, to: url)
    }
    
    /// Check if installed packages match lock file
    public func verifyInstallations(
        lockFile: VeloLockFile,
        installedPackages: [String: String] // name -> version
    ) -> [String] { // Returns list of mismatches
        var mismatches: [String] = []
        
        for (package, lockEntry) in lockFile.dependencies {
            if let installedVersion = installedPackages[package] {
                if installedVersion != lockEntry.version {
                    mismatches.append(
                        "\(package): expected \(lockEntry.version), found \(installedVersion)"
                    )
                }
            } else {
                mismatches.append("\(package): not installed (expected \(lockEntry.version))")
            }
        }
        
        return mismatches
    }
    
    /// Get the locked version for a package
    public func getLockedVersion(for package: String, in lockFile: VeloLockFile) -> String? {
        return lockFile.dependencies[package]?.version
    }
}