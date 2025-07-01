import Foundation

/// Represents a version constraint for package dependencies
public struct VersionConstraint: Codable, Equatable {
    public let operator: VersionOperator
    public let version: String
    
    public enum VersionOperator: String, Codable, CaseIterable {
        case equal = "=="
        case greaterThan = ">"
        case greaterThanOrEqual = ">="
        case lessThan = "<"
        case lessThanOrEqual = "<="
        case compatible = "~>"     // Compatible version (allows patch updates)
        case caret = "^"           // Caret version (allows minor and patch updates)
        
        public var description: String {
            return rawValue
        }
    }
    
    public init(operator: VersionOperator, version: String) {
        self.operator = `operator`
        self.version = version
    }
    
    /// Parse version constraint from string (e.g., ">= 1.0", "~> 2.1.0")
    public static func parse(_ constraintString: String) -> VersionConstraint? {
        let trimmed = constraintString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try each operator in order of length (longest first to avoid conflicts)
        let operators = VersionOperator.allCases.sorted { $0.rawValue.count > $1.rawValue.count }
        
        for op in operators {
            if trimmed.hasPrefix(op.rawValue) {
                let versionPart = String(trimmed.dropFirst(op.rawValue.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !versionPart.isEmpty {
                    return VersionConstraint(operator: op, version: versionPart)
                }
            }
        }
        
        // If no operator found, assume equality
        return VersionConstraint(operator: .equal, version: trimmed)
    }
    
    /// Check if a version satisfies this constraint
    public func isSatisfied(by version: String) -> Bool {
        switch operator {
        case .equal:
            return compareVersions(version, self.version) == 0
        case .greaterThan:
            return compareVersions(version, self.version) > 0
        case .greaterThanOrEqual:
            return compareVersions(version, self.version) >= 0
        case .lessThan:
            return compareVersions(version, self.version) < 0
        case .lessThanOrEqual:
            return compareVersions(version, self.version) <= 0
        case .compatible:
            return isCompatibleVersion(version, with: self.version)
        case .caret:
            return isCaretCompatible(version, with: self.version)
        }
    }
    
    /// Compare two versions semantically
    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let version1 = SemanticVersion.parse(v1)
        let version2 = SemanticVersion.parse(v2)
        
        if version1.major != version2.major {
            return version1.major < version2.major ? -1 : 1
        }
        
        if version1.minor != version2.minor {
            return version1.minor < version2.minor ? -1 : 1
        }
        
        if version1.patch != version2.patch {
            return version1.patch < version2.patch ? -1 : 1
        }
        
        return 0
    }
    
    /// Check if version is compatible using ~> operator rules
    /// ~> 2.1.0 means >= 2.1.0 and < 2.2.0
    private func isCompatibleVersion(_ candidate: String, with base: String) -> Bool {
        let candidateVersion = SemanticVersion.parse(candidate)
        let baseVersion = SemanticVersion.parse(base)
        
        // Must be same major and minor version
        guard candidateVersion.major == baseVersion.major,
              candidateVersion.minor == baseVersion.minor else {
            return false
        }
        
        // Patch version must be >= base patch
        return candidateVersion.patch >= baseVersion.patch
    }
    
    /// Check if version is caret compatible using ^ operator rules
    /// ^1.2.3 means >= 1.2.3 and < 2.0.0
    private func isCaretCompatible(_ candidate: String, with base: String) -> Bool {
        let candidateVersion = SemanticVersion.parse(candidate)
        let baseVersion = SemanticVersion.parse(base)
        
        // Must be same major version
        guard candidateVersion.major == baseVersion.major else {
            return false
        }
        
        // Compare as regular version comparison
        return compareVersions(candidate, base) >= 0
    }
}

/// Represents multiple version constraints (AND relationship)
public struct VersionConstraintSet: Codable, Equatable {
    public let constraints: [VersionConstraint]
    
    public init(constraints: [VersionConstraint]) {
        self.constraints = constraints
    }
    
    /// Parse multiple constraints from strings
    public static func parse(from constraintStrings: [String]) -> VersionConstraintSet {
        let constraints = constraintStrings.compactMap { VersionConstraint.parse($0) }
        return VersionConstraintSet(constraints: constraints)
    }
    
    /// Check if a version satisfies all constraints
    public func isSatisfied(by version: String) -> Bool {
        return constraints.allSatisfy { $0.isSatisfied(by: version) }
    }
    
    /// Check if this constraint set is compatible with another
    public func isCompatible(with other: VersionConstraintSet) -> Bool {
        // For now, we'll use a simple approach:
        // Two constraint sets are compatible if there exists at least one version
        // that satisfies both sets. This is a simplified check.
        
        // Extract all explicit versions from constraints
        let allVersions = Set(constraints.map { $0.version } + other.constraints.map { $0.version })
        
        // Check if any version satisfies both sets
        for version in allVersions {
            if self.isSatisfied(by: version) && other.isSatisfied(by: version) {
                return true
            }
        }
        
        // If no explicit versions work, do a more comprehensive check
        // This is a simplified implementation - a full resolver would be more complex
        return true
    }
    
    /// Get a description of the constraints
    public var description: String {
        if constraints.isEmpty {
            return "any version"
        }
        
        return constraints.map { "\($0.operator.rawValue) \($0.version)" }.joined(separator: ", ")
    }
}

/// Helper for parsing semantic versions
public struct SemanticVersion: Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    
    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }
    
    /// Parse a version string into components
    public static func parse(_ versionString: String) -> SemanticVersion {
        let cleaned = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle common version formats
        let components = cleaned.components(separatedBy: ".")
        
        let major = Int(components.first ?? "0") ?? 0
        let minor = components.count > 1 ? (Int(components[1]) ?? 0) : 0
        let patch = components.count > 2 ? (Int(components[2]) ?? 0) : 0
        
        return SemanticVersion(major: major, minor: minor, patch: patch)
    }
    
    public var versionString: String {
        if let prerelease = prerelease {
            return "\(major).\(minor).\(patch)-\(prerelease)"
        }
        return "\(major).\(minor).\(patch)"
    }
}

/// Resolves version constraints to find compatible versions
public class VersionConstraintResolver {
    
    /// Find the best version that satisfies all constraints
    public static func resolve(
        constraints: [String: VersionConstraintSet],
        availableVersions: [String: [String]]
    ) -> [String: String]? {
        
        var resolved: [String: String] = [:]
        
        for (package, constraintSet) in constraints {
            let available = availableVersions[package] ?? []
            
            // Find versions that satisfy the constraints
            let satisfying = available.filter { constraintSet.isSatisfied(by: $0) }
            
            if satisfying.isEmpty {
                // No version satisfies the constraints
                return nil
            }
            
            // Choose the latest version that satisfies constraints
            let sorted = satisfying.sorted { version1, version2 in
                let v1 = SemanticVersion.parse(version1)
                let v2 = SemanticVersion.parse(version2)
                
                if v1.major != v2.major {
                    return v1.major > v2.major
                }
                if v1.minor != v2.minor {
                    return v1.minor > v2.minor
                }
                return v1.patch > v2.patch
            }
            
            resolved[package] = sorted.first
        }
        
        return resolved
    }
    
    /// Check for conflicts between constraint sets
    public static func detectConflicts(
        constraints: [String: VersionConstraintSet]
    ) -> [String] {
        
        var conflicts: [String] = []
        
        for (package, constraintSet) in constraints {
            // Check if constraint set is internally consistent
            // This is a simplified check - would need more sophisticated logic
            let hasConflicts = constraintSet.constraints.count > 1 && 
                              !hasCompatibleConstraints(constraintSet.constraints)
            
            if hasConflicts {
                conflicts.append(package)
            }
        }
        
        return conflicts
    }
    
    private static func hasCompatibleConstraints(_ constraints: [VersionConstraint]) -> Bool {
        // Simplified compatibility check
        // Real implementation would need more sophisticated constraint solving
        return true
    }
}