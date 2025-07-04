import Foundation

/// Centralized version management for Velo
/// Provides dynamic version detection based on Git tags and commits
public struct VeloVersion {

    /// The current version of Velo
    public static let current: SemanticVersion = {
        return detectVersion()
    }()

    /// The current version as a string
    public static let currentString: String = {
        return current.description
    }()

    /// Detect the current version based on Git information
    private static func detectVersion() -> SemanticVersion {
        // Try to get version from Git
        if let gitVersion = getVersionFromGit() {
            return gitVersion
        }

        // If Git failed, create a development version manually
        let commitHash = getGitCommitHash() ?? "unknown"
        let isClean = isGitWorkingDirectoryClean()

        let baseVersion = SemanticVersion(major: 0, minor: 0, patch: 1)
        let devSuffix = createDevSuffix(commitHash: commitHash, isClean: isClean)

        return createDevVersion(base: baseVersion, suffix: devSuffix)
    }

    /// Get version from Git tags and commit information
    private static func getVersionFromGit() -> SemanticVersion? {
        let commitHash = getGitCommitHash()
        let isClean = isGitWorkingDirectoryClean()

        // If we're exactly on a tag, return the tag version
        if isOnExactTag() {
            let lastTag = getLastGitTag()
            return parseVersionFromTag(lastTag)
        }

        // Try to get the last tag
        let lastTag = getLastGitTag()

        // If we have a tag, create development version from it
        if let baseVersion = parseVersionFromTag(lastTag) {
            let devSuffix = createDevSuffix(commitHash: commitHash, isClean: isClean)
            return createDevVersion(base: baseVersion, suffix: devSuffix)
        }

        // If no tags exist, return nil to fall back to manual version
        return nil
    }

    /// Get the last Git tag
    private static func getLastGitTag() -> String? {
        return runGitCommand(["describe", "--tags", "--abbrev=0"])
    }

    /// Get the current Git commit hash (short)
    private static func getGitCommitHash() -> String? {
        return runGitCommand(["rev-parse", "--short", "HEAD"])
    }

    /// Check if we're exactly on a Git tag
    private static func isOnExactTag() -> Bool {
        guard let exactRef = runGitCommand(["describe", "--exact-match", "--tags", "HEAD"]) else {
            return false
        }
        return !exactRef.isEmpty
    }

    /// Check if the Git working directory is clean
    private static func isGitWorkingDirectoryClean() -> Bool {
        guard let status = runGitCommand(["status", "--porcelain"]) else {
            return false
        }
        return status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Parse version from Git tag
    private static func parseVersionFromTag(_ tag: String?) -> SemanticVersion? {
        guard let tag = tag else { return nil }

        // Remove 'v' prefix if present
        let cleanTag = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag

        return SemanticVersion(string: cleanTag)
    }

    /// Create development version suffix
    private static func createDevSuffix(commitHash: String?, isClean: Bool) -> String {
        var suffix = "dev"

        if let hash = commitHash {
            suffix += "+\(hash)"
            if !isClean {
                suffix += "-dirty"
            }
        }

        return suffix
    }

    /// Create a development version with prerelease suffix
    private static func createDevVersion(base: SemanticVersion, suffix: String) -> SemanticVersion {
        return SemanticVersion(
            major: base.major,
            minor: base.minor,
            patch: base.patch,
            prerelease: suffix
        )
    }

    /// Run a Git command and return its output
    private static func runGitCommand(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress error output

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }
}

// MARK: - SemanticVersion Extension for Prerelease Support

extension SemanticVersion {
    /// Create a SemanticVersion with prerelease information
    public init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        if let prerelease = prerelease {
            self = SemanticVersion(string: "\(major).\(minor).\(patch)-\(prerelease)") ??
                   SemanticVersion(major: major, minor: minor, patch: patch)
        } else {
            self.init(major: major, minor: minor, patch: patch)
        }
    }
}
