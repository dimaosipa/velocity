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

        @Argument(help: "The package to install (optional if velo.json exists)")
        var package: String?

        @Flag(help: "Force reinstall even if already installed")
        var force = false

        @Flag(help: "Install build dependencies")
        var includeBuildDeps = false

        @Option(help: "Install specific version")
        var version: String?

        @Flag(help: "Skip dependency installation (internal use)")
        var skipDependencies = false

        @Flag(help: "Install globally instead of locally")
        var global = false

        @Flag(help: "Install exactly from velo.lock, fail if any deviation")
        var frozen = false

        @Flag(help: "Verify lock file before installing, warn about changes")
        var check = false

        @Flag(help: "Force tap update even if cache is fresh")
        var updateTaps = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let context = ProjectContext()

            // If no package specified, try to install from velo.json
            if package == nil {
                try await installFromManifest(context: context)
                return
            }

            guard let packageInput = package else {
                throw VeloError.formulaNotFound(name: "No package specified")
            }

            // Parse package specification (supports package@version syntax)
            // Handle versioned formula names (e.g., python@3.9)
            // First check if the full input exists as a formula name
            let tapManager = TapManager(pathHelper: PathHelper.shared)
            let resolvedName: String
            let resolvedVersion: String?
            
            if packageInput.contains("@"), let _ = try tapManager.findFormula(packageInput) {
                // Full name exists as a formula (e.g., python@3.9)
                resolvedName = packageInput
                resolvedVersion = version  // Use only --version flag if provided
            } else {
                // Parse as name@version specification
                let packageSpec = PackageSpecification.parse(packageInput)
                guard packageSpec.isValid else {
                    throw VeloError.formulaNotFound(name: "Invalid package specification: \(packageInput)")
                }
                resolvedName = packageSpec.name
                resolvedVersion = packageSpec.version ?? version  // inline @version takes precedence
            }

            // Determine if we should install locally or globally
            let useLocal = !global && context.isProjectContext

            // Get appropriate PathHelper
            let pathHelper = context.getPathHelper(preferLocal: useLocal)

            try await installPackage(
                name: resolvedName,
                version: resolvedVersion,
                context: context,
                pathHelper: pathHelper,
                skipDeps: skipDependencies,
                verbose: true,
                skipTapUpdate: false,
                forceTapUpdate: updateTaps
            )

            // Automatically add to velo.json if in project context and installing locally
            if useLocal && context.isProjectContext {
                try await addToManifest(
                    package: resolvedName,
                    version: resolvedVersion,
                    context: context
                )
            }
        }

        private func installFromManifest(context: ProjectContext) async throws {
            guard context.isProjectContext else {
                OSLogger.shared.error("No velo.json found. Run 'velo init' to create one or specify a package name.")
                throw ExitCode.failure
            }

            guard let manifestPath = context.manifestPath else {
                throw VeloError.notInProjectContext
            }

            OSLogger.shared.info("Installing packages from velo.json...")

            let manifestManager = VeloManifestManager()
            let manifest = try manifestManager.read(from: manifestPath)

            let pathHelper = context.getPathHelper(preferLocal: !global)

            // Handle --frozen and --check flags
            if frozen || check {
                try await handleLockFileFlags(context: context, pathHelper: pathHelper)
                if frozen {
                    return // --frozen installs exactly from lock file, so we're done
                }
            }

            // Ensure required taps are available
            let requiredTaps = manifestManager.getAllTaps(from: manifest)
            if !requiredTaps.isEmpty {
                try await ensureRequiredTaps(requiredTaps, pathHelper: pathHelper)
            }

            let allDeps = manifestManager.getAllDependencies(from: manifest)

            if allDeps.isEmpty {
                print("No dependencies found in velo.json")
                return
            }

            OSLogger.shared.info("Installing \(allDeps.count) packages...")

            var installedPackages: [(formula: Formula, bottleURL: String, tap: String, resolvedDependencies: [String: String])] = []

            for (packageName, versionSpec) in allDeps {
                let installResult = try await installPackageWithTracking(
                    name: packageName,
                    version: versionSpec == "*" ? nil : versionSpec,
                    context: context,
                    pathHelper: pathHelper,
                    skipDeps: false,
                    verbose: false,
                    skipTapUpdate: true, // Skip after first update
                    forceTapUpdate: false
                )

                if let result = installResult {
                    installedPackages.append(result)
                }
            }

            // Update lock file if in project context
            if let lockFilePath = context.lockFilePath {
                try updateLockFile(installedPackages: installedPackages, lockFilePath: lockFilePath)
            }

            OSLogger.shared.success("All packages installed successfully!")
        }

        private func installPackageWithTracking(
            name: String,
            version: String? = nil,
            context: ProjectContext,
            pathHelper: PathHelper,
            skipDeps: Bool,
            verbose: Bool,
            skipTapUpdate: Bool = false,
            forceTapUpdate: Bool = false
        ) async throws -> (formula: Formula, bottleURL: String, tap: String, resolvedDependencies: [String: String])? {
            let tapManager = TapManager(pathHelper: pathHelper)

            // Find formula and determine source tap
            guard let formula = try tapManager.findFormula(name) else {
                throw VeloError.formulaNotFound(name: name)
            }

            // Determine which tap this formula came from
            let sourceTap = try getSourceTap(for: name, pathHelper: pathHelper)

            // Install the package
            try await installPackage(
                name: name,
                version: version,
                context: context,
                pathHelper: pathHelper,
                skipDeps: skipDeps,
                verbose: verbose,
                skipTapUpdate: skipTapUpdate,
                forceTapUpdate: forceTapUpdate
            )

            // Get bottle URL
            guard let bottle = formula.preferredBottle,
                  let bottleURL = formula.bottleURL(for: bottle) else {
                throw VeloError.installationFailed(package: name, reason: "No compatible bottle found")
            }

            // Resolve exact dependency versions
            let resolvedDeps = try await resolveExactDependencyVersions(for: formula, pathHelper: pathHelper)

            return (formula: formula, bottleURL: bottleURL, tap: sourceTap, resolvedDependencies: resolvedDeps)
        }

        private func getSourceTap(for packageName: String, pathHelper: PathHelper) throws -> String {
            // For now, return "homebrew/core" as default
            // In a full implementation, we'd track which tap the formula was found in
            return "homebrew/core"
        }

        private func resolveExactDependencyVersions(for formula: Formula, pathHelper: PathHelper) async throws -> [String: String] {
            var resolvedDeps: [String: String] = [:]

            for dependency in formula.dependencies.filter({ $0.type == .required }) {
                let versions = pathHelper.installedVersions(for: dependency.name)
                if let latestVersion = versions.last {
                    resolvedDeps[dependency.name] = latestVersion
                }
            }

            return resolvedDeps
        }

        private func updateLockFile(
            installedPackages: [(formula: Formula, bottleURL: String, tap: String, resolvedDependencies: [String: String])],
            lockFilePath: URL
        ) throws {
            let lockFileManager = VeloLockFileManager()
            try lockFileManager.updateLockFile(at: lockFilePath, with: installedPackages)
            OSLogger.shared.info("Updated velo.lock with \(installedPackages.count) packages")
        }

        private func handleLockFileFlags(context: ProjectContext, pathHelper: PathHelper) async throws {
            guard let lockFilePath = context.lockFilePath else {
                OSLogger.shared.error("No velo.lock file found. Cannot use --frozen or --check flags.")
                throw ExitCode.failure
            }

            guard FileManager.default.fileExists(atPath: lockFilePath.path) else {
                OSLogger.shared.error("velo.lock file does not exist. Run 'velo install' first to create it.")
                throw ExitCode.failure
            }

            let lockFileManager = VeloLockFileManager()
            let lockFile = try lockFileManager.read(from: lockFilePath)

            if check {
                OSLogger.shared.info("Checking lock file integrity...")
                let installedPackages = try getInstalledPackagesForVerification(pathHelper: pathHelper)
                let mismatches = lockFileManager.verifyInstallations(lockFile: lockFile, installedPackages: installedPackages)

                if !mismatches.isEmpty {
                    OSLogger.shared.warning("Lock file mismatches detected:")
                    for mismatch in mismatches {
                        print("  • \(mismatch)")
                    }
                    print("")
                }
            }

            if frozen {
                OSLogger.shared.info("Installing exactly from velo.lock (frozen mode)...")
                try await installFromLockFile(lockFile: lockFile, pathHelper: pathHelper)
            }
        }

        private func getInstalledPackagesForVerification(pathHelper: PathHelper) throws -> [String: String] {
            var installedPackages: [String: String] = [:]

            let cellarPath = pathHelper.cellarPath
            guard FileManager.default.fileExists(atPath: cellarPath.path) else {
                return installedPackages
            }

            let packages = try FileManager.default.contentsOfDirectory(atPath: cellarPath.path)
                .filter { !$0.hasPrefix(".") }

            for package in packages {
                let versions = pathHelper.installedVersions(for: package)
                if let defaultVersion = pathHelper.getDefaultVersion(for: package) {
                    installedPackages[package] = defaultVersion
                } else if let latestVersion = versions.last {
                    installedPackages[package] = latestVersion
                }
            }

            return installedPackages
        }

        private func installFromLockFile(lockFile: VeloLockFile, pathHelper: PathHelper) async throws {
            for (packageName, lockEntry) in lockFile.dependencies {
                // Check if already installed with correct version
                let installedVersions = pathHelper.installedVersions(for: packageName)
                if installedVersions.contains(lockEntry.version) {
                    OSLogger.shared.info("✓ \(packageName) \(lockEntry.version) already installed")
                    continue
                }

                OSLogger.shared.info("Installing \(packageName) \(lockEntry.version) from lock file...")

                // For frozen installs, we need to install the exact version specified
                // This is a simplified implementation - in practice, we'd need to:
                // 1. Ensure the exact tap commit is available
                // 2. Download from the exact URL specified in lock file
                // 3. Verify SHA256 matches

                let tapManager = TapManager(pathHelper: pathHelper)
                guard let formula = try tapManager.findFormula(packageName) else {
                    throw VeloError.formulaNotFound(name: packageName)
                }

                // Verify version matches
                guard formula.version == lockEntry.version else {
                    throw VeloError.installationFailed(
                        package: packageName,
                        reason: "Available version \(formula.version) doesn't match locked version \(lockEntry.version)"
                    )
                }

                // Install using existing method
                try await installPackage(
                    name: packageName,
                    version: lockEntry.version,
                    context: ProjectContext(),
                    pathHelper: pathHelper,
                    skipDeps: false,
                    verbose: true,
                    skipTapUpdate: true,
                    forceTapUpdate: false
                )
            }

            OSLogger.shared.success("All packages installed from velo.lock successfully!")
        }

        private func ensureRequiredTaps(_ requiredTaps: [String], pathHelper: PathHelper) async throws {
            OSLogger.shared.info("Ensuring required taps are available...")

            let tapsPath = pathHelper.tapsPath
            var missingTaps: [String] = []

            // Check which taps are missing
            for tapName in requiredTaps {
                let tapPath = tapsPath.appendingPathComponent(tapName)
                if !FileManager.default.fileExists(atPath: tapPath.path) {
                    missingTaps.append(tapName)
                }
            }

            if missingTaps.isEmpty {
                OSLogger.shared.info("All required taps are available")
                return
            }

            OSLogger.shared.info("Adding missing taps: \(missingTaps.joined(separator: ", "))")

            // Add missing taps
            for tapName in missingTaps {
                do {
                    try await addTap(tapName, to: tapsPath)
                    OSLogger.shared.info("✓ Added tap \(tapName)")
                } catch {
                    OSLogger.shared.error("Failed to add required tap \(tapName): \(error)")
                    throw VeloError.installationFailed(
                        package: "velo.json dependencies",
                        reason: "Required tap '\(tapName)' could not be added: \(error.localizedDescription)"
                    )
                }
            }
        }

        private func addTap(_ tapName: String, to tapsPath: URL) async throws {
            let components = tapName.components(separatedBy: "/")
            guard components.count == 2 else {
                throw VeloError.invalidTapName(tapName)
            }

            let user = components[0]
            let repo = components[1]

            // Apply repository naming convention
            let actualRepo = repo.hasPrefix("homebrew-") ? repo : "homebrew-\(repo)"
            let url = "https://github.com/\(user)/\(actualRepo).git"
            let tapPath = tapsPath.appendingPathComponent(tapName)

            // Ensure parent directory exists
            try FileManager.default.createDirectory(
                at: tapPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Clone the tap
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = [
                "clone",
                "--depth", "1",
                url,
                tapPath.path
            ]

            try await runProcess(process, description: "Cloning tap \(tapName)")
        }

        private func runProcess(_ process: Process, description: String) async throws {
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let error = VeloError.processError(
                            command: process.executableURL?.lastPathComponent ?? "git",
                            exitCode: Int(process.terminationStatus),
                            description: "\(description) failed"
                        )
                        continuation.resume(throwing: error)
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: VeloError.processError(
                        command: "git",
                        exitCode: -1,
                        description: "Failed to start \(description): \(error.localizedDescription)"
                    ))
                }
            }
        }

        private func addToManifest(
            package: String,
            version: String?,
            context: ProjectContext
        ) async throws {
            guard let manifestPath = context.manifestPath else {
                return // Not in project context, skip
            }

            let manifestManager = VeloManifestManager()

            // Use the version we installed, or "*" if no specific version
            let versionToSave = version ?? "*"

            try manifestManager.addDependency(
                package,
                version: versionToSave,
                to: manifestPath
            )

            OSLogger.shared.info("Added \(package)@\(versionToSave) to dependencies")
        }

        private func installPackage(
            name: String,
            version: String? = nil,
            context: ProjectContext,
            pathHelper: PathHelper,
            skipDeps: Bool,
            verbose: Bool,
            skipTapUpdate: Bool = false,
            forceTapUpdate: Bool = false
        ) async throws {
            let downloader = BottleDownloader()
            let installer = Installer(pathHelper: pathHelper)
            let tapManager = TapManager(pathHelper: pathHelper)
            let progressHandler = CLIProgress()

            if verbose {
                OSLogger.shared.info("Installing \(name)...")
            }

            // Ensure we have the homebrew/core tap (skip for dependencies)
            if !skipTapUpdate {
                try await tapManager.updateTaps(force: forceTapUpdate)
            }

            // Parse formula
            guard let formula = try tapManager.findFormula(name) else {
                throw VeloError.formulaNotFound(name: name)
            }

            // Check if already installed (including equivalent packages)
            if !force {
                if pathHelper.isEquivalentPackageInstalled(name) {
                    if let installedEquivalent = pathHelper.findInstalledEquivalentPackage(for: name) {
                        if verbose {
                            if installedEquivalent == name {
                                OSLogger.shared.info("\(formula.name) \(formula.version) is already installed")
                            } else {
                                OSLogger.shared.info("Equivalent package \(installedEquivalent) is already installed for \(name)")
                            }
                        }
                        return
                    }
                }
                
                // Fallback to original verification
                let status = try installer.verifyInstallation(formula: formula)
                if status.isInstalled {
                    if verbose {
                        OSLogger.shared.info("\(formula.name) \(formula.version) is already installed")
                    }
                    return
                }
            }

            // Install dependencies using dependency graph approach
            if !skipDeps {
                try await installDependenciesWithGraph(
                    for: formula,
                    tapManager: tapManager,
                    pathHelper: pathHelper
                )
            }

            // Check for compatible bottle with enhanced fallback logic
            guard let bottle = formula.preferredBottle else {
                // Enhanced error handling for missing bottles
                let availablePlatforms = formula.bottles.map { $0.platform.rawValue }.joined(separator: ", ")
                let currentArch = Self.getCurrentArchitecture()
                
                var errorMessage = "No compatible bottle found for \(currentArch)"
                var suggestions: [String] = []
                
                if !formula.bottles.isEmpty {
                    errorMessage += ". Available platforms: \(availablePlatforms)"
                    
                    // Check for Rosetta compatibility
                    if formula.hasRosettaCompatibleBottle {
                        suggestions.append("x86_64 bottles are available but may require Rosetta 2")
                    }
                } else {
                    errorMessage += ". No bottles available for any platform"
                    suggestions.append("This package may need to be built from source")
                }
                
                // Add helpful suggestions
                if !suggestions.isEmpty {
                    errorMessage += ". Suggestions: " + suggestions.joined(separator: "; ")
                }
                
                OSLogger.shared.error(errorMessage)
                OSLogger.shared.info("You can:")
                OSLogger.shared.info("1. Try installing with 'arch -x86_64' if running on Apple Silicon")
                OSLogger.shared.info("2. Check if an alternative package exists")
                OSLogger.shared.info("3. Build from source (future feature)")
                
                throw VeloError.installationFailed(package: name, reason: errorMessage)
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
                        OSLogger.shared.info("Retrying download (attempt \(attempt + 1)/\(maxRetries))...")
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
                    OSLogger.shared.warning("Bottle not accessible for \(name): \(reason)")
                    OSLogger.shared.warning("Skipping \(name) installation due to bottle access restrictions.")
                    OSLogger.shared.info("This may be due to GHCR access limitations or rate limiting.")
                    OSLogger.shared.info("You can try installing \(name) again later or use an alternative installation method.")

                    throw VeloError.bottleNotAccessible(url: url, reason: reason)

                } catch {
                    OSLogger.shared.warning("Download failed (attempt \(attempt + 1)/\(maxRetries)): \(error.localizedDescription)")

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

            OSLogger.shared.success("\(formula.name) \(formula.version) installed successfully!")

            // Show next steps
            if verbose && !PathHelper.shared.isInPath() {
                OSLogger.shared.warning("Add ~/.velo/bin to your PATH to use installed packages:")
                print("  echo 'export PATH=\"$HOME/.velo/bin:$PATH\"' >> ~/.zshrc")
            }
        }

        // MARK: - Dependency Resolution with Complete Graph

        private func installDependenciesWithGraph(
            for formula: Formula,
            tapManager: TapManager,
            pathHelper: PathHelper
        ) async throws {
            let runtimeDependencies = formula.dependencies.filter { $0.type == .required }

            if runtimeDependencies.isEmpty {
                return
            }

            OSLogger.shared.info("Building complete dependency graph...")

            // Build complete dependency graph for ALL dependencies at once
            let dependencyNames = runtimeDependencies.map { $0.name }
            let graph = DependencyGraph(pathHelper: pathHelper)
            try await graph.buildCompleteGraph(for: dependencyNames, tapManager: tapManager)

            // Check for version conflicts
            if graph.hasConflicts {
                OSLogger.shared.warning("Version conflicts detected:")
                for conflict in graph.versionConflicts {
                    OSLogger.shared.warning("  ⚠️ \(conflict.description)")
                }
                OSLogger.shared.info("Proceeding with installation despite conflicts...")
            }

            // Get packages that need to be installed (using equivalence detection)
            let newPackages = graph.newPackages
            let installablePackages = graph.installablePackages
            let uninstallablePackages = graph.uninstallablePackages
            
            if newPackages.isEmpty {
                OSLogger.shared.info("✓ All dependencies already installed")
                return
            }

            OSLogger.shared.info("Dependencies to install: \(newPackages.count) packages")
            
            // Handle uninstallable packages
            if !uninstallablePackages.isEmpty {
                OSLogger.shared.warning("⚠️  Found \(uninstallablePackages.count) packages without compatible bottles:")
                for package in uninstallablePackages {
                    let availablePlatforms = package.formula.bottles.map { $0.platform.rawValue }.joined(separator: ", ")
                    if availablePlatforms.isEmpty {
                        OSLogger.shared.warning("  • \(package.name): No bottles available")
                    } else {
                        OSLogger.shared.warning("  • \(package.name): Available for \(availablePlatforms)")
                    }
                }
                OSLogger.shared.info("These packages will be skipped. The installation may not work correctly.")
                OSLogger.shared.info("Consider building from source or finding alternative packages.")
            }
            
            if installablePackages.isEmpty {
                OSLogger.shared.error("No packages can be installed - all dependencies lack compatible bottles")
                return
            }
            
            // Show install plan
            let installPlan = try InstallPlan(graph: graph, rootPackage: formula.name)
            installPlan.display()

            // Download only installable packages in parallel
            OSLogger.shared.info("Downloading \(installablePackages.count) installable packages in parallel...")
            let downloadManager = ParallelDownloadManager(pathHelper: pathHelper)
            let downloads = try await downloadManager.downloadAll(packages: installablePackages)

            // Install packages in dependency order
            let installOrder = try graph.getInstallOrder()
            OSLogger.shared.info("Installing packages in dependency order...")
            try await installPackagesInOrder(
                installOrder: installOrder,
                downloads: downloads,
                graph: graph,
                pathHelper: pathHelper
            )

            OSLogger.shared.success("All dependencies installed successfully!")
        }

        /// Install packages in the correct dependency order
        private func installPackagesInOrder(
            installOrder: [String],
            downloads: [String: DownloadResult],
            graph: DependencyGraph,
            pathHelper: PathHelper
        ) async throws {
            let installer = Installer(pathHelper: pathHelper)
            
            for packageName in installOrder {
                guard let node = graph.getNode(for: packageName) else { continue }
                
                // Skip if already installed
                if node.isInstalled {
                    continue
                }
                
                guard let downloadResult = downloads[packageName] else {
                    throw VeloError.installationFailed(
                        package: packageName,
                        reason: "Download result not found"
                    )
                }
                
                guard downloadResult.success else {
                    throw VeloError.installationFailed(
                        package: packageName,
                        reason: downloadResult.error?.localizedDescription ?? "Download failed"
                    )
                }
                
                // Install from pre-downloaded bottle
                try await installer.install(
                    formula: node.formula,
                    from: downloadResult.downloadPath,
                    progress: nil
                )
                
                // Clean up downloaded file
                try? FileManager.default.removeItem(at: downloadResult.downloadPath)
            }
        }
        
        // MARK: - Architecture Detection
        
        private static func getCurrentArchitecture() -> String {
            #if arch(arm64)
            return "Apple Silicon (arm64)"
            #elseif arch(x86_64)
            return "Intel (x86_64)"
            #else
            return "Unknown architecture"
            #endif
        }

    }

// MARK: - Progress Handler

private class CLIProgress: DownloadProgress, InstallationProgress {
    private var lastProgressUpdate = Date()
    private let updateInterval: TimeInterval = 0.1 // 100ms

    // MARK: - DownloadProgress

    func downloadDidStart(url: String, totalSize: Int64?) {
        if let size = totalSize {
            OSLogger.shared.info("Downloading \(formatBytes(size))...")
        } else {
            OSLogger.shared.info("Downloading...")
        }
    }

    func downloadDidUpdate(bytesDownloaded: Int64, totalBytes: Int64?) {
        let now = Date()
        guard now.timeIntervalSince(lastProgressUpdate) >= updateInterval else { return }
        lastProgressUpdate = now

        if let total = totalBytes {
            let percentage = Int((Double(bytesDownloaded) / Double(total)) * 100)
            OSLogger.shared.progress("Downloading: \(percentage)% (\(formatBytes(bytesDownloaded))/\(formatBytes(total)))")
        } else {
            OSLogger.shared.progress("Downloaded: \(formatBytes(bytesDownloaded))")
        }
    }

    func downloadDidComplete(url: String) {
        print("\n")
        OSLogger.shared.info("Download complete")
    }

    func downloadDidFail(url: String, error: Error) {
        print("\n")
        OSLogger.shared.error("Download failed: \(error.localizedDescription)")
    }

    // MARK: - InstallationProgress

    func installationDidStart(package: String, version: String) {
        OSLogger.shared.info("Installing \(package) \(version)...")
    }

    func extractionDidStart(totalFiles: Int?) {
        OSLogger.shared.info("Extracting package...")
    }

    func extractionDidUpdate(filesExtracted: Int, totalFiles: Int?) {
        // Don't spam with extraction updates
    }

    func linkingDidStart(binariesCount: Int) {
        if binariesCount > 0 {
            OSLogger.shared.info("Creating \(binariesCount) symlink(s)...")
        }
    }

    func linkingDidUpdate(binariesLinked: Int, totalBinaries: Int) {
        // Progress for linking is usually fast enough to not need updates
    }

    func installationDidComplete(package: String) {
        // Handled by the main command
    }

    func installationDidFail(package: String, error: Error) {
        OSLogger.shared.error("Installation of \(package) failed: \(error.localizedDescription)")
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}
}
