import Foundation
import ArgumentParser
import VeloCore
import VeloFormula
import VeloSystem

extension Velo {
    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Search for packages"
        )

        @Argument(help: "Search term")
        var term: String

        @Flag(help: "Show detailed results")
        var verbose = false

        @Flag(help: "Search descriptions as well as names")
        var descriptions = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            // Ensure velo directories exist
            try PathHelper.shared.ensureVeloDirectories()

            logInfo("Searching for '\(term)'...")

            do {
                let results = try await searchPackages(term: term, includeDescriptions: descriptions)

                if results.isEmpty {
                    print("No packages found matching '\(term)'")
                    return
                }

                print("Search results for '\(term)':")
                print()

                for result in results {
                    let installedIndicator = PathHelper.shared.isPackageInstalled(result.name) ? " [installed]" : ""

                    if verbose {
                        print("==> \(result.name)\(installedIndicator)")
                        print("    \(result.description)")
                        print("    \(result.homepage)")

                        if result.hasCompatibleBottle {
                            print("    ✅ Apple Silicon compatible")
                        } else {
                            print("    ❌ No Apple Silicon bottles")
                        }

                        print()
                    } else {
                        print("\(result.name): \(result.description)\(installedIndicator)")
                    }
                }

                print("\(results.count) package(s) found")

            } catch {
                logError("Search failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        private func searchPackages(term: String, includeDescriptions: Bool) async throws -> [Formula] {
            // Use TapManager to search through actual taps
            let pathHelper = PathHelper.shared
            let tapManager = TapManager(pathHelper: pathHelper)

            // Build the formula index for fast searching
            try await tapManager.buildFullIndex()

            // Search for formula names matching the term
            let matchingNames = tapManager.searchFormulae(term, includeDescriptions: includeDescriptions)

            // Resolve names to actual Formula objects
            var results: [Formula] = []

            for name in matchingNames {
                do {
                    if let formula = try tapManager.findFormula(name) {
                        results.append(formula)
                    }
                } catch {
                    logVerbose("Failed to load formula \(name): \(error)")
                }
            }

            // Sort by relevance (exact matches first, then alphabetical)
            return results.sorted { formula1, formula2 in
                let exact1 = formula1.name.localizedCaseInsensitiveCompare(term) == .orderedSame
                let exact2 = formula2.name.localizedCaseInsensitiveCompare(term) == .orderedSame

                if exact1 && !exact2 { return true }
                if !exact1 && exact2 { return false }

                return formula1.name.localizedCompare(formula2.name) == .orderedAscending
            }
        }
    }
}
