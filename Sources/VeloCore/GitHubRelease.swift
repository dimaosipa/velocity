import Foundation
import VeloSystem

/// Represents a GitHub release asset (downloadable file)
public struct GitHubReleaseAsset: Codable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int
    public let contentType: String

    enum CodingKeys: String, CodingKey {
        case name, size
        case browserDownloadUrl = "browser_download_url"
        case contentType = "content_type"
    }

    /// Check if this asset is suitable for the current platform
    public var isCompatibleWithCurrentPlatform: Bool {
        let name = self.name.lowercased()

        // Look for macOS ARM64 indicators
        let hasArm64 = name.contains("arm64") || name.contains("aarch64")
        let hasMacOS = name.contains("macos") || name.contains("darwin")

        // Prefer ARM64 builds, but fall back to universal macOS builds
        return (hasArm64 && hasMacOS) || (hasMacOS && !name.contains("x86") && !name.contains("amd64"))
    }
}

/// Represents a GitHub release
public struct GitHubRelease: Codable {
    public let tagName: String
    public let name: String
    public let publishedAt: String
    public let prerelease: Bool
    public let draft: Bool
    public let assets: [GitHubReleaseAsset]
    public let body: String?

    enum CodingKeys: String, CodingKey {
        case name, prerelease, draft, assets, body
        case tagName = "tag_name"
        case publishedAt = "published_at"
    }

    /// Parse the semantic version from the tag name
    public var version: SemanticVersion? {
        return SemanticVersion(string: tagName)
    }

    /// Find the best asset for the current platform
    public var compatibleAsset: GitHubReleaseAsset? {
        return assets.first { $0.isCompatibleWithCurrentPlatform }
    }

    /// Check if this release is newer than a given version
    public func isNewerThan(_ currentVersion: SemanticVersion) -> Bool {
        guard let releaseVersion = version else { return false }
        return releaseVersion.isNewerThan(currentVersion)
    }
}

/// Manages fetching release information from GitHub
public class GitHubReleaseManager {
    private let session: URLSession
    private let baseURL = "https://api.github.com"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetch the latest release for a repository
    public func fetchLatestRelease(
        owner: String,
        repo: String,
        includePrerelease: Bool = false
    ) async throws -> GitHubRelease {
        if includePrerelease {
            // Fetch all releases and find the latest (including prereleases)
            let releases = try await fetchReleases(owner: owner, repo: repo, limit: 10)
            guard let latest = releases.first(where: { !$0.draft }) else {
                throw VeloError.updateCheckFailed(reason: "No releases found")
            }
            return latest
        } else {
            // Fetch only the latest stable release
            return try await fetchStableLatestRelease(owner: owner, repo: repo)
        }
    }

    private func fetchStableLatestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        let urlString = "\(baseURL)/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw VeloError.updateCheckFailed(reason: "Invalid repository URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("velo/\(getCurrentVersion())", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw VeloError.updateCheckFailed(reason: "Invalid response from GitHub")
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 404:
                throw VeloError.updateCheckFailed(reason: "Repository not found or no releases available")
            case 403:
                throw VeloError.updateCheckFailed(reason: "GitHub API rate limit exceeded")
            default:
                throw VeloError.updateCheckFailed(reason: "GitHub API returned status \(httpResponse.statusCode)")
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            return release

        } catch let error as DecodingError {
            throw VeloError.updateCheckFailed(reason: "Failed to parse GitHub response: \(error.localizedDescription)")
        } catch {
            throw VeloError.updateCheckFailed(reason: "Network error: \(error.localizedDescription)")
        }
    }

    private func fetchReleases(owner: String, repo: String, limit: Int = 10) async throws -> [GitHubRelease] {
        let urlString = "\(baseURL)/repos/\(owner)/\(repo)/releases?per_page=\(limit)"
        guard let url = URL(string: urlString) else {
            throw VeloError.updateCheckFailed(reason: "Invalid repository URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("velo/\(getCurrentVersion())", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw VeloError.updateCheckFailed(reason: "Invalid response from GitHub")
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 404:
                throw VeloError.updateCheckFailed(reason: "Repository not found")
            case 403:
                throw VeloError.updateCheckFailed(reason: "GitHub API rate limit exceeded")
            default:
                throw VeloError.updateCheckFailed(reason: "GitHub API returned status \(httpResponse.statusCode)")
            }

            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            return releases

        } catch let error as DecodingError {
            throw VeloError.updateCheckFailed(reason: "Failed to parse GitHub response: \(error.localizedDescription)")
        } catch {
            throw VeloError.updateCheckFailed(reason: "Network error: \(error.localizedDescription)")
        }
    }

    /// Download a release asset to a temporary file
    public func downloadAsset(
        _ asset: GitHubReleaseAsset,
        to destinationURL: URL,
        progress: ((Int64, Int64) -> Void)? = nil
    ) async throws {
        guard let url = URL(string: asset.browserDownloadUrl) else {
            throw VeloError.updateCheckFailed(reason: "Invalid asset download URL")
        }

        var request = URLRequest(url: url)
        request.setValue("velo/\(getCurrentVersion())", forHTTPHeaderField: "User-Agent")

        do {
            let (tempURL, response) = try await session.download(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw VeloError.updateCheckFailed(reason: "Invalid response from GitHub")
            }

            guard httpResponse.statusCode == 200 else {
                throw VeloError.updateCheckFailed(reason: "Failed to download asset: HTTP \(httpResponse.statusCode)")
            }

            // Move from temporary location to destination
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            // Make executable if it's a binary
            if asset.name.contains("velo") || asset.contentType.contains("executable") {
                let attributes = [FileAttributeKey.posixPermissions: 0o755]
                try FileManager.default.setAttributes(attributes, ofItemAtPath: destinationURL.path)
            }

        } catch {
            throw VeloError.updateCheckFailed(reason: "Download failed: \(error.localizedDescription)")
        }
    }

    private func getCurrentVersion() -> String {
        // This should match the version in Velo.swift
        return "0.1.0"
    }
}
