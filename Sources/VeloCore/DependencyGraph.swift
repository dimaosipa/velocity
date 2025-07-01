import Foundation
import VeloFormula
import VeloSystem

// MARK: - Dependency Node

public struct DependencyNode {
    public let name: String
    public let formula: Formula
    public let dependencies: [String]  // Names of direct dependencies
    public var isInstalled: Bool
    
    public init(name: String, formula: Formula, dependencies: [String], isInstalled: Bool = false) {
        self.name = name
        self.formula = formula
        self.dependencies = dependencies
        self.isInstalled = isInstalled
    }
}

// MARK: - Dependency Graph

public class DependencyGraph {
    private var nodes: [String: DependencyNode] = [:]
    private var edges: [String: Set<String>] = [:]  // package -> its dependencies
    private let pathHelper: PathHelper
    
    public init(pathHelper: PathHelper = PathHelper.shared) {
        self.pathHelper = pathHelper
    }
    
    // MARK: - Graph Building
    
    /// Build complete dependency graph starting from a root package
    public func buildGraph(for rootPackage: String, tapManager: TapManager) async throws {
        OSLogger.shared.verbose("📊 Building dependency graph for \(rootPackage)", category: OSLogger.shared.installer)
        
        var visited = Set<String>()
        var visiting = Set<String>()  // For cycle detection
        
        try await buildGraphRecursive(
            package: rootPackage,
            tapManager: tapManager,
            visited: &visited,
            visiting: &visiting
        )
        
        OSLogger.shared.info("📊 Dependency graph built: \(nodes.count) total packages")
    }
    
    private func buildGraphRecursive(
        package: String,
        tapManager: TapManager,
        visited: inout Set<String>,
        visiting: inout Set<String>
    ) async throws {
        // Cycle detection
        if visiting.contains(package) {
            throw VeloError.installationFailed(
                package: package,
                reason: "Circular dependency detected in chain: \(Array(visiting).joined(separator: " -> "))"
            )
        }
        
        // Skip if already processed
        if visited.contains(package) {
            return
        }
        
        visiting.insert(package)
        
        // Get formula for this package
        guard let formula = try tapManager.findFormula(package) else {
            throw VeloError.formulaNotFound(name: package)
        }
        
        // Get runtime dependencies
        let runtimeDeps = formula.dependencies
            .filter { $0.type == .required }
            .map { $0.name }
        
        // Check if already installed
        let isInstalled = pathHelper.isPackageInstalled(package)
        
        // Create node
        let node = DependencyNode(
            name: package,
            formula: formula,
            dependencies: runtimeDeps,
            isInstalled: isInstalled
        )
        
        nodes[package] = node
        edges[package] = Set(runtimeDeps)
        
        // Recursively process dependencies
        for dependency in runtimeDeps {
            try await buildGraphRecursive(
                package: dependency,
                tapManager: tapManager,
                visited: &visited,
                visiting: &visiting
            )
        }
        
        visiting.remove(package)
        visited.insert(package)
    }
    
    // MARK: - Graph Analysis
    
    /// Get packages that need to be installed (not already installed)
    public var newPackages: [DependencyNode] {
        return nodes.values.filter { !$0.isInstalled }
    }
    
    /// Get packages that are already installed
    public var installedPackages: [DependencyNode] {
        return nodes.values.filter { $0.isInstalled }
    }
    
    /// Get all packages in the graph
    public var allPackages: [DependencyNode] {
        return Array(nodes.values)
    }
    
    /// Get total download size estimate
    public func estimatedDownloadSize() throws -> Int64 {
        // This would require examining bottle sizes - placeholder for now
        return Int64(newPackages.count) * 5_000_000  // Rough estimate: 5MB per package
    }
    
    // MARK: - Topological Sort
    
    /// Get packages in installation order using topological sort
    public func getInstallOrder() throws -> [String] {
        var inDegree: [String: Int] = [:]
        var queue: [String] = []
        var result: [String] = []
        
        // Initialize in-degree count for all nodes
        for (package, _) in nodes {
            inDegree[package] = 0
        }
        
        // Count incoming edges (dependencies pointing to each package)
        for (_, dependencies) in edges {
            for dependency in dependencies {
                inDegree[dependency, default: 0] += 1
            }
        }
        
        // Find packages with no dependencies (in-degree = 0)
        for (package, degree) in inDegree {
            if degree == 0 {
                queue.append(package)
            }
        }
        
        // Process queue
        while !queue.isEmpty {
            let current = queue.removeFirst()
            result.append(current)
            
            // Reduce in-degree for all packages that depend on current
            if let dependencies = edges[current] {
                for dependency in dependencies {
                    inDegree[dependency]! -= 1
                    if inDegree[dependency]! == 0 {
                        queue.append(dependency)
                    }
                }
            }
        }
        
        // Check for cycles
        if result.count != nodes.count {
            let remaining = Set(nodes.keys).subtracting(Set(result))
            throw VeloError.installationFailed(
                package: "dependency_graph",
                reason: "Circular dependency detected involving: \(Array(remaining).joined(separator: ", "))"
            )
        }
        
        return result
    }
    
    // MARK: - Utilities
    
    /// Get node for a package
    public func getNode(for package: String) -> DependencyNode? {
        return nodes[package]
    }
    
    /// Get dependencies of a package
    public func getDependencies(of package: String) -> [String] {
        return Array(edges[package] ?? [])
    }
    
    /// Print dependency graph for debugging
    public func printGraph() {
        OSLogger.shared.verbose("Dependency Graph:", category: OSLogger.shared.installer)
        for (package, dependencies) in edges.sorted(by: { $0.key < $1.key }) {
            let isInstalled = nodes[package]?.isInstalled ?? false
            let status = isInstalled ? "✅" : "📦"
            if dependencies.isEmpty {
                OSLogger.shared.debug("  \(status) \(package) (no dependencies)", category: OSLogger.shared.installer)
            } else {
                OSLogger.shared.debug("  \(status) \(package) -> \(Array(dependencies).sorted().joined(separator: ", "))", category: OSLogger.shared.installer)
            }
        }
    }
}

// MARK: - Install Plan

public struct InstallPlan {
    public let rootPackage: String
    public let newPackages: [DependencyNode]
    public let alreadyInstalled: [DependencyNode]
    public let installOrder: [String]
    public let estimatedSize: Int64
    
    public init(graph: DependencyGraph, rootPackage: String) throws {
        self.rootPackage = rootPackage
        self.newPackages = graph.newPackages
        self.alreadyInstalled = graph.installedPackages
        self.installOrder = try graph.getInstallOrder()
        self.estimatedSize = try graph.estimatedDownloadSize()
    }
    
    /// Display install plan to user
    public func display() {
        OSLogger.shared.info("📦 Install plan for \(rootPackage):")
        OSLogger.shared.info("   New packages: \(newPackages.count)")
        OSLogger.shared.info("   Already installed: \(alreadyInstalled.count)")
        OSLogger.shared.info("   Total packages: \(newPackages.count + alreadyInstalled.count)")
        
        if !newPackages.isEmpty {
            OSLogger.shared.verbose("   Packages to install:", category: OSLogger.shared.installer)
            for package in newPackages.prefix(10) {  // Show first 10
                OSLogger.shared.debug("     • \(package.name) \(package.formula.version)", category: OSLogger.shared.installer)
            }
            if newPackages.count > 10 {
                OSLogger.shared.verbose("     ... and \(newPackages.count - 10) more", category: OSLogger.shared.installer)
            }
        }
        
        let sizeInMB = estimatedSize / 1_000_000
        OSLogger.shared.info("   Estimated download: ~\(sizeInMB) MB")
    }
}