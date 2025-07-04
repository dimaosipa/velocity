import Foundation
import VeloSystem

/// Configuration for self-update operations
public struct SelfUpdateConfig {
    public let owner: String
    public let repo: String
    public let includePrerelease: Bool
    public let skipBackup: Bool
    public let force: Bool

    public init(
        owner: String = "dimaosipa",  // Default GitHub owner
        repo: String = "velocity",    // Default repository name
        includePrerelease: Bool = false,
        skipBackup: Bool = false,
        force: Bool = false
    ) {
        self.owner = owner
        self.repo = repo
        self.includePrerelease = includePrerelease
        self.skipBackup = skipBackup
        self.force = force
    }
}

/// Result of an update check
public enum UpdateCheckResult {
    case upToDate(current: SemanticVersion)
    case updateAvailable(current: SemanticVersion, latest: GitHubRelease)
    case prereleaseAvailable(current: SemanticVersion, latest: GitHubRelease)
}

/// Manages the self-update process for Velo
public class SelfUpdater {
    private let releaseManager: GitHubReleaseManager
    private let pathHelper: PathHelper
    private let fileManager: FileManager

    public init(
        releaseManager: GitHubReleaseManager = GitHubReleaseManager(),
        pathHelper: PathHelper = PathHelper.shared,
        fileManager: FileManager = .default
    ) {
        self.releaseManager = releaseManager
        self.pathHelper = pathHelper
        self.fileManager = fileManager
    }

    /// Check for available updates
    public func checkForUpdates(config: SelfUpdateConfig) async throws -> UpdateCheckResult {
        let currentVersion = getCurrentVersion()

        let latestRelease = try await releaseManager.fetchLatestRelease(
            owner: config.owner,
            repo: config.repo,
            includePrerelease: config.includePrerelease
        )

        guard let latestVersion = latestRelease.version else {
            throw VeloError.updateCheckFailed(reason: "Invalid version format in release: \(latestRelease.tagName)")
        }

        if latestRelease.prerelease && !config.includePrerelease {
            // Latest is prerelease but we don't want prereleases
            return .upToDate(current: currentVersion)
        }

        if latestVersion.isNewerThan(currentVersion) || config.force {
            if latestRelease.prerelease {
                return .prereleaseAvailable(current: currentVersion, latest: latestRelease)
            } else {
                return .updateAvailable(current: currentVersion, latest: latestRelease)
            }
        } else {
            return .upToDate(current: currentVersion)
        }
    }

    /// Perform the self-update process
    public func performUpdate(
        to release: GitHubRelease,
        config: SelfUpdateConfig,
        progress: ((String) -> Void)? = nil
    ) async throws {
        progress?("Starting self-update process...")

        // Get current binary path
        guard let currentBinaryPath = getCurrentBinaryPath() else {
            throw VeloError.updateCheckFailed(reason: "Could not determine current binary location")
        }

        // Get target installation path
        let targetPath = pathHelper.binPath.appendingPathComponent("velo")

        // Check if current installation is a symlink
        let isCurrentlySymlinked = try isSymlink(currentBinaryPath)

        if isCurrentlySymlinked {
            progress?("Detected symlinked installation - updating in development mode")
            throw VeloError.updateCheckFailed(reason: "Cannot update symlinked installation. Please rebuild from source.")
        }

        // Find compatible asset
        guard let asset = release.compatibleAsset else {
            throw VeloError.updateCheckFailed(reason: "No compatible binary found for this platform")
        }

        progress?("Found compatible asset: \(asset.name)")

        // Create backup if requested
        var backupPath: URL?
        if !config.skipBackup {
            backupPath = try createBackup(of: targetPath)
            progress?("Created backup at: \(backupPath!.path)")
        }

        do {
            // Download new binary
            let tempPath = pathHelper.temporaryFile(prefix: "velo-update", extension: "")
            progress?("Downloading \(asset.name)...")

            try await releaseManager.downloadAsset(asset, to: tempPath) { [self] downloaded, total in
                if total > 0 {
                    let percentage = Int((Double(downloaded) / Double(total)) * 100)
                    progress?("Downloaded \(percentage)% (\(self.formatBytes(downloaded))/\(self.formatBytes(total)))")
                }
            }

            progress?("Download complete, installing...")

            // Replace the binary
            if fileManager.fileExists(atPath: targetPath.path) {
                try fileManager.removeItem(at: targetPath)
            }

            try fileManager.moveItem(at: tempPath, to: targetPath)

            // Ensure it's executable
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try fileManager.setAttributes(attributes, ofItemAtPath: targetPath.path)

            progress?("Update completed successfully!")

            // Clean up backup after successful update
            if let backup = backupPath, !config.skipBackup {
                try? fileManager.removeItem(at: backup)
            }

        } catch {
            // Restore backup if update failed
            if let backup = backupPath {
                progress?("Update failed, restoring backup...")
                try? restoreBackup(from: backup, to: targetPath)
            }

            throw VeloError.updateCheckFailed(reason: "Update failed: \(error.localizedDescription)")
        }
    }

    /// Get information about the current installation
    public func getCurrentInstallationInfo() -> (path: URL?, version: SemanticVersion, isSymlinked: Bool) {
        let currentPath = getCurrentBinaryPath()
        let version = getCurrentVersion()
        let isSymlinked = currentPath.map { (try? isSymlink($0)) ?? false } ?? false

        return (currentPath, version, isSymlinked)
    }

    // MARK: - Private Helper Methods

    private func getCurrentVersion() -> SemanticVersion {
        return VeloVersion.current
    }

    private func getCurrentBinaryPath() -> URL? {
        let currentPath = CommandLine.arguments[0]

        // If it's a relative path, make it absolute
        if currentPath.hasPrefix("./") || !currentPath.hasPrefix("/") {
            let currentDir = fileManager.currentDirectoryPath
            let fullPath = URL(fileURLWithPath: currentDir).appendingPathComponent(currentPath)
            return fullPath.standardized
        }

        return URL(fileURLWithPath: currentPath)
    }

    private func isSymlink(_ url: URL) throws -> Bool {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let fileType = attributes[.type] as? FileAttributeType
        return fileType == .typeSymbolicLink
    }

    private func createBackup(of binaryPath: URL) throws -> URL {
        let backupPath = binaryPath.appendingPathExtension("backup.\(Int(Date().timeIntervalSince1970))")
        try fileManager.copyItem(at: binaryPath, to: backupPath)
        return backupPath
    }

    private func restoreBackup(from backupPath: URL, to targetPath: URL) throws {
        if fileManager.fileExists(atPath: targetPath.path) {
            try fileManager.removeItem(at: targetPath)
        }
        try fileManager.moveItem(at: backupPath, to: targetPath)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}
