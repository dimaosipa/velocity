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
        
        @Flag(help: "Skip dependency installation (internal use)")
        var skipDependencies = false
        
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
            try await installPackage(name: package, skipDeps: skipDependencies, verbose: true)
        }
        
        private func installPackage(name: String, skipDeps: Bool, verbose: Bool) async throws {
            let downloader = BottleDownloader()
            let installer = Installer()
            let tapManager = TapManager()
            let progressHandler = CLIProgress()
            
            if verbose {
                logInfo("Installing \(name)...")
            }
            
            // Ensure we have the homebrew/core tap
            try await tapManager.updateTaps()
            
            // Parse formula
            guard let formula = try tapManager.findFormula(name) else {
                throw VeloError.formulaNotFound(name: name)
            }
            
            // Check if already installed
            if !force {
                let status = try installer.verifyInstallation(formula: formula)
                if status.isInstalled {
                    if verbose {
                        logInfo("\(formula.name) \(formula.version) is already installed")
                    }
                    return
                }
            }
            
            // Install dependencies first (runtime dependencies only)
            if !skipDeps {
                try await installDependencies(for: formula)
            }
            
            // Check for compatible bottle
            guard let bottle = formula.preferredBottle else {
                throw VeloError.installationFailed(
                    package: name,
                    reason: "No compatible bottle found for Apple Silicon"
                )
            }
            
            guard let bottleURL = formula.bottleURL(for: bottle) else {
                throw VeloError.installationFailed(
                    package: name,
                    reason: "Could not generate bottle URL"
                )
            }
            
            // Download bottle
            let tempFile = PathHelper.shared.temporaryFile(prefix: "bottle-\(name)", extension: "tar.gz")
            
            // Retry download with exponential backoff for transient issues
            let maxRetries = 2
            
            for attempt in 0..<maxRetries {
                do {
                    if attempt > 0 {
                        logInfo("Retrying download (attempt \(attempt + 1)/\(maxRetries))...")
                        // Exponential backoff: 1s, 2s
                        try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                    }
                    
                    try await downloader.download(
                        from: bottleURL,
                        to: tempFile,
                        expectedSHA256: bottle.sha256,
                        progress: progressHandler
                    )
                    
                    break // Success, exit retry loop
                    
                } catch VeloError.bottleNotAccessible(let url, let reason) {
                    // Don't retry for access denied errors
                    logWarning("Bottle not accessible for \(name): \(reason)")
                    logWarning("Skipping \(name) installation due to bottle access restrictions.")
                    logInfo("This may be due to GHCR access limitations or rate limiting.")
                    logInfo("You can try installing \(name) again later or use an alternative installation method.")
                    
                    throw VeloError.bottleNotAccessible(url: url, reason: reason)
                    
                } catch {
                    logWarning("Download failed (attempt \(attempt + 1)/\(maxRetries)): \(error.localizedDescription)")
                    
                    if attempt == maxRetries - 1 {
                        // Last attempt failed, throw the error
                        throw error
                    }
                }
            }
            
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
            if verbose && !PathHelper.shared.isInPath() {
                logWarning("Add ~/.velo/bin to your PATH to use installed packages:")
                print("  echo 'export PATH=\"$HOME/.velo/bin:$PATH\"' >> ~/.zshrc")
            }
        }
        
        // MARK: - Dependency Resolution
        
        private func installDependencies(for formula: Formula) async throws {
            let runtimeDependencies = formula.dependencies.filter { $0.type == .required }
            
            if runtimeDependencies.isEmpty {
                return
            }
            
            logInfo("Checking \(runtimeDependencies.count) runtime dependencies...")
            
            var failedDependencies: [String] = []
            
            for dependency in runtimeDependencies {
                let pathHelper = PathHelper.shared
                
                // Skip if already installed
                if pathHelper.isPackageInstalled(dependency.name) {
                    logInfo("✓ \(dependency.name) (already installed)")
                    continue
                }
                
                logInfo("Installing dependency: \(dependency.name)...")
                
                // Create a new install instance for the dependency
                do {
                    try await installPackage(
                        name: dependency.name,
                        skipDeps: true,
                        verbose: false
                    )
                    logInfo("✓ \(dependency.name) installed successfully")
                } catch VeloError.bottleNotAccessible(_, let reason) {
                    logError("Critical dependency \(dependency.name) failed to install: \(reason)")
                    failedDependencies.append(dependency.name)
                } catch {
                    logError("Critical dependency \(dependency.name) failed to install: \(error.localizedDescription)")
                    failedDependencies.append(dependency.name)
                }
            }
            
            // If any required dependencies failed, abort the installation
            if !failedDependencies.isEmpty {
                logError("Installation aborted due to missing critical dependencies:")
                for dep in failedDependencies {
                    logError("  • \(dep)")
                }
                logError("")
                logError("\(formula.name) requires these dependencies to function properly.")
                logError("Installation aborted to prevent installing a broken package.")
                
                throw VeloError.installationFailed(
                    package: formula.name,
                    reason: "Missing critical dependencies: \(failedDependencies.joined(separator: ", "))"
                )
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