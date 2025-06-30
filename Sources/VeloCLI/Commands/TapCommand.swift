import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct Tap: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "tap",
            abstract: "Manage package repositories (taps)",
            subcommands: [
                TapList.self,
                TapAdd.self,
                TapRemove.self,
                TapUpdate.self
            ],
            defaultSubcommand: TapList.self
        )
    }
}

// MARK: - Tap List

extension Velo.Tap {
    struct TapList: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all installed taps"
        )

        @Flag(help: "Show detailed information including URLs")
        var verbose = false

        @Flag(help: "List global taps instead of local")
        var global = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let context = ProjectContext()

            // Determine if we should use local or global taps
            let useLocal = !global && context.isProjectContext

            // Get appropriate PathHelper
            let pathHelper = context.getPathHelper(preferLocal: useLocal)
            let tapsPath = pathHelper.tapsPath

            guard FileManager.default.fileExists(atPath: tapsPath.path) else {
                print("No taps installed")
                return
            }

            let taps = try getTaps(from: tapsPath)

            if taps.isEmpty {
                print("No taps installed")
                return
            }

            let scopeInfo = useLocal ? " (local)" : " (global)"
            print("Installed taps (\(taps.count))\(scopeInfo):")
            print("")

            for tap in taps.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending }) {
                if verbose {
                    print("📦 \(tap.name)")
                    print("   URL: \(tap.url)")
                    print("   Path: \(tap.path.path)")
                    if let formulaCount = tap.formulaCount {
                        print("   Formulae: \(formulaCount)")
                    } else {
                        print("   Formulae: Unknown")
                    }
                    print("")
                } else {
                    print("📦 \(tap.name)")
                }
            }
        }

        private func getTaps(from tapsPath: URL) throws -> [TapInfo] {
            var taps: [TapInfo] = []

            let organizations = try FileManager.default.contentsOfDirectory(atPath: tapsPath.path)
                .filter { !$0.hasPrefix(".") }

            for org in organizations {
                let orgPath = tapsPath.appendingPathComponent(org)
                var isDirectory: ObjCBool = false

                guard FileManager.default.fileExists(atPath: orgPath.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }

                let repos = try FileManager.default.contentsOfDirectory(atPath: orgPath.path)
                    .filter { !$0.hasPrefix(".") }

                for repo in repos {
                    let repoPath = orgPath.appendingPathComponent(repo)
                    guard FileManager.default.fileExists(atPath: repoPath.path, isDirectory: &isDirectory),
                          isDirectory.boolValue else {
                        continue
                    }

                    let tapName = "\(org)/\(repo)"
                    let tapInfo = TapInfo(
                        name: tapName,
                        path: repoPath,
                        url: getRemoteURL(for: repoPath) ?? "Unknown",
                        formulaCount: getFormulaCount(in: repoPath)
                    )
                    taps.append(tapInfo)
                }
            }

            return taps
        }

        private func getRemoteURL(for repoPath: URL) -> String? {
            let gitConfigPath = repoPath.appendingPathComponent(".git/config")
            guard let content = try? String(contentsOf: gitConfigPath) else {
                return nil
            }

            // Extract remote URL from git config
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("url = ") {
                    return String(trimmed.dropFirst(6))
                } else if trimmed.hasPrefix("url\t=") || trimmed.hasPrefix("url=") {
                    // Handle cases with tabs or no spaces
                    if let equalIndex = trimmed.firstIndex(of: "=") {
                        let afterEqual = String(trimmed[trimmed.index(after: equalIndex)...])
                        return afterEqual.trimmingCharacters(in: .whitespaces)
                    }
                }
            }

            return nil
        }

        private func getFormulaCount(in repoPath: URL) -> Int? {
            let formulaPath = repoPath.appendingPathComponent("Formula")
            guard FileManager.default.fileExists(atPath: formulaPath.path) else {
                return nil
            }

            do {
                // Count .rb files in all subdirectories
                var count = 0
                let items = try FileManager.default.contentsOfDirectory(atPath: formulaPath.path)

                for item in items {
                    let itemPath = formulaPath.appendingPathComponent(item)
                    var isDirectory: ObjCBool = false

                    if FileManager.default.fileExists(atPath: itemPath.path, isDirectory: &isDirectory) {
                        if isDirectory.boolValue {
                            // Count .rb files in subdirectory
                            let subItems = try FileManager.default.contentsOfDirectory(atPath: itemPath.path)
                            count += subItems.filter { $0.hasSuffix(".rb") }.count
                        } else if item.hasSuffix(".rb") {
                            count += 1
                        }
                    }
                }

                return count
            } catch {
                return nil
            }
        }
    }
}

// MARK: - Tap Add

extension Velo.Tap {
    struct TapAdd: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add a new tap"
        )

        @Argument(help: "Tap name in format 'user/repo' or full GitHub URL")
        var tap: String

        @Flag(help: "Force add even if tap already exists")
        var force = false

        @Flag(help: "Add tap globally instead of locally")
        var global = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let context = ProjectContext()

            // Determine if we should use local or global taps
            let useLocal = !global && context.isProjectContext

            // Get appropriate PathHelper
            let pathHelper = context.getPathHelper(preferLocal: useLocal)

            let (tapName, url) = try parseTapInput(tap)
            let tapPath = pathHelper.tapsPath.appendingPathComponent(tapName)

            // Check if tap already exists
            if FileManager.default.fileExists(atPath: tapPath.path) && !force {
                logError("Tap '\(tapName)' already exists. Use --force to reinstall.")
                throw ExitCode.failure
            }

            let scopeInfo = useLocal ? "locally to .velo/taps/" : "globally to ~/.velo/taps/"
            logInfo("Adding tap \(tapName) \(scopeInfo)")
            logInfo("Repository: \(url)")

            // Remove existing if force flag is used
            if FileManager.default.fileExists(atPath: tapPath.path) && force {
                try FileManager.default.removeItem(at: tapPath)
            }

            // Ensure parent directory exists
            try FileManager.default.createDirectory(
                at: tapPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Clone the tap
            try await cloneTap(from: url, to: tapPath)

            // Update velo.json if in project context and using local taps
            if useLocal && context.isProjectContext {
                try await updateManifestWithTap(tapName, context: context, action: .add)
            }

            // Verify the tap was added successfully
            let formulaPath = tapPath.appendingPathComponent("Formula")
            if FileManager.default.fileExists(atPath: formulaPath.path) {
                let count = getFormulaCount(in: tapPath)
                if let count = count, count > 0 {
                    Logger.shared.success("Successfully added tap '\(tapName)' with \(count) formulae")
                } else {
                    Logger.shared.success("Successfully added tap '\(tapName)'")
                }
            } else {
                logWarning("Tap added but no Formula directory found. This may not be a valid Homebrew tap.")
            }
        }

        private func parseTapInput(_ input: String) throws -> (name: String, url: String) {
            // Handle full URLs
            if input.hasPrefix("https://") || input.hasPrefix("git@") {
                // Extract name from URL
                let url = input
                var name = url

                // Extract user/repo from GitHub URLs
                if let range = url.range(of: "github.com/") {
                    let afterGitHub = String(url[range.upperBound...])
                    let components = afterGitHub.components(separatedBy: "/")
                    if components.count >= 2 {
                        let user = components[0]
                        let fullRepo = components[1].replacingOccurrences(of: ".git", with: "")

                        // Convert homebrew-prefixed repo names to shorthand for display
                        let displayRepo = fullRepo.hasPrefix("homebrew-") ? String(fullRepo.dropFirst(9)) : fullRepo
                        name = "\(user)/\(displayRepo)"
                    }
                }

                return (name: name, url: url)
            }

            // Handle user/repo format
            let components = input.components(separatedBy: "/")
            guard components.count == 2 else {
                throw VeloError.invalidTapName(input)
            }

            let user = components[0]
            let repo = components[1]

            // Normalize tap name: always use shortened version for display
            let normalizedRepo = repo.hasPrefix("homebrew-") ? String(repo.dropFirst(9)) : repo
            let tapName = "\(user)/\(normalizedRepo)"

            // Apply repository naming convention: repositories must be prefixed with "homebrew-"
            let actualRepo = repo.hasPrefix("homebrew-") ? repo : "homebrew-\(repo)"
            let url = "https://github.com/\(user)/\(actualRepo).git"

            return (name: tapName, url: url)
        }

        private func cloneTap(from url: String, to path: URL) async throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = [
                "clone",
                "--depth", "1",
                url,
                path.path
            ]

            try await runProcess(process, description: "Cloning tap")
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

        private func getFormulaCount(in repoPath: URL) -> Int? {
            let formulaPath = repoPath.appendingPathComponent("Formula")
            guard FileManager.default.fileExists(atPath: formulaPath.path) else {
                return nil
            }

            do {
                var count = 0
                let items = try FileManager.default.contentsOfDirectory(atPath: formulaPath.path)

                for item in items {
                    let itemPath = formulaPath.appendingPathComponent(item)
                    var isDirectory: ObjCBool = false

                    if FileManager.default.fileExists(atPath: itemPath.path, isDirectory: &isDirectory) {
                        if isDirectory.boolValue {
                            let subItems = try FileManager.default.contentsOfDirectory(atPath: itemPath.path)
                            count += subItems.filter { $0.hasSuffix(".rb") }.count
                        } else if item.hasSuffix(".rb") {
                            count += 1
                        }
                    }
                }

                return count
            } catch {
                return nil
            }
        }
    }
}

// MARK: - Tap Remove

extension Velo.Tap {
    struct TapRemove: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a tap"
        )

        @Argument(help: "Tap name to remove (e.g., 'user/repo')")
        var tapName: String

        @Flag(help: "Skip confirmation prompt")
        var yes = false

        @Flag(help: "Remove tap globally instead of locally")
        var global = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let context = ProjectContext()

            // Determine if we should use local or global taps
            let useLocal = !global && context.isProjectContext

            // Get appropriate PathHelper
            let pathHelper = context.getPathHelper(preferLocal: useLocal)

            // Normalize tap name to match how taps are stored
            let normalizedTapName = normalizeTapName(tapName)
            let tapPath = pathHelper.tapsPath.appendingPathComponent(normalizedTapName)

            // Check if tap exists
            guard FileManager.default.fileExists(atPath: tapPath.path) else {
                logError("Tap '\(normalizedTapName)' is not installed")
                throw ExitCode.failure
            }

            // Prevent removal of core tap
            if normalizedTapName == "homebrew/core" {
                logError("Cannot remove homebrew/core tap - it's required for Velo to function")
                throw ExitCode.failure
            }

            // Confirmation
            if !yes {
                print("This will remove tap '\(normalizedTapName)' and all its formulae.")
                print("Packages installed from this tap will remain but won't receive updates.")
                print("")
                print("Continue? [y/N]: ", terminator: "")

                guard let input = readLine()?.lowercased(),
                      input == "y" || input == "yes" else {
                    print("Cancelled")
                    return
                }
            }

            logInfo("Removing tap \(normalizedTapName)...")

            // Remove the tap directory
            try FileManager.default.removeItem(at: tapPath)

            // Clean up empty parent directories
            let parentPath = tapPath.deletingLastPathComponent()
            if let items = try? FileManager.default.contentsOfDirectory(atPath: parentPath.path),
               items.isEmpty {
                try? FileManager.default.removeItem(at: parentPath)
            }

            // Update velo.json if in project context and using local taps
            if useLocal && context.isProjectContext {
                try await updateManifestWithTap(normalizedTapName, context: context, action: .remove)
            }

            Logger.shared.success("Tap '\(normalizedTapName)' removed successfully")

            print("")
            print("Note: Packages installed from this tap remain installed but won't receive updates.")
            print("To reinstall this tap: velo tap add \(normalizedTapName)")
        }

        private func normalizeTapName(_ input: String) -> String {
            let components = input.components(separatedBy: "/")
            guard components.count == 2 else {
                return input // Return as-is if not in user/repo format
            }

            let user = components[0]
            let repo = components[1]

            // Always use shortened version for display/storage
            let normalizedRepo = repo.hasPrefix("homebrew-") ? String(repo.dropFirst(9)) : repo
            return "\(user)/\(normalizedRepo)"
        }
    }
}

// MARK: - Tap Update

extension Velo.Tap {
    struct TapUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Update a specific tap or all taps"
        )

        @Argument(help: "Tap name to update (omit to update all taps)")
        var tapName: String?

        @Flag(help: "Update taps globally instead of locally")
        var global = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let context = ProjectContext()

            // Determine if we should use local or global taps
            let useLocal = !global && context.isProjectContext

            // Get appropriate PathHelper
            let pathHelper = context.getPathHelper(preferLocal: useLocal)
            let tapsPath = pathHelper.tapsPath

            if let specificTap = tapName {
                try await updateSpecificTap(specificTap, in: tapsPath)
            } else {
                try await updateAllTaps(in: tapsPath)
            }
        }

        private func updateSpecificTap(_ tapName: String, in tapsPath: URL) async throws {
            // Normalize tap name to match how taps are stored
            let normalizedTapName = normalizeTapName(tapName)
            let tapPath = tapsPath.appendingPathComponent(normalizedTapName)

            guard FileManager.default.fileExists(atPath: tapPath.path) else {
                logError("Tap '\(normalizedTapName)' is not installed")
                throw ExitCode.failure
            }

            logInfo("Updating tap \(normalizedTapName)...")
            try await updateTap(at: tapPath, name: normalizedTapName)
        }

        private func updateAllTaps(in tapsPath: URL) async throws {
            guard FileManager.default.fileExists(atPath: tapsPath.path) else {
                print("No taps installed")
                return
            }

            let organizations = try FileManager.default.contentsOfDirectory(atPath: tapsPath.path)
                .filter { !$0.hasPrefix(".") }

            var updatedTaps: [String] = []
            var failedTaps: [String] = []

            for org in organizations {
                let orgPath = tapsPath.appendingPathComponent(org)
                let repos = try FileManager.default.contentsOfDirectory(atPath: orgPath.path)
                    .filter { !$0.hasPrefix(".") }

                for repo in repos {
                    let tapName = "\(org)/\(repo)"
                    let tapPath = orgPath.appendingPathComponent(repo)

                    do {
                        logInfo("Updating tap \(tapName)...")
                        try await updateTap(at: tapPath, name: tapName)
                        updatedTaps.append(tapName)
                    } catch {
                        logWarning("Failed to update \(tapName): \(error)")
                        failedTaps.append(tapName)
                    }
                }
            }

            print("")
            Logger.shared.success("Updated \(updatedTaps.count) taps")

            if !failedTaps.isEmpty {
                logWarning("Failed to update \(failedTaps.count) taps: \(failedTaps.joined(separator: ", "))")
            }
        }

        private func updateTap(at path: URL, name: String) async throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["pull", "--ff-only"]
            process.currentDirectoryURL = path

            try await runProcess(process, description: "Updating \(name)")
            logInfo("✓ \(name) updated")
        }

        private func runProcess(_ process: Process, description: String) async throws {
            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let error = VeloError.processError(
                            command: "git",
                            exitCode: Int(process.terminationStatus),
                            description: "\(description) failed"
                        )
                        continuation.resume(throwing: error)
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        private func normalizeTapName(_ input: String) -> String {
            let components = input.components(separatedBy: "/")
            guard components.count == 2 else {
                return input // Return as-is if not in user/repo format
            }

            let user = components[0]
            let repo = components[1]

            // Always use shortened version for display/storage
            let normalizedRepo = repo.hasPrefix("homebrew-") ? String(repo.dropFirst(9)) : repo
            return "\(user)/\(normalizedRepo)"
        }
    }
}

// MARK: - Supporting Types

private struct TapInfo {
    let name: String
    let path: URL
    let url: String
    let formulaCount: Int?
}

private enum TapAction {
    case add
    case remove
}

// MARK: - Manifest Management

private func updateManifestWithTap(_ tapName: String, context: ProjectContext, action: TapAction) async throws {
    guard let manifestPath = context.manifestPath else {
        return // Not in project context
    }

    let manifestManager = VeloManifestManager()

    switch action {
    case .add:
        try manifestManager.addTap(tapName, to: manifestPath)
        logInfo("Added \(tapName) to velo.json taps")
    case .remove:
        try manifestManager.removeTap(tapName, from: manifestPath)
        logInfo("Removed \(tapName) from velo.json taps")
    }
}
