import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct Clean: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Clean packages, cache, or both while keeping velo binary"
        )

        @Flag(help: "Remove all installed packages")
        var packages = false

        @Flag(help: "Clear download cache")
        var cache = false

        @Flag(help: "Remove packages and cache (equivalent to --packages --cache)")
        var all = false

        @Flag(help: "Skip confirmation prompts")
        var yes = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let startTime = Date()
            let pathHelper = PathHelper.shared
            let fileManager = FileManager.default

            // Validate flags
            if !packages && !cache && !all {
                OSLogger.shared.error("Please specify what to clean: --packages, --cache, or --all")
                print("")
                print("Usage:")
                print("  velo clean --packages     # Remove all installed packages")
                print("  velo clean --cache        # Clear download cache")
                print("  velo clean --all          # Remove packages and cache")
                throw ExitCode.failure
            }

            let shouldCleanPackages = packages || all
            let shouldCleanCache = cache || all

            // Confirm destructive operations
            if !yes {
                try confirmAction(cleanPackages: shouldCleanPackages, cleanCache: shouldCleanCache)
            }

            var cleanedItems: [String] = []

            // Clean packages
            if shouldCleanPackages {
                try cleanPackages(pathHelper: pathHelper, fileManager: fileManager)
                cleanedItems.append("packages")
            }

            // Clean cache
            if shouldCleanCache {
                try cleanCache(pathHelper: pathHelper, fileManager: fileManager)
                cleanedItems.append("cache")
            }

            let duration = Date().timeIntervalSince(startTime)
            print("✓ Cleaned \(cleanedItems.joined(separator: " and ")) in \(String(format: "%.1f", duration))s")

            if shouldCleanPackages {
                print("")
                print("All packages have been removed. You can install new packages with:")
                print("  velo install <package-name>")
            }
        }

        private func confirmAction(cleanPackages: Bool, cleanCache: Bool) throws {
            print("This will remove:")
            print("")

            if cleanPackages {
                print("All installed packages and their receipts:")
                let pathHelper = PathHelper.shared
                if FileManager.default.fileExists(atPath: pathHelper.cellarPath.path) {
                    let packages = try FileManager.default.contentsOfDirectory(atPath: pathHelper.cellarPath.path)
                        .filter { !$0.hasPrefix(".") }

                    if packages.isEmpty {
                        print("   (no packages currently installed)")
                    } else {
                        for package in packages.sorted() {
                            print("   • \(package)")
                        }
                    }
                } else {
                    print("   (no packages currently installed)")
                }
                print("")
            }

            if cleanCache {
                print("Download cache")
                let pathHelper = PathHelper.shared
                if FileManager.default.fileExists(atPath: pathHelper.cachePath.path) {
                    let cacheSize = try pathHelper.totalSize(of: pathHelper.cachePath)
                    let formatter = ByteCountFormatter()
                    formatter.countStyle = .binary
                    print("   Cache size: \(formatter.string(fromByteCount: cacheSize))")
                } else {
                    print("   (cache is empty)")
                }
                print("")
            }

            print("⚠️  This action cannot be undone.")
            print("")
            print("Continue? [y/N]: ", terminator: "")

            guard let input = readLine()?.lowercased() else {
                print("Cancelled")
                throw ExitCode.success
            }

            if input != "y" && input != "yes" {
                print("Cancelled")
                throw ExitCode.success
            }
        }

        private func cleanPackages(pathHelper: PathHelper, fileManager: FileManager) throws {
            OSLogger.shared.info("Removing all packages...")

            // Remove Cellar directory (installed packages)
            if fileManager.fileExists(atPath: pathHelper.cellarPath.path) {
                try fileManager.removeItem(at: pathHelper.cellarPath)
            }

            // Remove bin directory (symlinks)
            let binContents = try? fileManager.contentsOfDirectory(atPath: pathHelper.binPath.path)
            if let contents = binContents {
                for item in contents {
                    // Keep the velo binary itself
                    if item == "velo" {
                        continue
                    }

                    let itemPath = pathHelper.binPath.appendingPathComponent(item)
                    try fileManager.removeItem(at: itemPath)
                }
            }

            // Remove opt directory (package symlinks)
            if fileManager.fileExists(atPath: pathHelper.optPath.path) {
                try fileManager.removeItem(at: pathHelper.optPath)
            }

            // Remove receipts directory (installation metadata)
            if fileManager.fileExists(atPath: pathHelper.receiptsPath.path) {
                try fileManager.removeItem(at: pathHelper.receiptsPath)
            }

            // Recreate essential directories
            try pathHelper.ensureVeloDirectories()

            OSLogger.shared.info("All packages removed")
        }

        private func cleanCache(pathHelper: PathHelper, fileManager: FileManager) throws {
            OSLogger.shared.info("Clearing download cache...")

            if fileManager.fileExists(atPath: pathHelper.cachePath.path) {
                let contents = try fileManager.contentsOfDirectory(at: pathHelper.cachePath, includingPropertiesForKeys: nil)

                for file in contents {
                    try fileManager.removeItem(at: file)
                }
            }

            // Also clean temporary files older than 1 hour
            if fileManager.fileExists(atPath: pathHelper.tmpPath.path) {
                let contents = try fileManager.contentsOfDirectory(at: pathHelper.tmpPath, includingPropertiesForKeys: [.creationDateKey])
                let oneHourAgo = Date().addingTimeInterval(-3600)

                for file in contents {
                    if let attributes = try? file.resourceValues(forKeys: [.creationDateKey]),
                       let creationDate = attributes.creationDate,
                       creationDate < oneHourAgo {
                        try? fileManager.removeItem(at: file)
                    }
                }
            }

            OSLogger.shared.info("Cache cleared")
        }
    }
}
