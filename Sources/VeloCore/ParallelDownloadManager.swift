import Foundation
import VeloFormula
import VeloSystem

// MARK: - Download Result

public struct DownloadResult {
    public let packageName: String
    public let formula: Formula
    public let downloadPath: URL
    public let success: Bool
    public let error: Error?
    
    public init(packageName: String, formula: Formula, downloadPath: URL, success: Bool = true, error: Error? = nil) {
        self.packageName = packageName
        self.formula = formula
        self.downloadPath = downloadPath
        self.success = success
        self.error = error
    }
}

// MARK: - Parallel Download Progress

public protocol ParallelDownloadProgress {
    func downloadDidStart(totalPackages: Int, totalSize: Int64?)
    func packageDownloadDidStart(package: String, size: Int64?)
    func packageDownloadDidUpdate(package: String, bytesDownloaded: Int64, totalBytes: Int64?)
    func packageDownloadDidComplete(package: String, success: Bool, error: Error?)
    func allDownloadsDidComplete(successful: Int, failed: Int)
}

// MARK: - Parallel Download Manager

public class ParallelDownloadManager {
    private let downloader: BottleDownloader
    private let pathHelper: PathHelper
    private let maxConcurrentDownloads: Int
    
    public init(pathHelper: PathHelper = PathHelper.shared, maxConcurrentDownloads: Int = 4) {
        self.downloader = BottleDownloader()
        self.pathHelper = pathHelper
        self.maxConcurrentDownloads = maxConcurrentDownloads
    }
    
    // MARK: - Public Interface
    
    /// Download bottles for multiple packages in parallel
    public func downloadAll(
        packages: [DependencyNode],
        progress: ParallelDownloadProgress? = nil
    ) async throws -> [String: DownloadResult] {
        
        guard !packages.isEmpty else {
            return [:]
        }
        
        OSLogger.shared.info("⬇️  Downloading \(packages.count) packages in parallel")
        
        let totalSize = estimateTotalSize(packages: packages)
        progress?.downloadDidStart(totalPackages: packages.count, totalSize: totalSize)
        
        // Group packages into batches to limit concurrent downloads
        let batches = packages.chunked(into: maxConcurrentDownloads)
        var allResults: [DownloadResult] = []
        
        for batch in batches {
            // Process each batch in parallel and collect results
            let batchResults = await withTaskGroup(of: DownloadResult.self) { group in
                for package in batch {
                    group.addTask {
                        await self.downloadSinglePackage(package: package, progress: progress)
                    }
                }
                
                var results: [DownloadResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }
            allResults.append(contentsOf: batchResults)
        }
        
        // Convert to dictionary
        var results: [String: DownloadResult] = [:]
        for result in allResults {
            results[result.packageName] = result
        }
        
        let successful = results.values.filter { $0.success }.count
        let failed = results.values.filter { !$0.success }.count
        
        progress?.allDownloadsDidComplete(successful: successful, failed: failed)
        
        // Check for failures
        let failures = results.values.filter { !$0.success }
        if !failures.isEmpty {
            let failedNames = failures.compactMap { $0.error?.localizedDescription }.joined(separator: ", ")
            throw VeloError.installationFailed(
                package: "parallel_download",
                reason: "Failed to download \(failures.count) packages: \(failedNames)"
            )
        }
        
        OSLogger.shared.info("⬇️  Successfully downloaded \(successful) packages")
        return results
    }
    
    // MARK: - Private Methods
    
    private func downloadSinglePackage(
        package: DependencyNode,
        progress: ParallelDownloadProgress?
    ) async -> DownloadResult {
        
        do {
            // Get preferred bottle with enhanced fallback logic
            guard let bottle = package.formula.preferredBottle else {
                let availablePlatforms = package.formula.bottles.map { $0.platform.rawValue }.joined(separator: ", ")
                
                var reason = "No compatible bottle found"
                if !package.formula.bottles.isEmpty {
                    reason += ". Available: \(availablePlatforms)"
                    
                    #if arch(arm64)
                    if package.formula.hasRosettaCompatibleBottle {
                        reason += " (x86_64 available via Rosetta)"
                    }
                    #endif
                } else {
                    reason += ". No bottles available"
                }
                
                throw VeloError.installationFailed(package: package.name, reason: reason)
            }
            
            guard let bottleURL = package.formula.bottleURL(for: bottle) else {
                throw VeloError.installationFailed(
                    package: package.name,
                    reason: "Could not generate bottle URL"
                )
            }
            
            // Create temporary file for download
            let tempFile = pathHelper.temporaryFile(
                prefix: "bottle-\(package.name)",
                extension: "tar.gz"
            )
            
            let estimatedSize = estimateBottleSize(package: package)
            progress?.packageDownloadDidStart(package: package.name, size: estimatedSize)
            
            // Create progress wrapper for individual package
            let packageProgress = PackageDownloadProgress(
                packageName: package.name,
                progress: progress
            )
            
            // Download the bottle
            try await downloader.download(
                from: bottleURL,
                to: tempFile,
                expectedSHA256: bottle.sha256,
                progress: packageProgress
            )
            
            progress?.packageDownloadDidComplete(package: package.name, success: true, error: nil)
            
            return DownloadResult(
                packageName: package.name,
                formula: package.formula,
                downloadPath: tempFile
            )
            
        } catch {
            progress?.packageDownloadDidComplete(package: package.name, success: false, error: error)
            
            return DownloadResult(
                packageName: package.name,
                formula: package.formula,
                downloadPath: URL(fileURLWithPath: "/dev/null"), // Placeholder
                success: false,
                error: error
            )
        }
    }
    
    private func estimateTotalSize(packages: [DependencyNode]) -> Int64 {
        // Rough estimate: 5MB per package
        return Int64(packages.count) * 5_000_000
    }
    
    private func estimateBottleSize(package: DependencyNode) -> Int64 {
        // More sophisticated estimation could be added later
        return 5_000_000  // 5MB estimate
    }
}

// MARK: - Package Download Progress Wrapper

private class PackageDownloadProgress: DownloadProgress {
    private let packageName: String
    private let progress: ParallelDownloadProgress?
    
    init(packageName: String, progress: ParallelDownloadProgress?) {
        self.packageName = packageName
        self.progress = progress
    }
    
    func downloadDidStart(url: String, totalSize: Int64?) {
        // Individual package start is handled by ParallelDownloadManager
    }
    
    func downloadDidUpdate(bytesDownloaded: Int64, totalBytes: Int64?) {
        progress?.packageDownloadDidUpdate(
            package: packageName,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes
        )
    }
    
    func downloadDidComplete(url: String) {
        // Completion is handled by ParallelDownloadManager
    }
    
    func downloadDidFail(url: String, error: Error) {
        // Failure is handled by ParallelDownloadManager
    }
}

// Note: Array.chunked extension is already defined in FormulaCache.swift