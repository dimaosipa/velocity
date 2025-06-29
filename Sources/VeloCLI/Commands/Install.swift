import Foundation
import ArgumentParser
import VeloCore
import VeloFormula
import VeloSystem

extension Velo {
    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install a package"
        )
        
        @Argument(help: "The package to install")
        var package: String
        
        @Flag(help: "Force reinstall even if already installed")
        var force = false
        
        @Flag(help: "Install build dependencies")
        var includeBuildDeps = false
        
        @Option(help: "Install specific version")
        var version: String?
        
        func run() throws {
            // Use a simple blocking approach for async operations
            let semaphore = DispatchSemaphore(value: 0)
            var thrownError: Error?
            
            Task {
                do {
                    try await self.runAsync()
                } catch {
                    thrownError = error
                }
                semaphore.signal()
            }
            
            semaphore.wait()
            
            if let error = thrownError {
                throw error
            }
        }
        
        private func runAsync() async throws {
            let downloader = BottleDownloader()
            let installer = Installer()
            let tapManager = TapManager()
            let progressHandler = CLIProgress()
            
            logInfo("Installing \(package)...")
            
            // Ensure we have the homebrew/core tap
            try await tapManager.updateTaps()
            
            // Parse formula
            guard let formula = try tapManager.findFormula(package) else {
                throw VeloError.formulaNotFound(name: package)
            }
            
            // Check if already installed
            if !force {
                let status = try installer.verifyInstallation(formula: formula)
                if status.isInstalled {
                    logInfo("\(formula.name) \(formula.version) is already installed")
                    return
                }
            }
            
            // Check for compatible bottle
            guard let bottle = formula.preferredBottle else {
                throw VeloError.installationFailed(
                    package: package,
                    reason: "No compatible bottle found for Apple Silicon"
                )
            }
            
            guard let bottleURL = formula.bottleURL(for: bottle) else {
                throw VeloError.installationFailed(
                    package: package,
                    reason: "Could not generate bottle URL"
                )
            }
            
            // Download bottle
            let tempFile = PathHelper.shared.temporaryFile(prefix: "bottle-\(package)", extension: "tar.gz")
            
            try await downloader.download(
                from: bottleURL,
                to: tempFile,
                expectedSHA256: bottle.sha256,
                progress: progressHandler
            )
            
            // Install
            try await installer.install(
                formula: formula,
                from: tempFile,
                progress: progressHandler
            )
            
            // Clean up
            try? FileManager.default.removeItem(at: tempFile)
            
            Logger.shared.success("\(formula.name) \(formula.version) installed successfully!")
            
            // Show next steps
            if !PathHelper.shared.isInPath() {
                logWarning("Add ~/.velo/bin to your PATH to use installed packages:")
                print("  echo 'export PATH=\"$HOME/.velo/bin:$PATH\"' >> ~/.zshrc")
            }
        }
        
    }

// MARK: - Progress Handler

private class CLIProgress: DownloadProgress, InstallationProgress {
    private var lastProgressUpdate = Date()
    private let updateInterval: TimeInterval = 0.1 // 100ms
    
    // MARK: - DownloadProgress
    
    func downloadDidStart(url: String, totalSize: Int64?) {
        if let size = totalSize {
            logInfo("Downloading \(formatBytes(size))...")
        } else {
            logInfo("Downloading...")
        }
    }
    
    func downloadDidUpdate(bytesDownloaded: Int64, totalBytes: Int64?) {
        let now = Date()
        guard now.timeIntervalSince(lastProgressUpdate) >= updateInterval else { return }
        lastProgressUpdate = now
        
        if let total = totalBytes {
            let percentage = Int((Double(bytesDownloaded) / Double(total)) * 100)
            Logger.shared.progress("Downloading: \(percentage)% (\(formatBytes(bytesDownloaded))/\(formatBytes(total)))")
        } else {
            Logger.shared.progress("Downloaded: \(formatBytes(bytesDownloaded))")
        }
    }
    
    func downloadDidComplete(url: String) {
        print("\n")
        logInfo("Download complete")
    }
    
    func downloadDidFail(url: String, error: Error) {
        print("\n")
        logError("Download failed: \(error.localizedDescription)")
    }
    
    // MARK: - InstallationProgress
    
    func installationDidStart(package: String, version: String) {
        logInfo("Installing \(package) \(version)...")
    }
    
    func extractionDidStart(totalFiles: Int?) {
        logInfo("Extracting package...")
    }
    
    func extractionDidUpdate(filesExtracted: Int, totalFiles: Int?) {
        // Don't spam with extraction updates
    }
    
    func linkingDidStart(binariesCount: Int) {
        if binariesCount > 0 {
            logInfo("Creating \(binariesCount) symlink(s)...")
        }
    }
    
    func linkingDidUpdate(binariesLinked: Int, totalBinaries: Int) {
        // Progress for linking is usually fast enough to not need updates
    }
    
    func installationDidComplete(package: String) {
        // Handled by the main command
    }
    
    func installationDidFail(package: String, error: Error) {
        logError("Installation of \(package) failed: \(error.localizedDescription)")
    }
    
    // MARK: - Helpers
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}
}