import Foundation
import VeloSystem

/// Manages package name equivalencies and version conflicts
public class PackageEquivalence {
    public static let shared = PackageEquivalence()

    private init() {}

    // MARK: - Package Name Equivalence

    /// Maps package names to their canonical equivalents
    /// This handles cases like python@3.9 vs python3.9 vs python39
    private let packageEquivalencies: [String: Set<String>] = [
        "python@3.9": ["python3.9", "python39", "python@3.9"],
        "python@3.10": ["python3.10", "python310", "python@3.10"],
        "python@3.11": ["python3.11", "python311", "python@3.11"],
        "python@3.12": ["python3.12", "python312", "python@3.12"],
        "python@3.13": ["python3.13", "python313", "python@3.13"],
        "node@18": ["node18", "nodejs18", "node@18"],
        "node@20": ["node20", "nodejs20", "node@20"],
        "node@22": ["node22", "nodejs22", "node@22"],
        "openssl@3": ["openssl3", "libssl3", "openssl@3"],
        "openssl@1.1": ["openssl1.1", "libssl1.1", "openssl@1.1"],
        "mysql@8.0": ["mysql8.0", "mysql8", "mysql@8.0"],
        "postgresql@14": ["postgresql14", "postgres14", "postgresql@14"],
        "postgresql@15": ["postgresql15", "postgres15", "postgresql@15"],
        "postgresql@16": ["postgresql16", "postgres16", "postgresql@16"]
    ]

    /// Get all equivalent package names for a given package
    public func getEquivalentPackages(for packageName: String) -> Set<String> {
        // First check explicit equivalency mappings
        for (_, equivalents) in packageEquivalencies {
            if equivalents.contains(packageName) {
                return equivalents
            }
        }

        // Check for version-based equivalencies (e.g., python@3.12.1 ≡ python@3.12.2)
        if let versionEquivalents = getVersionBasedEquivalents(for: packageName) {
            return versionEquivalents
        }

        // If no equivalents found, return just the original name
        return [packageName]
    }

    /// Get equivalent packages based on version similarity (same major.minor)
    private func getVersionBasedEquivalents(for packageName: String) -> Set<String>? {
        guard let (baseName, version) = parsePackageVersion(packageName) else {
            return nil
        }

        let majorMinor = getMajorMinorVersion(version)
        guard !majorMinor.isEmpty else {
            return nil
        }

        // Define packages that should use version-based equivalency
        let versionSensitivePackages = [
            "python", "node", "ruby", "java", "php", "perl", "go", "rust",
            "mysql", "postgresql", "postgres", "redis", "mongodb",
            "openssl", "llvm", "gcc", "clang"
        ]

        // Check if this is a version-sensitive package
        guard versionSensitivePackages.contains(baseName) else {
            return nil
        }

        // Generate common equivalent patterns for this major.minor version
        var equivalents = Set<String>([packageName])

        // Add @version format (python@3.12)
        equivalents.insert("\(baseName)@\(majorMinor)")

        // Add concatenated format (python312)
        let compactVersion = majorMinor.replacingOccurrences(of: ".", with: "")
        equivalents.insert("\(baseName)\(compactVersion)")

        // Add dotted format (python3.12)
        equivalents.insert("\(baseName)\(majorMinor)")

        return equivalents
    }

    /// Parse package name to extract base name and version
    private func parsePackageVersion(_ packageName: String) -> (baseName: String, version: String)? {
        // Handle @version format (python@3.12.1)
        if let atIndex = packageName.firstIndex(of: "@") {
            let baseName = String(packageName.prefix(upTo: atIndex))
            let version = String(packageName.suffix(from: packageName.index(after: atIndex)))
            return (baseName, version)
        }

        // Handle concatenated version format (python312, python3.12)
        // Look for patterns like python3.12, node18, etc.
        let patterns = [
            #"^([a-zA-Z]+)(\d+\.\d+(?:\.\d+)?)$"#,  // python3.12, node18.1
            #"^([a-zA-Z]+)(\d+)$"#                   // python312, node18
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: packageName, range: NSRange(packageName.startIndex..., in: packageName)) {

                let baseNameRange = Range(match.range(at: 1), in: packageName)!
                let versionRange = Range(match.range(at: 2), in: packageName)!

                let baseName = String(packageName[baseNameRange])
                let version = String(packageName[versionRange])

                return (baseName, version)
            }
        }

        return nil
    }

    /// Extract major.minor version from a version string
    private func getMajorMinorVersion(_ version: String) -> String {
        let parts = version.split(separator: ".")

        if parts.count >= 2 {
            // Standard major.minor format (3.12)
            return "\(parts[0]).\(parts[1])"
        } else if parts.count == 1, let major = Int(parts[0]) {
            // Single number - could be major version only
            return String(major)
        }

        return version
    }

    /// Get the canonical name for a package (the @-versioned name if it exists)
    public func getCanonicalName(for packageName: String) -> String {
        // First check explicit equivalency mappings
        for (canonical, equivalents) in packageEquivalencies {
            if equivalents.contains(packageName) {
                return canonical
            }
        }

        // For version-based equivalencies, prefer @version format as canonical
        if let (baseName, version) = parsePackageVersion(packageName) {
            let majorMinor = getMajorMinorVersion(version)
            if !majorMinor.isEmpty {
                let versionSensitivePackages = [
                    "python", "node", "ruby", "java", "php", "perl", "go", "rust",
                    "mysql", "postgresql", "postgres", "redis", "mongodb",
                    "openssl", "llvm", "gcc", "clang"
                ]

                if versionSensitivePackages.contains(baseName) {
                    return "\(baseName)@\(majorMinor)"
                }
            }
        }

        return packageName
    }

    /// Check if two package names are equivalent
    public func areEquivalent(_ package1: String, _ package2: String) -> Bool {
        let equivalents1 = getEquivalentPackages(for: package1)
        return equivalents1.contains(package2)
    }

    /// Check if two packages are equivalent based on version similarity (same major.minor)
    public func areVersionEquivalent(_ package1: String, _ package2: String) -> Bool {
        // First check explicit equivalencies
        if areEquivalent(package1, package2) {
            return true
        }

        // Check version-based equivalencies
        guard let equiv1 = getVersionBasedEquivalents(for: package1),
              let equiv2 = getVersionBasedEquivalents(for: package2) else {
            return false
        }

        // Check if they share any equivalents (same major.minor version)
        return !equiv1.intersection(equiv2).isEmpty
    }

    // MARK: - Installed Package Detection

    /// Find any equivalent package that is already installed
    public func findEquivalentInstalledPackage(for packageName: String, pathHelper: PathHelper) -> String? {
        let equivalents = getEquivalentPackages(for: packageName)

        for equivalent in equivalents {
            if pathHelper.isPackageInstalled(equivalent) {
                return equivalent
            }
        }
        return nil
    }

    /// Get all installed packages that are equivalent to the given package
    public func getInstalledEquivalents(for packageName: String, pathHelper: PathHelper) -> [String] {
        let equivalents = getEquivalentPackages(for: packageName)
        return equivalents.filter { pathHelper.isPackageInstalled($0) }
    }

    // MARK: - Version Conflict Detection

    /// Detect version conflicts between package requirements
    public func detectVersionConflicts(requirements: [String: String]) -> [VersionConflict] {
        var conflicts: [VersionConflict] = []
        var packagesByCanonical: [String: [(package: String, version: String)]] = [:]

        // Group requirements by canonical package name
        for (package, version) in requirements {
            let canonical = getCanonicalName(for: package)
            packagesByCanonical[canonical, default: []].append((package, version))
        }

        // Check for conflicts within each canonical group
        for (canonical, packages) in packagesByCanonical {
            if packages.count > 1 {
                // Multiple version requirements for the same logical package
                let versions = Set(packages.map { $0.version })
                if versions.count > 1 {
                    conflicts.append(VersionConflict(
                        canonicalPackage: canonical,
                        conflictingRequirements: packages.map {
                            ConflictingRequirement(package: $0.package, version: $0.version)
                        }
                    ))
                }
            }
        }

        return conflicts
    }

    // MARK: - Symlink Conflict Resolution

    /// Determine if a symlink conflict can be resolved automatically
    public func canResolveSymlinkConflict(
        existingPackage: String,
        newPackage: String,
        pathHelper: PathHelper
    ) -> SymlinkConflictResolution {

        // If packages are equivalent, allow replacement
        if areEquivalent(existingPackage, newPackage) {
            let existingVersions = pathHelper.installedVersions(for: existingPackage)
            let newVersions = pathHelper.installedVersions(for: newPackage)

            // Compare versions to determine which should be the default
            let latestExisting = existingVersions.last ?? "0.0.0"
            let latestNew = newVersions.last ?? "0.0.0"

            if compareVersions(latestNew, latestExisting) >= 0 {
                return .allowReplacement(reason: "Newer version of equivalent package")
            } else {
                return .requiresConfirmation(reason: "Older version of equivalent package")
            }
        }

        // Different packages - require user confirmation
        return .requiresConfirmation(reason: "Different package")
    }

    // MARK: - Version Comparison

    /// Compare two version strings (returns -1, 0, or 1)
    private func compareVersions(_ version1: String, _ version2: String) -> Int {
        let v1Parts = version1.split(separator: ".").compactMap { Int(String($0)) }
        let v2Parts = version2.split(separator: ".").compactMap { Int(String($0)) }

        let maxLength = max(v1Parts.count, v2Parts.count)

        for i in 0..<maxLength {
            let v1Part = i < v1Parts.count ? v1Parts[i] : 0
            let v2Part = i < v2Parts.count ? v2Parts[i] : 0

            if v1Part < v2Part {
                return -1
            } else if v1Part > v2Part {
                return 1
            }
        }

        return 0
    }
}

// MARK: - Supporting Types

public struct VersionConflict {
    public let canonicalPackage: String
    public let conflictingRequirements: [ConflictingRequirement]

    public var description: String {
        let requirementStrings = conflictingRequirements.map { "\($0.package)@\($0.version)" }
        return "Version conflict for \(canonicalPackage): \(requirementStrings.joined(separator: ", "))"
    }
}

public struct ConflictingRequirement {
    public let package: String
    public let version: String
}

public enum SymlinkConflictResolution {
    case allowReplacement(reason: String)
    case requiresConfirmation(reason: String)

    public var shouldPromptUser: Bool {
        switch self {
        case .allowReplacement:
            return false
        case .requiresConfirmation:
            return true
        }
    }

    public var reason: String {
        switch self {
        case .allowReplacement(let reason):
            return reason
        case .requiresConfirmation(let reason):
            return reason
        }
    }
}
