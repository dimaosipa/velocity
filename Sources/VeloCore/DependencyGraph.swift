import Foundation
import VeloFormula
import VeloSystem

// MARK: - Dependency Node

public struct DependencyNode {
    public let name: String
    public let formula: Formula
    public let dependencies: [DependencyRequirement]  // Dependency requirements with constraints
    public var isInstalled: Bool
    public let equivalentPackages: Set<String>  // All equivalent package names
    
    public init(name: String, formula: Formula, dependencies: [DependencyRequirement], isInstalled: Bool = false, equivalentPackages: Set<String> = []) {
        self.name = name
        self.formula = formula
        self.dependencies = dependencies
        self.isInstalled = isInstalled
        self.equivalentPackages = equivalentPackages.isEmpty ? [name] : equivalentPackages
    }
}

public struct DependencyRequirement {
    public let name: String
    public let versionConstraints: VersionConstraintSet
    public let type: Formula.Dependency.DependencyType
    
    public init(name: String, versionConstraints: VersionConstraintSet, type: Formula.Dependency.DependencyType) {
        self.name = name
        self.versionConstraints = versionConstraints
        self.type = type
    }
}

// MARK: - Dependency Graph

public class DependencyGraph {
    private var nodes: [String: DependencyNode] = [:]
    private var edges: [String: Set<String>] = [:]  // package -> its dependencies
    private let pathHelper: PathHelper
    private let packageEquivalence: PackageEquivalence
    private var versionConstraints: [String: VersionConstraintSet] = [:]  // Collected constraints per canonical package
    private var conflictDetected: [VersionConflict] = []
    
    public init(pathHelper: PathHelper = PathHelper.shared, packageEquivalence: PackageEquivalence = PackageEquivalence.shared) {
        self.pathHelper = pathHelper
        self.packageEquivalence = packageEquivalence
    }
    
    // MARK: - Graph Building
    
    /// Build complete dependency graph starting from a root package with deduplication and conflict detection
    public func buildCompleteGraph(for rootPackages: [String], tapManager: TapManager) async throws {
        OSLogger.shared.verbose("📊 Building complete dependency graph for \(rootPackages.joined(separator: ", "))", category: OSLogger.shared.installer)
        
        // Phase 1: Discover all packages and collect requirements
        var allPackages = Set<String>()
        var packageRequirements: [String: [DependencyRequirement]] = [:]
        
        for rootPackage in rootPackages {
            try await discoverDependencies(
                package: rootPackage,
                tapManager: tapManager,
                allPackages: &allPackages,
                packageRequirements: &packageRequirements,
                visited: Set<String>(),
                visiting: Set<String>()
            )
        }
        
        // Phase 2: Resolve package equivalencies and deduplicate
        let (canonicalPackages, equivalencyMap) = deduplicatePackages(allPackages)
        
        // Phase 3: Collect and validate version constraints
        try collectVersionConstraints(packageRequirements, canonicalPackages, equivalencyMap, tapManager)
        
        // Phase 4: Check for version conflicts
        detectVersionConflicts()
        
        // Phase 5: Build final graph with resolved packages
        try await buildResolvedGraph(canonicalPackages, equivalencyMap, tapManager)
        
        OSLogger.shared.info("📊 Complete dependency graph built: \(nodes.count) packages, \(conflictDetected.count) conflicts")
        
        // Report conflicts if any
        if !conflictDetected.isEmpty {
            for conflict in conflictDetected {
                OSLogger.shared.warning("Version conflict: \(conflict.description)")
            }
        }
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
        packageRequirements: inout [String: [DependencyRequirement]],
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
        
        // Convert formula dependencies to requirements with version constraints
        let requirements = formula.dependencies
            .filter { $0.type == .required }
            .map { dep in
                let constraints = VersionConstraintSet.parse(from: dep.versionConstraints ?? [])
                return DependencyRequirement(name: dep.name, versionConstraints: constraints, type: dep.type)
            }
        
        packageRequirements[package] = requirements
        
        var newVisited = visited
        newVisited.insert(package)
        
        // Recursively process dependencies
        for requirement in requirements {
            try await discoverDependencies(
                package: requirement.name,
                tapManager: tapManager,
                allPackages: &allPackages,
                packageRequirements: &packageRequirements,
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
    
    /// Phase 3: Collect version constraints per canonical package
    private func collectVersionConstraints(
        _ packageRequirements: [String: [DependencyRequirement]],
        _ canonicalPackages: Set<String>,
        _ equivalencyMap: [String: String],
        _ tapManager: TapManager
    ) throws {
        
        for canonicalPackage in canonicalPackages {
            var allConstraints: [VersionConstraint] = []
            
            // Collect constraints from all equivalent packages
            for (package, requirements) in packageRequirements {
                let packageCanonical = equivalencyMap[package] ?? package
                if packageCanonical == canonicalPackage {
                    for requirement in requirements {
                        let reqCanonical = equivalencyMap[requirement.name] ?? requirement.name
                        if reqCanonical == canonicalPackage {
                            allConstraints.append(contentsOf: requirement.versionConstraints.constraints)
                        }
                    }
                }
            }
            
            versionConstraints[canonicalPackage] = VersionConstraintSet(constraints: allConstraints)
        }
    }
    
    /// Phase 4: Detect version conflicts
    private func detectVersionConflicts() {
        var conflictsByPackage: [String: [String]] = [:]
        
        for (package, constraintSet) in versionConstraints {
            if constraintSet.constraints.count > 1 {
                // Check if constraints are mutually compatible
                let versions = Set(constraintSet.constraints.map { $0.version })
                if versions.count > 1 {
                    // Multiple different version requirements
                    let requirements = constraintSet.constraints.map { "\($0.`operator`.rawValue) \($0.version)" }
                    conflictsByPackage[package] = requirements
                }
            }
        }
        
        // Convert to VersionConflict objects
        conflictDetected = conflictsByPackage.map { (package, requirements) in
            let conflictingReqs = requirements.map { ConflictingRequirement(package: package, version: $0) }
            return VersionConflict(canonicalPackage: package, conflictingRequirements: conflictingReqs)
        }
    }
    
    /// Phase 5: Build final resolved graph
    private func buildResolvedGraph(
        _ canonicalPackages: Set<String>,
        _ equivalencyMap: [String: String],
        _ tapManager: TapManager
    ) async throws {
        
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
            
            // Create dependency requirements
            let requirements = formula!.dependencies
                .filter { $0.type == .required }
                .map { dep in
                    let canonicalDep = equivalencyMap[dep.name] ?? dep.name
                    let constraints = versionConstraints[canonicalDep] ?? VersionConstraintSet(constraints: [])
                    return DependencyRequirement(name: canonicalDep, versionConstraints: constraints, type: dep.type)
                }
            
            // Create node
            let node = DependencyNode(
                name: canonicalPackage,
                formula: formula!,
                dependencies: requirements,
                isInstalled: isInstalled,
                equivalentPackages: equivalents
            )
            
            nodes[canonicalPackage] = node
            edges[canonicalPackage] = Set(requirements.map { $0.name })
        }
    }
    
    // MARK: - Graph Analysis
    
    /// Get packages that need to be installed (not already installed)
    public var newPackages: [DependencyNode] {
        return nodes.values.filter { !$0.isInstalled }
    }
    
    /// Get packages that can be installed (have compatible bottles)
    public var installablePackages: [DependencyNode] {
        return newPackages.filter { $0.formula.hasCompatibleBottle }
    }
    
    /// Get packages that cannot be installed (no compatible bottles)
    public var uninstallablePackages: [DependencyNode] {
        return newPackages.filter { !$0.formula.hasCompatibleBottle }
    }
    
    /// Get packages that are already installed
    public var installedPackages: [DependencyNode] {
        return nodes.values.filter { $0.isInstalled }
    }
    
    /// Get all packages in the graph
    public var allPackages: [DependencyNode] {
        return Array(nodes.values)
    }
    
    /// Get detected version conflicts
    public var versionConflicts: [VersionConflict] {
        return conflictDetected
    }
    
    /// Check if the graph has any conflicts
    public var hasConflicts: Bool {
        return !conflictDetected.isEmpty
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
    
    /// Get dependency requirements with constraints
    public func getDependencyRequirements(of package: String) -> [DependencyRequirement] {
        return nodes[package]?.dependencies ?? []
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
            
            // Show version constraints if any
            if let constraints = versionConstraints[package], !constraints.constraints.isEmpty {
                OSLogger.shared.debug("    Constraints: \(constraints.description)", category: OSLogger.shared.installer)
            }
        }
        
        // Show conflicts
        if !conflictDetected.isEmpty {
            OSLogger.shared.verbose("Version Conflicts:", category: OSLogger.shared.installer)
            for conflict in conflictDetected {
                OSLogger.shared.debug("  ⚠️ \(conflict.description)", category: OSLogger.shared.installer)
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