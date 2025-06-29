import Foundation
import VeloSystem

/// Manages the context of package installations (local vs global)
public final class ProjectContext {
    private let fileManager = FileManager.default
    private let currentDirectory: URL
    
    /// The detected project root (directory containing velo.json)
    public private(set) var projectRoot: URL?
    
    /// Whether we're in a project context (has velo.json)
    public var isProjectContext: Bool {
        projectRoot != nil
    }
    
    /// Local .velo directory path if in project context
    public var localVeloPath: URL? {
        projectRoot?.appendingPathComponent(".velo")
    }
    
    /// Path to velo.json if it exists
    public var manifestPath: URL? {
        projectRoot?.appendingPathComponent("velo.json")
    }
    
    /// Path to velo.lock if it exists
    public var lockFilePath: URL? {
        projectRoot?.appendingPathComponent("velo.lock")
    }
    
    public init(currentDirectory: URL? = nil) {
        self.currentDirectory = currentDirectory ?? URL(fileURLWithPath: fileManager.currentDirectoryPath)
        self.projectRoot = findProjectRoot()
    }
    
    /// Find the nearest velo.json by traversing up the directory tree
    private func findProjectRoot() -> URL? {
        var searchPath = currentDirectory
        
        // Traverse up to find velo.json
        while searchPath.path != "/" {
            let manifestPath = searchPath.appendingPathComponent("velo.json")
            if fileManager.fileExists(atPath: manifestPath.path) {
                return searchPath
            }
            searchPath = searchPath.deletingLastPathComponent()
        }
        
        // Check root directory
        let rootManifest = URL(fileURLWithPath: "/").appendingPathComponent("velo.json")
        if fileManager.fileExists(atPath: rootManifest.path) {
            return URL(fileURLWithPath: "/")
        }
        
        return nil
    }
    
    /// Get the appropriate PathHelper based on context
    public func getPathHelper(preferLocal: Bool = true) -> PathHelper {
        if preferLocal, let localPath = localVeloPath {
            // Create a local PathHelper that uses .velo directory
            return PathHelper(customHome: localPath)
        } else {
            // Use global PathHelper
            return PathHelper.shared
        }
    }
    
    /// Determine if a command should use local or global packages
    public func shouldUseLocal(forceGlobal: Bool = false) -> Bool {
        if forceGlobal {
            return false
        }
        return isProjectContext
    }
    
    /// Create local .velo directory structure
    public func initializeLocalVelo() throws {
        guard let localPath = localVeloPath else {
            throw VeloError.notInProjectContext
        }
        
        let pathHelper = PathHelper(customHome: localPath)
        try pathHelper.ensureVeloDirectories()
    }
}