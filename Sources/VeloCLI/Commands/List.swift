import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List installed packages"
        )
        
        @Flag(help: "Show versions")
        var versions = false
        
        @Flag(help: "Show sizes")
        var sizes = false
        
        @Option(help: "Filter by package name")
        var filter: String?
        
        @Flag(name: .shortAndLong, help: "List all available packages (not just installed)")
        var all = false
        
        func run() throws {
            let pathHelper = PathHelper.shared
            let cellarPath = pathHelper.cellarPath
            
            if all {
                // This would list all available packages from taps
                // For now, just show a message
                print("Available packages:")
                print("(Tap support not yet implemented)")
                return
            }
            
            // Check if cellar directory exists
            guard FileManager.default.fileExists(atPath: cellarPath.path) else {
                print("No packages installed")
                return
            }
            
            do {
                let packages = try FileManager.default.contentsOfDirectory(atPath: cellarPath.path)
                    .filter { !$0.hasPrefix(".") }
                    .sorted()
                
                // Apply filter if specified
                let filteredPackages = filter.map { filterTerm in
                    packages.filter { $0.localizedCaseInsensitiveContains(filterTerm) }
                } ?? packages
                
                if filteredPackages.isEmpty {
                    if let filterTerm = filter {
                        print("No installed packages match '\(filterTerm)'")
                    } else {
                        print("No packages installed")
                    }
                    return
                }
                
                print("Installed packages:")
                
                for package in filteredPackages {
                    let packageVersions = pathHelper.installedVersions(for: package)
                    
                    if versions {
                        for version in packageVersions {
                            var line = "\(package) \(version)"
                            
                            if sizes {
                                let packageDir = pathHelper.packagePath(for: package, version: version)
                                if let size = try? pathHelper.totalSize(of: packageDir) {
                                    let formatter = ByteCountFormatter()
                                    formatter.countStyle = .binary
                                    line += " (\(formatter.string(fromByteCount: size)))"
                                }
                            }
                            
                            print("  \(line)")
                        }
                    } else {
                        var line = package
                        
                        if packageVersions.count > 1 {
                            line += " (\(packageVersions.count) versions)"
                        } else if let version = packageVersions.first {
                            line += " \(version)"
                        }
                        
                        if sizes {
                            var totalSize: Int64 = 0
                            for version in packageVersions {
                                let packageDir = pathHelper.packagePath(for: package, version: version)
                                if let size = try? pathHelper.totalSize(of: packageDir) {
                                    totalSize += size
                                }
                            }
                            
                            let formatter = ByteCountFormatter()
                            formatter.countStyle = .binary
                            line += " (\(formatter.string(fromByteCount: totalSize)))"
                        }
                        
                        print("  \(line)")
                    }
                }
                
                // Summary
                print("\n\(filteredPackages.count) package(s) installed")
                
                if sizes {
                    let totalSize = try calculateTotalSize(for: filteredPackages, pathHelper: pathHelper)
                    let formatter = ByteCountFormatter()
                    formatter.countStyle = .binary
                    print("Total size: \(formatter.string(fromByteCount: totalSize))")
                }
                
            } catch {
                logError("Failed to list packages: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
        
        private func calculateTotalSize(for packages: [String], pathHelper: PathHelper) throws -> Int64 {
            var totalSize: Int64 = 0
            
            for package in packages {
                let versions = pathHelper.installedVersions(for: package)
                for version in versions {
                    let packageDir = pathHelper.packagePath(for: package, version: version)
                    if let size = try? pathHelper.totalSize(of: packageDir) {
                        totalSize += size
                    }
                }
            }
            
            return totalSize
        }
    }
}