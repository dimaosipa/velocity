import Foundation
import ArgumentParser
import VeloCore
import VeloFormula
import VeloSystem

extension Velo {
    struct Analyze: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Analyze formulas and installation patterns",
            subcommands: [PostInstall.self]
        )
    }
}

extension Velo.Analyze {
    struct PostInstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Extract and analyze post_install scripts from installed packages"
        )

        @Flag(help: "Show verbose output including script contents")
        var verbose = false

        @Flag(help: "Include packages without post_install scripts in report")
        var includeEmpty = false

        @Option(help: "Limit analysis to first N packages (for testing)")
        var limit: Int?

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let context = ProjectContext()
            let pathHelper = context.getPathHelper(preferLocal: false) // Always use global for analysis

            OSLogger.shared.info("🔍 Analyzing post_install scripts from installed packages...")

            // Ensure analysis directory exists
            let analysisDir = pathHelper.veloHome.appendingPathComponent("analysis")
            let postInstallDir = analysisDir.appendingPathComponent("post-install")
            try pathHelper.ensureDirectoryExists(at: analysisDir)
            try pathHelper.ensureDirectoryExists(at: postInstallDir)

            // Get all installed packages
            guard FileManager.default.fileExists(atPath: pathHelper.cellarPath.path) else {
                OSLogger.shared.info("No packages installed to analyze")
                return
            }

            var packages = try FileManager.default.contentsOfDirectory(atPath: pathHelper.cellarPath.path)
                .filter { !$0.hasPrefix(".") }
                .sorted()

            // Apply limit if specified
            if let limit = limit {
                packages = Array(packages.prefix(limit))
            }

            if packages.isEmpty {
                OSLogger.shared.info("No packages installed to analyze")
                return
            }

            OSLogger.shared.info("📦 Found \(packages.count) installed packages")

            var analysisResults: [PackageAnalysis] = []
            let formulaCache = FormulaCache(pathHelper: pathHelper)

            for (index, packageName) in packages.enumerated() {
                if verbose {
                    OSLogger.shared.info("Analyzing \(index + 1)/\(packages.count): \(packageName)")
                }
                do {
                    if let analysis = try await analyzePackage(packageName, formulaCache: formulaCache, postInstallDir: postInstallDir) {
                        analysisResults.append(analysis)

                        if verbose {
                            OSLogger.shared.info("✅ \(packageName): \(analysis.hasPostInstall ? "has post_install" : "no post_install")")
                            if analysis.hasPostInstall && verbose {
                                print("   Script preview: \(String(analysis.scriptPreview.prefix(100)))...")
                            }
                        }
                    }
                } catch {
                    OSLogger.shared.warning("⚠️ Failed to analyze \(packageName): \(error.localizedDescription)")
                }
            }

            // Generate summary report
            try generateSummaryReport(results: analysisResults, outputDir: analysisDir)

            // Show results
            let withPostInstall = analysisResults.filter { $0.hasPostInstall }
            let withoutPostInstall = analysisResults.filter { !$0.hasPostInstall }

            OSLogger.shared.info("")
            OSLogger.shared.info("📊 Analysis Results:")
            OSLogger.shared.info("   📄 Packages with post_install: \(withPostInstall.count)")
            OSLogger.shared.info("   📄 Packages without post_install: \(withoutPostInstall.count)")
            OSLogger.shared.info("   📄 Total analyzed: \(analysisResults.count)")

            if !withPostInstall.isEmpty {
                OSLogger.shared.info("")
                OSLogger.shared.info("📝 Packages with post_install scripts:")
                for result in withPostInstall.prefix(10) {
                    OSLogger.shared.info("   - \(result.packageName) (\(result.scriptLines) lines)")
                }
                if withPostInstall.count > 10 {
                    OSLogger.shared.info("   ... and \(withPostInstall.count - 10) more")
                }
            }

            if includeEmpty && !withoutPostInstall.isEmpty {
                OSLogger.shared.info("")
                OSLogger.shared.info("📝 Packages without post_install scripts:")
                for result in withoutPostInstall.prefix(10) {
                    OSLogger.shared.info("   - \(result.packageName)")
                }
                if withoutPostInstall.count > 10 {
                    OSLogger.shared.info("   ... and \(withoutPostInstall.count - 10) more")
                }
            }

            OSLogger.shared.info("")
            OSLogger.shared.info("💾 Analysis saved to: \(postInstallDir.path)")
            OSLogger.shared.info("📋 Summary report: \(analysisDir.appendingPathComponent("post-install-summary.txt").path)")
        }

        private func analyzePackage(_ packageName: String, formulaCache: FormulaCache, postInstallDir: URL) async throws -> PackageAnalysis? {
            // Try to load formula from cache first
            if let formula = try formulaCache.get(packageName) {
                return createAnalysis(for: packageName, formula: formula, postInstallDir: postInstallDir)
            }

            // If not in cache, try to load from tap files directly
            let pathHelper = PathHelper.shared
            let tapsDir = pathHelper.tapsPath

            // Look for formula file in taps (homebrew/core format with letter directories)
            let firstLetter = String(packageName.lowercased().prefix(1))
            let possiblePaths = [
                tapsDir.appendingPathComponent("homebrew/core/Formula/\(firstLetter)/\(packageName).rb"),
                tapsDir.appendingPathComponent("homebrew/core/Formula/\(firstLetter)/\(packageName.lowercased()).rb"),
                // Fallback to old flat structure
                tapsDir.appendingPathComponent("homebrew/core/Formula/\(packageName).rb"),
                tapsDir.appendingPathComponent("homebrew/core/Formula/\(packageName.lowercased()).rb")
            ]

            for formulaPath in possiblePaths {
                if FileManager.default.fileExists(atPath: formulaPath.path) {
                    do {
                        let formulaContent = try String(contentsOf: formulaPath, encoding: String.Encoding.utf8)
                        let parser = FormulaParser()
                        let formula = try parser.parse(rubyContent: formulaContent, formulaName: packageName)

                        // Cache the parsed formula for future use
                        try formulaCache.set(formula)

                        return createAnalysis(for: packageName, formula: formula, postInstallDir: postInstallDir)
                    } catch {
                        // Continue to next path
                        continue
                    }
                }
            }

            return nil
        }

        private func createAnalysis(for packageName: String, formula: Formula, postInstallDir: URL) -> PackageAnalysis? {
            let analysis = PackageAnalysis(
                packageName: packageName,
                hasPostInstall: formula.postInstallScript != nil,
                scriptContent: formula.postInstallScript ?? "",
                scriptLines: formula.postInstallScript?.components(separatedBy: CharacterSet.newlines).count ?? 0,
                scriptPreview: String((formula.postInstallScript ?? "").prefix(200))
            )

            // Save script to file if it exists
            if let script = formula.postInstallScript, !script.isEmpty {
                do {
                    let scriptFile = postInstallDir.appendingPathComponent("\(packageName).rb")
                    let scriptContent = """
# post_install script for \(packageName)
# Extracted on \(Date())
# Package version: \(formula.version)

\(script)
"""
                    try scriptContent.write(to: scriptFile, atomically: true, encoding: String.Encoding.utf8)
                } catch {
                    // Continue even if we can't write the file
                }
            }

            return analysis
        }

        private func generateSummaryReport(results: [PackageAnalysis], outputDir: URL) throws {
            let summaryFile = outputDir.appendingPathComponent("post-install-summary.txt")

            let withPostInstall = results.filter { $0.hasPostInstall }
            let withoutPostInstall = results.filter { !$0.hasPostInstall }

            var summary = """
# Post-Install Script Analysis Report
Generated on: \(Date())

## Summary Statistics
- Total packages analyzed: \(results.count)
- Packages with post_install: \(withPostInstall.count) (\(Int(Double(withPostInstall.count) / Double(results.count) * 100))%)
- Packages without post_install: \(withoutPostInstall.count) (\(Int(Double(withoutPostInstall.count) / Double(results.count) * 100))%)

## Packages with post_install scripts:

"""

            for result in withPostInstall.sorted(by: { $0.scriptLines > $1.scriptLines }) {
                summary += "- \(result.packageName): \(result.scriptLines) lines\n"
                if !result.scriptPreview.isEmpty {
                    summary += "  Preview: \(result.scriptPreview.replacingOccurrences(of: "\n", with: " "))\n"
                }
                summary += "\n"
            }

            if !withoutPostInstall.isEmpty {
                summary += "\n## Packages without post_install scripts:\n\n"
                for result in withoutPostInstall {
                    summary += "- \(result.packageName)\n"
                }
            }

            summary += """

## Analysis Notes
- Scripts are saved as individual .rb files in the post-install directory
- Each script includes the original Ruby code from the formula
- Review these scripts to determine if Velo needs post_install support
- Common patterns: directory creation, symlinks, service setup, database initialization

"""

            try summary.write(to: summaryFile, atomically: true, encoding: String.Encoding.utf8)
        }
    }
}

private struct PackageAnalysis {
    let packageName: String
    let hasPostInstall: Bool
    let scriptContent: String
    let scriptLines: Int
    let scriptPreview: String
}
