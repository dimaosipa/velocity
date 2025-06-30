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
            let packageSpec = PackageSpecification.parse(packageInput)
            guard packageSpec.isValid else {
                throw VeloError.formulaNotFound(name: "Invalid package specification: \(packageInput)")
            }

            // Determine version: inline @version takes precedence over --version flag
            let finalVersion = packageSpec.version ?? version

            // Determine if we should install locally or globally
            let useLocal = !global && context.isProjectContext

            // Get appropriate PathHelper
            let pathHelper = context.getPathHelper(preferLocal: useLocal)

            try await installPackage(
                name: packageSpec.name,
                version: finalVersion,
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
                    package: packageSpec.name,
                    version: finalVersion,
                    context: context
                )
            }
        }

        private func installFromManifest(context: ProjectContext) async throws {
            guard context.isProjectContext else {
                logError("No velo.json found. Run 'velo init' to create one or specify a package name.")
                throw ExitCode.failure
            }

            guard let manifestPath = context.manifestPath else {
                throw VeloError.notInProjectContext
            }

            logInfo("Installing packages from velo.json...")

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

            logInfo("Installing \(allDeps.count) packages...")

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

            Logger.shared.success("All packages installed successfully!")
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
            logInfo("Updated velo.lock with \(installedPackages.count) packages")
        }

        private func handleLockFileFlags(context: ProjectContext, pathHelper: PathHelper) async throws {
            guard let lockFilePath = context.lockFilePath else {
                logError("No velo.lock file found. Cannot use --frozen or --check flags.")
                throw ExitCode.failure
            }

            guard FileManager.default.fileExists(atPath: lockFilePath.path) else {
                logError("velo.lock file does not exist. Run 'velo install' first to create it.")
                throw ExitCode.failure
            }

            let lockFileManager = VeloLockFileManager()
            let lockFile = try lockFileManager.read(from: lockFilePath)

            if check {
                logInfo("Checking lock file integrity...")
                let installedPackages = try getInstalledPackagesForVerification(pathHelper: pathHelper)
                let mismatches = lockFileManager.verifyInstallations(lockFile: lockFile, installedPackages: installedPackages)

                if !mismatches.isEmpty {
                    logWarning("Lock file mismatches detected:")
                    for mismatch in mismatches {
                        print("  • \(mismatch)")
                    }
                    print("")
                }
            }

            if frozen {
                logInfo("Installing exactly from velo.lock (frozen mode)...")
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
                    logInfo("✓ \(packageName) \(lockEntry.version) already installed")
                    continue
                }

                logInfo("Installing \(packageName) \(lockEntry.version) from lock file...")

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

            Logger.shared.success("All packages installed from velo.lock successfully!")
        }

        private func ensureRequiredTaps(_ requiredTaps: [String], pathHelper: PathHelper) async throws {
            logInfo("Ensuring required taps are available...")

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
                logInfo("All required taps are available")
                return
            }

            logInfo("Adding missing taps: \(missingTaps.joined(separator: ", "))")

            // Add missing taps
            for tapName in missingTaps {
                do {
                    try await addTap(tapName, to: tapsPath)
                    logInfo("✓ Added tap \(tapName)")
                } catch {
                    logError("Failed to add required tap \(tapName): \(error)")
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

            logInfo("Added \(package)@\(versionToSave) to dependencies")
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
                logInfo("Installing \(name)...")
            }

            // Ensure we have the homebrew/core tap (skip for dependencies)
            if !skipTapUpdate {
                try await tapManager.updateTaps(force: forceTapUpdate)
            }

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
                try await installDependencies(for: formula, context: context, pathHelper: pathHelper)
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

        private func installDependencies(
            for formula: Formula,
            context: ProjectContext,
            pathHelper: PathHelper
        ) async throws {
            let runtimeDependencies = formula.dependencies.filter { $0.type == .required }

            if runtimeDependencies.isEmpty {
                return
            }

            logInfo("Checking \(runtimeDependencies.count) runtime dependencies...")

            var failedDependencies: [String] = []

            for dependency in runtimeDependencies {
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
                        version: nil,
                        context: context,
                        pathHelper: pathHelper,
                        skipDeps: true,
                        verbose: false,
                        skipTapUpdate: true,
                        forceTapUpdate: false
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
