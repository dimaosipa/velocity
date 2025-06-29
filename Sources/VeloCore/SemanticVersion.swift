import Foundation

/// Represents a semantic version (e.g., 1.2.3, 2.0.0-beta.1)
public struct SemanticVersion: Codable, Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let build: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil, build: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
    }

    /// Parse a semantic version string (e.g., "v1.2.3", "1.2.3-beta.1+build.123")
    public init?(string: String) {
        let cleanString = string.hasPrefix("v") ? String(string.dropFirst()) : string

        // Split by + to separate build metadata
        let parts = cleanString.components(separatedBy: "+")
        let versionPart = parts[0]
        let buildPart = parts.count > 1 ? parts[1] : nil

        // Split by - to separate prerelease
        let versionComponents = versionPart.components(separatedBy: "-")
        let corePart = versionComponents[0]
        let prereleasePart = versionComponents.count > 1 ? versionComponents[1...].joined(separator: "-") : nil

        // Parse major.minor.patch
        let coreComponents = corePart.components(separatedBy: ".")
        guard coreComponents.count >= 3,
              let major = Int(coreComponents[0]),
              let minor = Int(coreComponents[1]),
              let patch = Int(coreComponents[2]) else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prereleasePart
        self.build = buildPart
    }

    /// String representation of the version
    public var description: String {
        var result = "\(major).\(minor).\(patch)"

        if let prerelease = prerelease {
            result += "-\(prerelease)"
        }

        if let build = build {
            result += "+\(build)"
        }

        return result
    }

    /// Whether this is a prerelease version
    public var isPrerelease: Bool {
        return prerelease != nil
    }

    /// Compare versions according to semantic versioning rules
    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        // Compare major, minor, patch
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        // Prerelease handling:
        // 1.0.0-alpha < 1.0.0
        // 1.0.0-alpha < 1.0.0-beta
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false // Equal core versions
        case (nil, _):
            return false // Release > prerelease
        case (_, nil):
            return true // Prerelease < release
        case (let lhsPre?, let rhsPre?):
            return lhsPre < rhsPre // Compare prerelease strings lexically
        }
    }
}

/// Version comparison utilities
public extension SemanticVersion {
    /// Check if this version is newer than another
    func isNewerThan(_ other: SemanticVersion) -> Bool {
        return self > other
    }

    /// Check if this version is compatible with another (same major version)
    func isCompatibleWith(_ other: SemanticVersion) -> Bool {
        return self.major == other.major
    }

    /// Check if this is a major version update
    func isMajorUpdateFrom(_ other: SemanticVersion) -> Bool {
        return self.major > other.major
    }

    /// Check if this is a minor version update
    func isMinorUpdateFrom(_ other: SemanticVersion) -> Bool {
        return self.major == other.major && self.minor > other.minor
    }

    /// Check if this is a patch version update
    func isPatchUpdateFrom(_ other: SemanticVersion) -> Bool {
        return self.major == other.major &&
               self.minor == other.minor &&
               self.patch > other.patch
    }
}
