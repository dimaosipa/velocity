import Foundation
import ArgumentParser
import VeloCore
import VeloFormula
import VeloSystem

extension Velo {
    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install one or more packages"
        )

        @Argument(help: "The packages to install (optional if velo.json exists)")
        var packages: [String] = []

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

            // If no packages specified, try to install from velo.json
            if packages.isEmpty {
                try await installFromManifest(context: context)
                return
            }

            // Remove duplicates while preserving order
            var uniquePackages: [String] = []
            var seen = Set<String>()
            for pkg in packages {
                if !seen.contains(pkg) {
                    uniquePackages.append(pkg)
                    seen.insert(pkg)
                }
            }

            if uniquePackages.count != packages.count {
                let duplicates = packages.count - uniquePackages.count
                print("ℹ️  Removed \(duplicates) duplicate package(s)")
            }

            // Install each package sequentially
            let totalPackages = uniquePackages.count
            var successCount = 0
            var failedPackages: [String] = []

            for (index, packageInput) in uniquePackages.enumerated() {
                let packageNumber = index + 1
                if totalPackages > 1 {
                    print("\n[\(packageNumber)/\(totalPackages)] Installing \(packageInput)...")
                }

                do {
                    try await installSinglePackage(packageInput, context: context)
                    successCount += 1
                } catch {
                    print("❌ Failed to install \(packageInput): \(error.localizedDescription)")
                    failedPackages.append(packageInput)
                    // Continue with next package instead of stopping
                }
            }

            // Show final summary (only for multiple packages)
            if totalPackages > 1 {
                print("\n" + String(repeating: "=", count: 50))
                if successCount == totalPackages {
                    print("✓ Successfully installed all \(totalPackages) package(s)")
                } else {
                    print("✓ Successfully installed \(successCount)/\(totalPackages) package(s)")
                    if !failedPackages.isEmpty {
                        print("❌ Failed to install: \(failedPackages.joined(separator: ", "))")
                    }
                }
            }
        }

        /// Install a single package with all the existing logic
        private func installSinglePackage(_ packageInput: String, context: ProjectContext) async throws {
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

            // Check if already installed before showing installation messages (unless force is used)
            if !force {
                let tapManager = TapManager(pathHelper: pathHelper)
                let receiptManager = ReceiptManager(pathHelper: pathHelper)

                // If version is specified, check for that specific version first
                if let requestedVersion = resolvedVersion {
                    if let formula = try? tapManager.findFormula(resolvedName, version: requestedVersion) {
                        let installer = Installer(pathHelper: pathHelper)
                        let status = try? installer.verifyInstallation(formula: formula)
                        if status?.isInstalled == true {
                            // Check if it's installed as a dependency
                            if let receipt = try? receiptManager.loadReceipt(for: formula.name, version: formula.version),
                               receipt.installedAs == .dependency {
                                // Convert from dependency to explicit installation
                                print("✓ \(formula.name) \(formula.version) is already installed (as dependency of \(receipt.requestedBy.joined(separator: ", "))), creating symlinks...")

                                // Create symlinks
                                let packageDir = pathHelper.packagePath(for: formula.name, version: formula.version)
                                try await installer.createSymlinksForExistingPackage(formula: formula, packageDir: packageDir)

                                // Update receipt
                                try receiptManager.updateReceipt(for: formula.name, version: formula.version) { receipt in
                                    receipt.installedAs = .explicit
                                    receipt.symlinksCreated = true
                                }

                                print("✓ \(formula.name) is now available in PATH")
                                return
                            } else {
                                // Check if all dependencies are satisfied
                                let missingDeps = try await checkMissingDependencies(for: formula, tapManager: tapManager, pathHelper: pathHelper)
                                if !missingDeps.isEmpty {
                                    print("⚠️  \(formula.name) \(formula.version) is installed but missing dependencies: \(missingDeps.joined(separator: ", "))")
                                    print("Installing missing dependencies...")

                                    // Install only the missing dependencies
                                    try await installMissingDependencies(missingDeps, context: context, pathHelper: pathHelper)
                                    print("✓ \(formula.name) dependencies restored")
                                    return
                                } else {
                                    print("✓ \(formula.name) \(formula.version) is already installed")
                                    return
                                }
                            }
                        }
                    }
                } else {
                    // No version specified, check if any version is installed
                    if pathHelper.isEquivalentPackageInstalled(resolvedName) {
                        if let installedEquivalent = pathHelper.findInstalledEquivalentPackage(for: resolvedName) {
                            // Check receipt for the installed version
                            if let receipt = try? receiptManager.loadReceipt(for: installedEquivalent) {
                                if receipt.installedAs == .dependency {
                                    // Get the formula for creating symlinks
                                    if let formula = try? tapManager.findFormula(installedEquivalent) {
                                        print("✓ \(resolvedName) is already installed (as dependency of \(receipt.requestedBy.joined(separator: ", "))), creating symlinks...")

                                        // Create symlinks
                                        let installer = Installer(pathHelper: pathHelper)
                                        let packageDir = pathHelper.packagePath(for: formula.name, version: formula.version)
                                        try await installer.createSymlinksForExistingPackage(formula: formula, packageDir: packageDir)

                                        // Update receipt
                                        try receiptManager.updateReceipt(for: formula.name, version: formula.version) { receipt in
                                            receipt.installedAs = .explicit
                                            receipt.symlinksCreated = true
                                        }

                                        print("✓ \(formula.name) is now available in PATH")
                                        return
                                    }
                                }
                            }

                            // No receipt or already explicit - check dependencies
                            if let formula = try? tapManager.findFormula(installedEquivalent) {
                                let missingDeps = try await checkMissingDependencies(for: formula, tapManager: tapManager, pathHelper: pathHelper)
                                if !missingDeps.isEmpty {
                                    print("⚠️  \(resolvedName) is installed but missing dependencies: \(missingDeps.joined(separator: ", "))")
                                    print("Installing missing dependencies...")

                                    // Install only the missing dependencies
                                    try await installMissingDependencies(missingDeps, context: context, pathHelper: pathHelper)
                                    print("✓ \(resolvedName) dependencies restored")
                                    return
                                } else {
                                    if installedEquivalent == resolvedName {
                                        print("✓ \(resolvedName) is already installed")
                                    } else {
                                        print("✓ \(resolvedName) is already installed (via \(installedEquivalent))")
                                    }
                                    return
                                }
                            } else {
                                // Can't load formula, just report it's installed
                                if installedEquivalent == resolvedName {
                                    print("✓ \(resolvedName) is already installed")
                                } else {
                                    print("✓ \(resolvedName) is already installed (via \(installedEquivalent))")
                                }
                                return
                            }
                        }
                    }

                    // Also check via formula if we can get it quickly
                    if let formula = try? tapManager.findFormula(resolvedName) {
                        let installer = Installer(pathHelper: pathHelper)
                        let status = try? installer.verifyInstallation(formula: formula)
                        if status?.isInstalled == true {
                            // Check if all dependencies are satisfied
                            let missingDeps = try await checkMissingDependencies(for: formula, tapManager: tapManager, pathHelper: pathHelper)
                            if !missingDeps.isEmpty {
                                print("⚠️  \(formula.name) \(formula.version) is installed but missing dependencies: \(missingDeps.joined(separator: ", "))")
                                print("Installing missing dependencies...")

                                // Install only the missing dependencies
                                try await installMissingDependencies(missingDeps, context: context, pathHelper: pathHelper)
                                print("✓ \(formula.name) dependencies restored")
                                return
                            } else {
                                print("✓ \(formula.name) \(formula.version) is already installed")
                                return
                            }
                        }
                    }
                }
            }

            // Start installation with timing
            let startTime = Date()

            do {
                try await installPackage(
                    name: resolvedName,
                    version: resolvedVersion,
                    context: context,
                    pathHelper: pathHelper,
                    skipDeps: skipDependencies,
                    verbose: true,
                    skipTapUpdate: false,
                    forceTapUpdate: updateTaps,
                    force: force,
                    startTime: startTime
                )
            } catch VeloError.formulaNotFound(let name) {
                // Provide helpful search-based alternatives
                try await handleFormulaNotFound(name: name, tapManager: tapManager)
                throw VeloError.formulaNotFound(name: name) // Re-throw after showing suggestions
            }

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

            print("Installing \(allDeps.count) packages...")

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

            print("✓ All packages installed successfully!")
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
            guard let formula = try tapManager.findFormula(name, version: version) else {
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
                    print("✓ \(packageName) \(lockEntry.version) already installed")
                    continue
                }

                print("Installing \(packageName) \(lockEntry.version) from lock file...")

                // For frozen installs, we need to install the exact version specified
                // This is a simplified implementation - in practice, we'd need to:
                // 1. Ensure the exact tap commit is available
                // 2. Download from the exact URL specified in lock file
                // 3. Verify SHA256 matches

                let tapManager = TapManager(pathHelper: pathHelper)
                guard let formula = try tapManager.findFormula(packageName, version: lockEntry.version) else {
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

            print("✓ All packages installed from velo.lock successfully!")
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
            forceTapUpdate: Bool = false,
            force: Bool = false,
            startTime: Date = Date()
        ) async throws {
            let downloader = BottleDownloader()
            let installer = Installer(pathHelper: pathHelper)
            let tapManager = TapManager(pathHelper: pathHelper)
            let progressHandler = CLIProgress()

            // Calculate total steps based on what we'll actually do
            let totalSteps = (skipTapUpdate ? 0 : 1) + (skipDeps ? 0 : 1) + 2 // +2 for download & install

            // Update package database if needed
            var stepCount = 1
            if !skipTapUpdate {
                ProgressReporter.shared.startLiveStep("[\(stepCount)/\(totalSteps)] 📥 Updating package database")
                try await tapManager.updateTaps(force: forceTapUpdate)
                ProgressReporter.shared.completeLiveStep("Updated package database")
                stepCount += 1
            }

            // Parse formula
            guard let formula = try tapManager.findFormula(name, version: version) else {
                throw VeloError.formulaNotFound(name: name)
            }

            // Note: Already installed check is now done in the main run() function

            // Resolve dependencies (but don't install yet - that happens during installation step)
            if !skipDeps {
                ProgressReporter.shared.startLiveStep("[\(stepCount)/\(totalSteps)] 🔍 Resolving dependencies")
                let depCount = try await resolveDependencies(
                    for: formula,
                    tapManager: tapManager,
                    pathHelper: pathHelper
                )
                if depCount > 0 {
                    ProgressReporter.shared.completeLiveStep("[\(stepCount)/\(totalSteps)] ✓ Resolved \(depCount) dependencies")
                } else {
                    ProgressReporter.shared.completeLiveStep("[\(stepCount)/\(totalSteps)] ✓ No dependencies required")
                }
                stepCount += 1
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

            // Download main package  
            ProgressReporter.shared.startLiveStep("[\(stepCount)/\(totalSteps)] ⬇️ Downloading \(formula.name)")

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

            ProgressReporter.shared.completeLiveStep("Downloaded \(formula.name)")

            // Install main package  
            stepCount += 1
            ProgressReporter.shared.startLiveStep("[\(stepCount)/\(totalSteps)] 🔧 Installing \(formula.name)")

            // Install dependencies first if any (with progress)
            let depCount = try await installDependenciesWithProgress(
                for: formula,
                tapManager: tapManager,
                pathHelper: pathHelper,
                force: force,
                stepCount: stepCount,
                totalSteps: totalSteps
            )

            // Now install the main package
            if depCount > 0 {
                ProgressReporter.shared.updateLiveProgress("[\(stepCount)/\(totalSteps)] 🔧 Installing \(formula.name) (main package)")
            }

            try await installer.install(
                formula: formula,
                from: tempFile,
                progress: progressHandler,
                force: force,
                shouldCreateSymlinks: true  // Main package gets symlinks
            )

            // Create receipt for explicitly installed package
            let receiptManager = ReceiptManager(pathHelper: pathHelper)
            let receipt = InstallationReceipt(
                package: formula.name,
                version: formula.version,
                installedAs: .explicit,
                requestedBy: [],
                symlinksCreated: true
            )
            try receiptManager.saveReceipt(receipt)

            if depCount > 0 {
                ProgressReporter.shared.completeLiveStep("[\(stepCount)/\(totalSteps)] ✓ Installed \(formula.name) and \(depCount) dependencies")
            } else {
                ProgressReporter.shared.completeLiveStep("[\(stepCount)/\(totalSteps)] ✓ Installed \(formula.name)")
            }

            // Clean up
            try? FileManager.default.removeItem(at: tempFile)

            // Show final success message with timing
            let duration = Date().timeIntervalSince(startTime)
            let verb = force ? "reinstalled" : "installed"
            print("✓ \(formula.name)@\(formula.version) \(verb) in \(String(format: "%.1f", duration))s")

            // Show next steps
            if verbose && !PathHelper.shared.isInPath() {
                OSLogger.shared.warning("Add ~/.velo/bin to your PATH to use installed packages:")
                print("  echo 'export PATH=\"$HOME/.velo/bin:$PATH\"' >> ~/.zshrc")
            }
        }

        // MARK: - Dependency Resolution with Complete Graph

        /// Resolve dependencies without installing them
        private func resolveDependencies(
            for formula: Formula,
            tapManager: TapManager,
            pathHelper: PathHelper
        ) async throws -> Int {
            let runtimeDependencies = formula.dependencies.filter { $0.type == .required }

            if runtimeDependencies.isEmpty {
                return 0
            }

            // Build dependency graph quietly
            let dependencyNames = runtimeDependencies.map { $0.name }
            let graph = DependencyGraph(pathHelper: pathHelper)

            // Update progress with package count discovery
            ProgressReporter.shared.updateLiveProgress("Resolving dependencies... (\(dependencyNames.count) direct)")

            try await graph.buildCompleteGraph(for: dependencyNames, tapManager: tapManager)

            // Update with total resolved count
            ProgressReporter.shared.updateLiveProgress("Resolving dependencies... (\(graph.allPackages.count) total)")

            // Version conflicts are handled at the equivalence level
            // No additional conflict checking needed since Homebrew formulae
            // are designed to work together

            return graph.installablePackages.count
        }

        /// Install dependencies with detailed progress reporting
        private func installDependenciesWithProgress(
            for formula: Formula,
            tapManager: TapManager,
            pathHelper: PathHelper,
            force: Bool = false,
            stepCount: Int,
            totalSteps: Int
        ) async throws -> Int {
            let runtimeDependencies = formula.dependencies.filter { $0.type == .required }

            if runtimeDependencies.isEmpty {
                return 0
            }

            // Build dependency graph
            let dependencyNames = runtimeDependencies.map { $0.name }
            let graph = DependencyGraph(pathHelper: pathHelper)
            try await graph.buildCompleteGraph(for: dependencyNames, tapManager: tapManager)

            let installablePackages = graph.installablePackages

            if installablePackages.isEmpty {
                return 0
            }

            // Create install plan and execute installation with progress
            let installPlan = try InstallPlan(graph: graph, rootPackage: formula.name)

            // Download all dependencies with progress
            ProgressReporter.shared.startLiveStep("Downloading dependencies")
            let downloadManager = ParallelDownloadManager(pathHelper: pathHelper)
            let downloadTracker = DownloadProgressTracker(packageCount: installablePackages.count)
            let downloadProgress = VisualParallelDownloadProgress(tracker: downloadTracker)
            let downloads = try await downloadManager.downloadAll(packages: installablePackages, progress: downloadProgress)
            ProgressReporter.shared.completeLiveStep("Downloaded dependencies")

            let installOrder = installPlan.installOrder

            // Install with detailed progress
            try await installPackagesInOrder(
                installOrder: installOrder,
                downloads: downloads,
                graph: graph,
                pathHelper: pathHelper,
                installTracker: nil,
                force: force,
                showProgress: true,
                stepCount: stepCount,
                totalSteps: totalSteps,
                requestedBy: formula.name  // Track parent package
            )

            return installablePackages.count
        }

        private func installDependenciesWithGraph(
            for formula: Formula,
            tapManager: TapManager,
            pathHelper: PathHelper,
            force: Bool = false
        ) async throws -> Int {
            let runtimeDependencies = formula.dependencies.filter { $0.type == .required }

            if runtimeDependencies.isEmpty {
                return 0
            }

            // Build dependency graph quietly
            let dependencyNames = runtimeDependencies.map { $0.name }
            let graph = DependencyGraph(pathHelper: pathHelper)

            // Update progress with package count discovery
            ProgressReporter.shared.updateLiveProgress("Resolving dependencies... (\(dependencyNames.count) direct)")

            try await graph.buildCompleteGraph(for: dependencyNames, tapManager: tapManager)

            // Update with total resolved count
            ProgressReporter.shared.updateLiveProgress("Resolving dependencies... (\(graph.allPackages.count) total)")

            // Version conflicts are handled at the equivalence level
            // No additional conflict checking needed since Homebrew formulae
            // generally don't specify version constraints

            // Get packages that need to be installed (using equivalence detection)
            let newPackages = graph.newPackages
            let installablePackages = graph.installablePackages
            let uninstallablePackages = graph.uninstallablePackages

            if newPackages.isEmpty {
                return 0
            }

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
                return 0
            }

            // Create install plan and execute installation
            let installPlan = try InstallPlan(graph: graph, rootPackage: formula.name)

            // Download and install packages quietly (they have their own progress)
            let downloadManager = ParallelDownloadManager(pathHelper: pathHelper)
            let downloads = try await downloadManager.downloadAll(packages: installablePackages, progress: nil)

            let installOrder = installPlan.installOrder
            // Show progress during dependency installation if there are dependencies
            if !installOrder.isEmpty {
                let hasUninstalled = installOrder.contains { packageName in
                    guard let node = graph.getNode(for: packageName) else { return false }
                    return !node.isInstalled
                }

                if hasUninstalled {
                    ProgressReporter.shared.updateLiveProgress("Installing dependencies...")
                }
            }

            try await installPackagesInOrder(
                installOrder: installOrder,
                downloads: downloads,
                graph: graph,
                pathHelper: pathHelper,
                installTracker: nil,
                force: force,
                showProgress: false  // Keep quiet for dependencies to avoid noise
            )

            return installablePackages.count
        }

        /// Install packages in the correct dependency order
        private func installPackagesInOrder(
            installOrder: [String],
            downloads: [String: DownloadResult],
            graph: DependencyGraph,
            pathHelper: PathHelper,
            installTracker: InstallationProgressTracker?,
            force: Bool = false,
            showProgress: Bool = false,
            stepCount: Int = 0,
            totalSteps: Int = 0,
            requestedBy: String? = nil  // Track which package requested these dependencies
        ) async throws {
            let installer = Installer(pathHelper: pathHelper)
            installTracker?.startInstallation()

            var currentIndex = 0
            let totalPackages = installOrder.filter { packageName in
                guard let node = graph.getNode(for: packageName) else { return false }
                return !node.isInstalled
            }.count

            for packageName in installOrder {
                guard let node = graph.getNode(for: packageName) else { continue }

                // Skip if already installed
                if node.isInstalled {
                    continue
                }

                currentIndex += 1

                // Show progress if requested
                if showProgress {
                    ProgressReporter.shared.updateLiveProgress("[\(stepCount)/\(totalSteps)] 🔧 Installing dependencies (\(currentIndex)/\(totalPackages)): \(packageName)")
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

                // Track installation progress
                installTracker?.startPackageInstallation(packageName)

                // Install from pre-downloaded bottle
                let visualProgress: InstallationProgress? = installTracker != nil ? VisualInstallationProgress(tracker: installTracker!, packageName: packageName) : nil
                try await installer.install(
                    formula: node.formula,
                    from: downloadResult.downloadPath,
                    progress: visualProgress,
                    force: force,
                    shouldCreateSymlinks: false  // Dependencies don't get symlinks
                )

                // Create receipt for dependency
                let receiptManager = ReceiptManager(pathHelper: pathHelper)
                let receipt = InstallationReceipt(
                    package: node.formula.name,
                    version: node.formula.version,
                    installedAs: .dependency,
                    requestedBy: requestedBy != nil ? [requestedBy!] : [],
                    symlinksCreated: false
                )
                try receiptManager.saveReceipt(receipt)

                // Update parent's receipt to add this dependency
                if requestedBy != nil {
                    // The parent might not have a receipt yet if we're installing its dependencies first
                    // So we'll handle this gracefully
                }

                installTracker?.completePackageInstallation(packageName)

                // Clean up downloaded file
                try? FileManager.default.removeItem(at: downloadResult.downloadPath)
            }

            installTracker?.completeAllInstallations()
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

        // MARK: - Formula Not Found Handling

        /// Handle formula not found errors by showing search-based alternatives
        private func handleFormulaNotFound(name: String, tapManager: TapManager) async throws {
            print("Error: Formula '\(name)' not found.")
            print("")

            // Try to build the search index if it hasn't been built yet
            try await tapManager.buildFullIndex()

            // Search for similar packages
            let searchResults = tapManager.searchFormulae(name, includeDescriptions: false)

            // For common generic names, also search for versioned packages
            let versionedSearchResults = searchForVersionedPackages(name: name, tapManager: tapManager)
            let allResults = Array(Set(searchResults + versionedSearchResults))

            if !allResults.isEmpty {
                print("Did you mean one of these?")

                // Show up to 8 results, prioritizing versioned packages and latest versions
                let sortedResults = allResults.prefix(8).sorted { result1, result2 in
                    let name1 = result1.lowercased()
                    let name2 = result2.lowercased()
                    let searchTerm = name.lowercased()

                    // Check if these are versioned packages of the search term
                    let isVersioned1 = name1.hasPrefix("\(searchTerm)@")
                    let isVersioned2 = name2.hasPrefix("\(searchTerm)@")

                    // Prefer versioned packages for generic names
                    if isVersioned1 && !isVersioned2 { return true }
                    if !isVersioned1 && isVersioned2 { return false }

                    // If both are versioned packages, sort by version (descending)
                    if isVersioned1 && isVersioned2 {
                        return result1 > result2 // String comparison works for most version formats
                    }

                    // Otherwise prefer results that start with the search term
                    let starts1 = name1.hasPrefix(searchTerm)
                    let starts2 = name2.hasPrefix(searchTerm)

                    if starts1 && !starts2 { return true }
                    if !starts1 && starts2 { return false }

                    // Then prefer shorter names (more specific)
                    if name1.count != name2.count {
                        return name1.count < name2.count
                    }

                    return name1 < name2
                }

                for result in sortedResults {
                    print("  \(result)")
                }

                // Show specific suggestion for common generic names
                let suggestion = getSuggestionForGenericName(name, from: Array(sortedResults))
                if let suggestion = suggestion {
                    print("")
                    print("Try: velo install \(suggestion)")
                }
            } else {
                // No search results found
                print("No similar packages found.")
                print("")
                print("You can:")
                print("  • Check the spelling of the package name")
                print("  • Search all packages: velo search \(name)")
                print("  • Browse available packages: velo list")
            }
            print("")
        }

        /// Search for versioned packages when looking for common generic names
        private func searchForVersionedPackages(name: String, tapManager: TapManager) -> [String] {
            let commonGenericNames = ["python", "node", "mysql", "postgresql", "postgres", "openssl"]

            guard commonGenericNames.contains(name.lowercased()) else {
                return []
            }

            // Search for versioned packages using the @ symbol
            let versionedSearchTerm = "\(name)@"
            return tapManager.searchFormulae(versionedSearchTerm, includeDescriptions: false)
        }

        /// Get a specific suggestion for common generic package names
        private func getSuggestionForGenericName(_ name: String, from results: [String]) -> String? {
            let genericMappings: [String: String] = [
                "python": "python@",
                "node": "node@",
                "mysql": "mysql@",
                "postgresql": "postgresql@",
                "postgres": "postgresql@",
                "openssl": "openssl@"
            ]

            guard let prefix = genericMappings[name.lowercased()] else {
                return results.first // Default to first result
            }

            // Find the latest version of the requested package type
            let versionedResults = results.filter { $0.lowercased().hasPrefix(prefix) }

            // Sort by version (latest first) - this is a simple string sort which works for most cases
            let sortedVersions = versionedResults.sorted { version1, version2 in
                // Extract version numbers for basic comparison
                let v1 = version1.replacingOccurrences(of: prefix, with: "")
                let v2 = version2.replacingOccurrences(of: prefix, with: "")
                return v1 > v2 // Latest first
            }

            return sortedVersions.first ?? results.first
        }

        /// Check if any dependencies are missing for the given formula
        private func checkMissingDependencies(
            for formula: Formula,
            tapManager: TapManager,
            pathHelper: PathHelper
        ) async throws -> [String] {
            var missingDeps: [String] = []

            // Only check runtime dependencies
            let runtimeDependencies = formula.dependencies.filter { $0.type == .required }

            for dep in runtimeDependencies {
                // Check if this dependency is installed
                if !pathHelper.isPackageInstalled(dep.name) {
                    // Also check for equivalent packages
                    if !pathHelper.isEquivalentPackageInstalled(dep.name) {
                        missingDeps.append(dep.name)
                    }
                }
            }

            return missingDeps
        }

        /// Install only the missing dependencies for a package
        private func installMissingDependencies(
            _ missingDeps: [String],
            context: ProjectContext,
            pathHelper: PathHelper
        ) async throws {
            for depName in missingDeps {
                print("🔧 Installing missing dependency: \(depName)")

                // Install the dependency directly using the existing installation logic
                try await installPackage(
                    name: depName,
                    version: nil,  // Use latest version
                    context: context,
                    pathHelper: pathHelper,
                    skipDeps: false,  // Dependencies might have their own dependencies
                    verbose: false,   // Reduce noise for dependency installation
                    skipTapUpdate: true,  // Skip tap update since we likely just updated
                    forceTapUpdate: false,
                    force: false,
                    startTime: Date()
                )
            }
        }

    }

// MARK: - Progress Handlers

private class CLIProgress: DownloadProgress, InstallationProgress {
    private var lastProgressUpdate = Date()
    private let updateInterval: TimeInterval = 0.5 // 500ms

    // MARK: - DownloadProgress

    func downloadDidStart(url: String, totalSize: Int64?) {
        if let size = totalSize {
            ProgressReporter.shared.startStep("Downloading \(formatBytes(size))")
        } else {
            ProgressReporter.shared.startStep("Downloading")
        }
    }

    func downloadDidUpdate(bytesDownloaded: Int64, totalBytes: Int64?) {
        let now = Date()
        guard now.timeIntervalSince(lastProgressUpdate) >= updateInterval else { return }
        lastProgressUpdate = now

        if let total = totalBytes {
            let progress = Double(bytesDownloaded) / Double(total)
            let message = "Downloading \(formatBytes(bytesDownloaded))/\(formatBytes(total))"
            ProgressReporter.shared.updateProgress(progress, message: message)
        } else {
            ProgressReporter.shared.updateProgress(0.5, message: "Downloaded \(formatBytes(bytesDownloaded))")
        }
    }

    func downloadDidComplete(url: String) {
        ProgressReporter.shared.completeStep("Download complete")
    }

    func downloadDidFail(url: String, error: Error) {
        ProgressReporter.shared.failStep("Download failed: \(error.localizedDescription)")
    }

    // MARK: - InstallationProgress

    func installationDidStart(package: String, version: String) {
        // Don't start a new step - we're already in a live step
        ProgressReporter.shared.updateLiveProgress("Installing \(package) \(version)")
    }

    func extractionDidStart(totalFiles: Int?) {
        if let total = totalFiles {
            ProgressReporter.shared.updateLiveProgress("Extracting \(total) files")
        } else {
            ProgressReporter.shared.updateLiveProgress("Extracting package")
        }
    }

    func extractionDidUpdate(filesExtracted: Int, totalFiles: Int?) {
        if let total = totalFiles {
            ProgressReporter.shared.updateLiveProgress("Extracting (\(filesExtracted)/\(total))")
        } else {
            ProgressReporter.shared.updateLiveProgress("Extracting (\(filesExtracted) files)")
        }
    }

    func processingDidStart(phase: String) {
        ProgressReporter.shared.updateLiveProgress(phase)
    }

    func processingDidUpdate(phase: String, progress: Double) {
        ProgressReporter.shared.updateLiveProgress(phase)
    }

    func linkingDidStart(binariesCount: Int) {
        if binariesCount > 0 {
            ProgressReporter.shared.updateLiveProgress("Creating \(binariesCount) symlinks")
        } else {
            ProgressReporter.shared.updateLiveProgress("Processing package")
        }
    }

    func linkingDidUpdate(binariesLinked: Int, totalBinaries: Int) {
        if totalBinaries > 0 {
            ProgressReporter.shared.updateLiveProgress("Linking (\(binariesLinked)/\(totalBinaries))")
        } else {
            ProgressReporter.shared.updateLiveProgress("Finalizing installation")
        }
    }

    func installationDidComplete(package: String) {
        // Don't complete step here - let the main flow handle it
        ProgressReporter.shared.updateLiveProgress("\(package) installed")
    }

    func installationDidFail(package: String, error: Error) {
        ProgressReporter.shared.failStep("Installation of \(package) failed: \(error.localizedDescription)")
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Visual Progress Adapters

private class VisualParallelDownloadProgress: ParallelDownloadProgress {
    private let tracker: DownloadProgressTracker

    init(tracker: DownloadProgressTracker) {
        self.tracker = tracker
    }

    func downloadDidStart(totalPackages: Int, totalSize: Int64?) {
        tracker.startDownloads()
    }

    func packageDownloadDidStart(package: String, size: Int64?) {
        tracker.startPackageDownload(package, totalSize: size)
    }

    func packageDownloadDidUpdate(package: String, bytesDownloaded: Int64, totalBytes: Int64?) {
        tracker.updatePackageDownload(package, bytesDownloaded: bytesDownloaded, totalBytes: totalBytes)
    }

    func packageDownloadDidComplete(package: String, success: Bool, error: Error?) {
        tracker.completePackageDownload(package, success: success)
    }

    func allDownloadsDidComplete(successful: Int, failed: Int) {
        tracker.completeAllDownloads()
    }
}

private class VisualInstallationProgress: InstallationProgress {
    private let tracker: InstallationProgressTracker
    private let packageName: String

    init(tracker: InstallationProgressTracker, packageName: String) {
        self.tracker = tracker
        self.packageName = packageName
    }

    func installationDidStart(package: String, version: String) {
        // Already handled by InstallationProgressTracker
    }

    func extractionDidStart(totalFiles: Int?) {
        tracker.updatePhase("Extracting \(packageName)")
    }

    func extractionDidUpdate(filesExtracted: Int, totalFiles: Int?) {
        if let total = totalFiles {
            tracker.updatePhase("Extracting \(packageName) (\(filesExtracted)/\(total))")
        }
    }

    func processingDidStart(phase: String) {
        tracker.updatePhase("\(phase) (\(packageName))")
    }

    func processingDidUpdate(phase: String, progress: Double) {
        tracker.updatePhase("\(phase) (\(packageName))")
    }

    func linkingDidStart(binariesCount: Int) {
        tracker.updatePhase("Linking \(packageName) (\(binariesCount) binaries)")
    }

    func linkingDidUpdate(binariesLinked: Int, totalBinaries: Int) {
        tracker.updatePhase("Linking \(packageName) (\(binariesLinked)/\(totalBinaries))")
    }

    func installationDidComplete(package: String) {
        // Handled by InstallationProgressTracker
    }

    func installationDidFail(package: String, error: Error) {
        tracker.updatePhase("Failed to install \(packageName): \(error.localizedDescription)")
    }
}
}
