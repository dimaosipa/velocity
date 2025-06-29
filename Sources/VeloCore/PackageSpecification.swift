import Foundation

/// Represents a package specification that can include version information
public struct PackageSpecification {
    /// The package name (without version)
    public let name: String

    /// The version specification, if provided
    public let version: String?

    /// Initialize with a package name and optional version
    public init(name: String, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

public extension PackageSpecification {
    /// Parse a package specification from a string that may contain @version syntax
    /// Examples:
    /// - "wget" -> PackageSpecification(name: "wget", version: nil)
    /// - "wget@1.25.0" -> PackageSpecification(name: "wget", version: "1.25.0")  
    /// - "openssl@3" -> PackageSpecification(name: "openssl", version: "3")
    /// - "python@3.11" -> PackageSpecification(name: "python", version: "3.11")
    static func parse(_ specification: String) -> PackageSpecification {
        // Special case: handle "@" as empty name and empty version
        if specification == "@" {
            return PackageSpecification(name: "", version: "")
        }

        let components = specification.components(separatedBy: "@")

        guard components.count >= 2 else {
            // No @ found, treat entire string as package name
            return PackageSpecification(name: specification, version: nil)
        }

        let packageName = String(components[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        // Join all components after the first @ (handles multiple @ signs)
        let versionSpec = components.dropFirst().joined(separator: "@").trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate package name is not empty
        guard !packageName.isEmpty else {
            return PackageSpecification(name: specification, version: nil)
        }

        // If version is empty, treat as no version specified
        let finalVersion = versionSpec.isEmpty ? nil : versionSpec

        return PackageSpecification(name: packageName, version: finalVersion)
    }

    /// Validate that the package specification is well-formed
    var isValid: Bool {
        // Package name must not be empty and contain only valid characters
        guard !name.isEmpty else { return false }

        // Package names should only contain alphanumeric, hyphens, underscores, and dots
        let validNamePattern = #"^[a-zA-Z0-9._-]+$"#
        guard name.range(of: validNamePattern, options: .regularExpression) != nil else {
            return false
        }

        // If version is specified, it should not be empty
        if let version = version {
            return !version.isEmpty
        }

        return true
    }

    /// The full specification string (name@version or just name)
    var fullSpecification: String {
        if let version = version, !version.isEmpty {
            return "\(name)@\(version)"
        } else {
            return name
        }
    }
}
