import Foundation
import VeloFormula
import VeloSystem

// MARK: - Dependency Node

public struct DependencyNode {
    public let name: String
    public let formula: Formula
    public let dependencies: [String]  // Names of direct dependencies
    public var isInstalled: Bool
    public let equivalentPackages: Set<String>  // All equivalent package names
    
    public init(name: String, formula: Formula, dependencies: [String], isInstalled: Bool = false, equivalentPackages: Set<String> = []) {
        self.name = name
        self.formula = formula
        self.dependencies = dependencies
        self.isInstalled = isInstalled
        self.equivalentPackages = equivalentPackages.isEmpty ? [name] : equivalentPackages
    }
}

// MARK: - Dependency Graph

public class DependencyGraph {
    private var nodes: [String: DependencyNode] = [:]
    private var edges: [String: Set<String>] = [:]  // package -> its dependencies
    private let pathHelper: PathHelper
    private let packageEquivalence: PackageEquivalence
    
    public init(pathHelper: PathHelper = PathHelper.shared, packageEquivalence: PackageEquivalence = PackageEquivalence.shared) {
        self.pathHelper = pathHelper
        self.packageEquivalence = packageEquivalence
    }
    
    // MARK: - Graph Building
    
    /// Build complete dependency graph starting from a root package with deduplication
    public func buildCompleteGraph(for rootPackages: [String], tapManager: TapManager) async throws {
        OSLogger.shared.verbose("📊 Building complete dependency graph for \(rootPackages.joined(separator: ", "))", category: OSLogger.shared.installer)
        
        // Phase 1: Discover all packages and collect dependencies
        var allPackages = Set<String>()
        var packageDependencies: [String: [String]] = [:]
        
        for rootPackage in rootPackages {
            try await discoverDependencies(
                package: rootPackage,
                tapManager: tapManager,
                allPackages: &allPackages,
                packageDependencies: &packageDependencies,
                visited: Set<String>(),
                visiting: Set<String>()
            )
        }
        
        // Phase 2: Resolve package equivalencies and deduplicate
        let (canonicalPackages, equivalencyMap) = deduplicatePackages(allPackages)
        
        // Phase 3: Build final graph with resolved packages
        try await buildResolvedGraph(canonicalPackages, equivalencyMap, packageDependencies, tapManager)
        
        OSLogger.shared.info("📊 Complete dependency graph built: \(nodes.count) packages")
    }
    
    /// Convenience method for single package (maintains backward compatibility)
    public func buildGraph(for rootPackage: String, tapManager: TapManager) async throws {
        try await buildCompleteGraph(for: [rootPackage], tapManager: tapManager)
    }
    
    /// Phase 1: Recursively discover all packages in the dependency tree
    private func discoverDependencies(
        package: String,
        tapManager: TapManager,
        allPackages: inout Set<String>,
        packageDependencies: inout [String: [String]],
        visited: Set<String>,
        visiting: Set<String>
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
        
        var newVisiting = visiting
        newVisiting.insert(package)
        allPackages.insert(package)
        
        // Get formula for this package
        guard let formula = try tapManager.findFormula(package) else {
            throw VeloError.formulaNotFound(name: package)
        }
        
        // Get runtime dependencies
        let dependencies = formula.dependencies
            .filter { $0.type == .required }
            .map { $0.name }
        
        packageDependencies[package] = dependencies
        
        var newVisited = visited
        newVisited.insert(package)
        
        // Recursively process dependencies
        for dependency in dependencies {
            try await discoverDependencies(
                package: dependency,
                tapManager: tapManager,
                allPackages: &allPackages,
                packageDependencies: &packageDependencies,
                visited: newVisited,
                visiting: newVisiting
            )
        }
    }
    
    /// Phase 2: Deduplicate equivalent packages
    private func deduplicatePackages(_ allPackages: Set<String>) -> (canonical: Set<String>, equivalencyMap: [String: String]) {
        var canonicalPackages = Set<String>()
        var equivalencyMap: [String: String] = [:]
        var processedEquivalents = Set<String>()
        
        for package in allPackages {
            if processedEquivalents.contains(package) {
                continue
            }
            
            let equivalents = packageEquivalence.getEquivalentPackages(for: package)
            let canonical = packageEquivalence.getCanonicalName(for: package)
            
            canonicalPackages.insert(canonical)
            
            for equivalent in equivalents {
                equivalencyMap[equivalent] = canonical
                processedEquivalents.insert(equivalent)
            }
        }
        
        OSLogger.shared.verbose("Deduplication: \(allPackages.count) -> \(canonicalPackages.count) packages", category: OSLogger.shared.installer)
        return (canonicalPackages, equivalencyMap)
    }
    
    
    /// Phase 3: Build final resolved graph
    private func buildResolvedGraph(
        _ canonicalPackages: Set<String>,
        _ equivalencyMap: [String: String],
        _ packageDependencies: [String: [String]],
        _ tapManager: TapManager
    ) async throws {
        OSLogger.shared.verbose("Building resolved graph for \(canonicalPackages.count) canonical packages", category: OSLogger.shared.installer)
        
        for canonicalPackage in canonicalPackages {
            // Find the best formula to use (prefer exact canonical name)
            var formula = try tapManager.findFormula(canonicalPackage)
            
            if formula == nil {
                // Try to find any equivalent formula
                let equivalents = packageEquivalence.getEquivalentPackages(for: canonicalPackage)
                for equivalent in equivalents {
                    if let f = try tapManager.findFormula(equivalent) {
                        formula = f
                        break
                    }
                }
                
                guard let finalFormula = formula else {
                    throw VeloError.formulaNotFound(name: canonicalPackage)
                }
                formula = finalFormula
            }
            
            // Check if already installed (check all equivalent names)
            let equivalents = packageEquivalence.getEquivalentPackages(for: canonicalPackage)
            let isInstalled = equivalents.contains { pathHelper.isPackageInstalled($0) }
            
            // Get dependencies for this canonical package
            // Find dependencies from any equivalent package that has dependencies recorded
            var dependencies: [String] = []
            for equivalent in equivalents {
                if let deps = packageDependencies[equivalent] {
                    dependencies = deps
                    break
                }
            }
            
            // Map dependencies to canonical names
            let canonicalDependencies = dependencies.map { dep in
                equivalencyMap[dep] ?? dep
            }
            
            // Create node
            let node = DependencyNode(
                name: canonicalPackage,
                formula: formula!,
                dependencies: canonicalDependencies,
                isInstalled: isInstalled,
                equivalentPackages: equivalents
            )
            
            nodes[canonicalPackage] = node
            edges[canonicalPackage] = Set(canonicalDependencies)
            
            OSLogger.shared.verbose("Added \(canonicalPackage) with dependencies: \(canonicalDependencies.joined(separator: ", "))", category: OSLogger.shared.installer)
        }
        
        // Log final graph structure for debugging
        OSLogger.shared.verbose("Final dependency graph:", category: OSLogger.shared.installer)
        for (package, deps) in edges.sorted(by: { $0.key < $1.key }) {
            OSLogger.shared.verbose("  \(package) -> [\(Array(deps).sorted().joined(separator: ", "))]", category: OSLogger.shared.installer)
        }
    }
    
    // MARK: - Graph Analysis
    
    // Cached package analysis results
    private var _packageAnalysis: (new: [DependencyNode], installable: [DependencyNode], uninstallable: [DependencyNode])?
    
    /// Compute package analysis once and cache results
    private func computePackageAnalysis() -> (new: [DependencyNode], installable: [DependencyNode], uninstallable: [DependencyNode]) {
        if let cached = _packageAnalysis {
            return cached
        }
        
        let new = nodes.values.filter { !$0.isInstalled }
        var installable: [DependencyNode] = []
        var uninstallable: [DependencyNode] = []
        
        for package in new {
            if package.formula.hasCompatibleBottle {
                installable.append(package)
            } else {
                uninstallable.append(package)
            }
        }
        
        let result = (new: new, installable: installable, uninstallable: uninstallable)
        _packageAnalysis = result
        return result
    }
    
    /// Get packages that need to be installed (not already installed)
    public var newPackages: [DependencyNode] {
        return computePackageAnalysis().new
    }
    
    /// Get packages that can be installed (have compatible bottles)
    public var installablePackages: [DependencyNode] {
        return computePackageAnalysis().installable
    }
    
    /// Get packages that cannot be installed (no compatible bottles)
    public var uninstallablePackages: [DependencyNode] {
        return computePackageAnalysis().uninstallable
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
        OSLogger.shared.verbose("Computing topological sort for \(nodes.count) packages", category: OSLogger.shared.installer)
        
        var inDegree: [String: Int] = [:]
        var queue: [String] = []
        var result: [String] = []
        
        let startTime = Date()
        
        // Initialize in-degree count for all nodes
        for (package, _) in nodes {
            inDegree[package] = 0
        }
        OSLogger.shared.debug("Initialized in-degrees in \(Date().timeIntervalSince(startTime))s", category: OSLogger.shared.installer)
        
        // Count incoming edges (packages that depend on each package)
        for (_, dependencies) in edges {
            for dependency in dependencies {
                inDegree[dependency, default: 0] += 1
            }
        }
        OSLogger.shared.debug("Counted edges in \(Date().timeIntervalSince(startTime))s", category: OSLogger.shared.installer)
        
        // Find packages with no dependencies (in-degree = 0)
        for (package, degree) in inDegree {
            if degree == 0 {
                queue.append(package)
            }
        }
        OSLogger.shared.debug("Found \(queue.count) root packages in \(Date().timeIntervalSince(startTime))s", category: OSLogger.shared.installer)
        
        // Process queue with progress tracking
        var processed = 0
        let totalPackages = nodes.count
        
        while !queue.isEmpty {
            let current = queue.removeFirst()
            result.append(current)
            processed += 1
            
            // Log progress every 20 packages
            if processed % 20 == 0 {
                OSLogger.shared.debug("Processed \(processed)/\(totalPackages) packages", category: OSLogger.shared.installer)
            }
            
            // Reduce in-degree for all dependencies of the current package
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
            OSLogger.shared.error("Topological sort failed! Processed \(result.count) of \(nodes.count) packages", category: OSLogger.shared.installer)
            OSLogger.shared.error("Remaining packages: \(Array(remaining).sorted().joined(separator: ", "))", category: OSLogger.shared.installer)
            
            // Log in-degrees of remaining packages
            for package in remaining.sorted() {
                let degree = inDegree[package] ?? -1
                let deps = Array(edges[package] ?? []).sorted().joined(separator: ", ")
                OSLogger.shared.error("  \(package): in-degree=\(degree), dependencies=[\(deps)]", category: OSLogger.shared.installer)
            }
            
            throw VeloError.installationFailed(
                package: "dependency_graph",
                reason: "Circular dependency detected involving: \(Array(remaining).sorted().joined(separator: ", "))"
            )
        }
        
        OSLogger.shared.verbose("Topological sort completed: \(result.joined(separator: " -> "))", category: OSLogger.shared.installer)
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
            let node = nodes[package]
            let isInstalled = node?.isInstalled ?? false
            let status = isInstalled ? "✅" : "📦"
            let equivalents = node?.equivalentPackages ?? []
            
            if dependencies.isEmpty {
                OSLogger.shared.debug("  \(status) \(package) (no dependencies)", category: OSLogger.shared.installer)
            } else {
                OSLogger.shared.debug("  \(status) \(package) -> \(Array(dependencies).sorted().joined(separator: ", "))", category: OSLogger.shared.installer)
            }
            
            // Show equivalents if any
            if equivalents.count > 1 {
                let others = equivalents.filter { $0 != package }
                if !others.isEmpty {
                    OSLogger.shared.debug("    Equivalents: \(others.sorted().joined(separator: ", "))", category: OSLogger.shared.installer)
                }
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
        OSLogger.shared.debug("Creating InstallPlan for \(rootPackage)", category: OSLogger.shared.installer)
        
        self.rootPackage = rootPackage
        
        OSLogger.shared.debug("Getting new packages...", category: OSLogger.shared.installer)
        self.newPackages = graph.newPackages
        OSLogger.shared.debug("Found \(self.newPackages.count) new packages", category: OSLogger.shared.installer)
        
        OSLogger.shared.debug("Getting installed packages...", category: OSLogger.shared.installer)
        self.alreadyInstalled = graph.installedPackages
        OSLogger.shared.debug("Found \(self.alreadyInstalled.count) installed packages", category: OSLogger.shared.installer)
        
        OSLogger.shared.debug("Computing install order...", category: OSLogger.shared.installer)
        self.installOrder = try graph.getInstallOrder()
        OSLogger.shared.debug("Install order computed with \(self.installOrder.count) packages", category: OSLogger.shared.installer)
        
        OSLogger.shared.debug("Estimating download size...", category: OSLogger.shared.installer)
        self.estimatedSize = try graph.estimatedDownloadSize()
        OSLogger.shared.debug("InstallPlan created successfully", category: OSLogger.shared.installer)
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