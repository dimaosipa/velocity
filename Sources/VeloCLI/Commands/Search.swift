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
            // For now, search through our test fixtures
            let fixturesPath = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Tests")
                .appendingPathComponent("Fixtures")
                .appendingPathComponent("Formulae")
            
            var results: [Formula] = []
            let parser = FormulaParser()
            
            if FileManager.default.fileExists(atPath: fixturesPath.path) {
                let formulaFiles = try FileManager.default.contentsOfDirectory(atPath: fixturesPath.path)
                    .filter { $0.hasSuffix(".rb") }
                
                for file in formulaFiles {
                    let formulaPath = fixturesPath.appendingPathComponent(file)
                    let formulaName = String(file.dropLast(3)) // Remove .rb
                    
                    // Check if name matches
                    if formulaName.localizedCaseInsensitiveContains(term) {
                        do {
                            let content = try String(contentsOf: formulaPath)
                            let formula = try parser.parse(rubyContent: content, formulaName: formulaName)
                            results.append(formula)
                        } catch {
                            logVerbose("Failed to parse \(formulaName): \(error)")
                        }
                        continue
                    }
                    
                    // Check description if requested
                    if includeDescriptions {
                        do {
                            let content = try String(contentsOf: formulaPath)
                            let formula = try parser.parse(rubyContent: content, formulaName: formulaName)
                            
                            if formula.description.localizedCaseInsensitiveContains(term) {
                                results.append(formula)
                            }
                        } catch {
                            logVerbose("Failed to parse \(formulaName): \(error)")
                        }
                    }
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