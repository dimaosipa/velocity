import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct Switch: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Switch the default version of an installed package"
        )
        
        @Argument(help: "The package name")
        var package: String
        
        @Argument(help: "The version to switch to")
        var version: String
        
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
            let pathHelper = PathHelper.shared
            
            logInfo("Switching \(package) default version to \(version)...")
            
            // Check if the specified version is installed
            guard pathHelper.isSpecificVersionInstalled(package, version: version) else {
                logError("Package '\(package)' version '\(version)' is not installed")
                print("\nAvailable versions:")
                let availableVersions = pathHelper.installedVersions(for: package)
                if availableVersions.isEmpty {
                    print("  (none)")
                } else {
                    for availableVersion in availableVersions {
                        print("  \(package) \(availableVersion)")
                    }
                }
                throw ExitCode.failure
            }
            
            do {
                try pathHelper.setDefaultVersion(for: package, version: version)
                Logger.shared.success("Default version for \(package) switched to \(version)")
                
                // Show which binaries are now available
                let packageDir = pathHelper.packagePath(for: package, version: version)
                let binDir = packageDir.appendingPathComponent("bin")
                
                if FileManager.default.fileExists(atPath: binDir.path) {
                    let binaries = try FileManager.default.contentsOfDirectory(atPath: binDir.path)
                        .filter { !$0.hasPrefix(".") }
                    
                    if !binaries.isEmpty {
                        print("\nAvailable binaries:")
                        for binary in binaries {
                            print("  \(binary) -> \(package) v\(version)")
                        }
                    }
                }
                
            } catch {
                logError("Failed to switch version: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
}