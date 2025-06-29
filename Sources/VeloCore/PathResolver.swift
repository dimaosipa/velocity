import Foundation
import VeloSystem

/// Configuration for path resolution behavior
public struct PathResolutionConfig: Codable {
    public let traverseParents: Bool
    public let preferLocal: Bool
    public let pathPrecedence: [PathScope]
    
    public enum PathScope: String, Codable {
        case local
        case global
        case system
    }
    
    public static let `default` = PathResolutionConfig(
        traverseParents: true,
        preferLocal: true,
        pathPrecedence: [.local, .global, .system]
    )
    
    public init(
        traverseParents: Bool = true,
        preferLocal: Bool = true,
        pathPrecedence: [PathScope] = [.local, .global, .system]
    ) {
        self.traverseParents = traverseParents
        self.preferLocal = preferLocal
        self.pathPrecedence = pathPrecedence
    }
}

/// Resolves which version of a binary should be used based on context and configuration
public final class PathResolver {
    private let fileManager = FileManager.default
    private let globalPathHelper = PathHelper.shared
    
    public init() {}
    
    /// Resolve a binary to its full path based on current context and configuration
    public func resolveBinary(
        _ name: String,
        context: ProjectContext,
        config: PathResolutionConfig = .default,
        scope: PathResolutionConfig.PathScope? = nil
    ) -> URL? {
        // If specific scope requested, only check that scope
        if let requestedScope = scope {
            return resolveBinaryInScope(name, scope: requestedScope, context: context)
        }
        
        // Otherwise, check scopes in configured order
        for scope in config.pathPrecedence {
            if let resolved = resolveBinaryInScope(name, scope: scope, context: context, config: config) {
                return resolved
            }
        }
        
        return nil
    }
    
    /// Resolve which command will be executed (shows all possible matches)
    public func which(
        _ name: String,
        context: ProjectContext,
        config: PathResolutionConfig = .default
    ) -> WhichResult {
        var results: [WhichResult.Match] = []
        
        // Check local installations
        if let localPaths = findLocalBinaries(name, context: context, config: config) {
            results.append(contentsOf: localPaths.map { path in
                WhichResult.Match(
                    path: path,
                    scope: .local,
                    version: extractVersion(from: path, package: name),
                    isDefault: false
                )
            })
        }
        
        // Check global installation
        let globalBinPath = globalPathHelper.binPath.appendingPathComponent(name)
        if fileManager.fileExists(atPath: globalBinPath.path) {
            results.append(WhichResult.Match(
                path: globalBinPath,
                scope: .global,
                version: extractVersion(from: globalBinPath, package: name),
                isDefault: false
            ))
        }
        
        // Check system paths
        if let systemPath = findInSystemPath(name) {
            results.append(WhichResult.Match(
                path: systemPath,
                scope: .system,
                version: nil,
                isDefault: false
            ))
        }
        
        // Mark the first match as default based on precedence
        if !results.isEmpty {
            for scope in config.pathPrecedence {
                if let index = results.firstIndex(where: { $0.scope == scope }) {
                    results[index].isDefault = true
                    break
                }
            }
        }
        
        return WhichResult(binary: name, matches: results)
    }
    
    // MARK: - Private Methods
    
    private func resolveBinaryInScope(
        _ name: String,
        scope: PathResolutionConfig.PathScope,
        context: ProjectContext,
        config: PathResolutionConfig = .default
    ) -> URL? {
        switch scope {
        case .local:
            return findLocalBinaries(name, context: context, config: config)?.first
        case .global:
            let globalPath = globalPathHelper.binPath.appendingPathComponent(name)
            return fileManager.fileExists(atPath: globalPath.path) ? globalPath : nil
        case .system:
            return findInSystemPath(name)
        }
    }
    
    private func findLocalBinaries(
        _ name: String,
        context: ProjectContext,
        config: PathResolutionConfig
    ) -> [URL]? {
        var results: [URL] = []
        
        // Check project local .velo
        if let localVeloPath = context.localVeloPath {
            let localBinPath = localVeloPath.appendingPathComponent("bin").appendingPathComponent(name)
            if fileManager.fileExists(atPath: localBinPath.path) {
                results.append(localBinPath)
            }
        }
        
        // Traverse parent directories if configured
        if config.traverseParents && results.isEmpty {
            var searchPath = context.projectRoot?.deletingLastPathComponent()
            
            while let path = searchPath, path.path != "/" {
                let parentVeloPath = path.appendingPathComponent(".velo/bin").appendingPathComponent(name)
                if fileManager.fileExists(atPath: parentVeloPath.path) {
                    results.append(parentVeloPath)
                    break // Stop at first parent match
                }
                searchPath = path.deletingLastPathComponent()
            }
        }
        
        return results.isEmpty ? nil : results
    }
    
    private func findInSystemPath(_ name: String) -> URL? {
        let systemPaths = [
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/opt/homebrew/bin", // Homebrew on Apple Silicon
            "/opt/local/bin"     // MacPorts
        ]
        
        for path in systemPaths {
            let binaryPath = URL(fileURLWithPath: path).appendingPathComponent(name)
            if fileManager.fileExists(atPath: binaryPath.path) {
                return binaryPath
            }
        }
        
        return nil
    }
    
    private func extractVersion(from path: URL, package: String) -> String? {
        // Try to resolve symlink and extract version from the target path
        if let resolvedPath = try? fileManager.destinationOfSymbolicLink(atPath: path.path) {
            // Look for version pattern in path like /Cellar/package/1.2.3/
            let components = resolvedPath.split(separator: "/")
            if let packageIndex = components.firstIndex(of: Substring(package)),
               packageIndex + 1 < components.count {
                return String(components[packageIndex + 1])
            }
        }
        return nil
    }
}

/// Result of the which command
public struct WhichResult {
    public let binary: String
    public let matches: [Match]
    
    public struct Match {
        public let path: URL
        public let scope: PathResolutionConfig.PathScope
        public let version: String?
        public var isDefault: Bool
    }
    
    public var defaultMatch: Match? {
        matches.first { $0.isDefault }
    }
}