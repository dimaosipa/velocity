import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Uninstall a package"
        )

        @Argument(help: "The package to uninstall")
        var package: String

        @Option(help: "Uninstall specific version only")
        var version: String?

        @Flag(help: "Force uninstall without confirmation")
        var force = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let installer = Installer()
            let pathHelper = PathHelper.shared
            let receiptManager = ReceiptManager(pathHelper: pathHelper)

            // Ensure velo directories exist
            try pathHelper.ensureVeloDirectories()

            if let specificVersion = version {
                // Uninstall specific version
                OSLogger.shared.info("Uninstalling \(package) v\(specificVersion)...")

                // Check if this specific version is installed
                guard pathHelper.isSpecificVersionInstalled(package, version: specificVersion) else {
                    OSLogger.shared.error("Package '\(package)' version '\(specificVersion)' is not installed")
                    throw ExitCode.failure
                }
                
                // Check receipt to see if other packages depend on this
                if let receipt = try? receiptManager.loadReceipt(for: package, version: specificVersion),
                   !receipt.requestedBy.isEmpty {
                    // This package is a dependency of others
                    print("ℹ️  \(package) is a dependency of: \(receipt.requestedBy.joined(separator: ", "))")
                    
                    if receipt.symlinksCreated {
                        print("Removing symlinks only...")
                        
                        // Remove symlinks
                        let packageDir = pathHelper.packagePath(for: package, version: specificVersion)
                        try installer.removeSymlinksForPackage(package: package, version: specificVersion, packageDir: packageDir)
                        
                        // Update receipt
                        try receiptManager.updateReceipt(for: package, version: specificVersion) { receipt in
                            receipt.installedAs = .dependency
                            receipt.symlinksCreated = false
                        }
                        
                        OSLogger.shared.success("Removed symlinks for \(package) v\(specificVersion). Package remains installed as dependency.")
                        return
                    } else {
                        print("⚠️  Warning: This package is required by other packages. Uninstalling may break them.")
                        if !force {
                            print("\nAre you sure you want to uninstall \(package) v\(specificVersion)? [y/N]: ", terminator: "")
                            let input = readLine()?.lowercased()
                            if input != "y" && input != "yes" {
                                OSLogger.shared.info("Uninstall cancelled")
                                return
                            }
                        }
                    }
                }

                // Confirm uninstall unless forced (for non-dependency packages)
                if !force && (try? receiptManager.loadReceipt(for: package, version: specificVersion))?.requestedBy.isEmpty ?? true {
                    print("\nAre you sure you want to uninstall \(package) v\(specificVersion)? [y/N]: ", terminator: "")
                    let input = readLine()?.lowercased()

                    if input != "y" && input != "yes" {
                        OSLogger.shared.info("Uninstall cancelled")
                        return
                    }
                }

                do {
                    try installer.uninstallVersion(package: package, version: specificVersion)
                    
                    // Delete receipt
                    try? receiptManager.deleteReceipt(for: package, version: specificVersion)
                    
                    OSLogger.shared.success("\(package) v\(specificVersion) uninstalled successfully!")

                } catch {
                    OSLogger.shared.error("Uninstallation failed: \(error.localizedDescription)")
                    throw ExitCode.failure
                }

            } else {
                // Uninstall all versions
                OSLogger.shared.info("Uninstalling \(package)...")

                // Check if package is installed
                guard pathHelper.isPackageInstalled(package) else {
                    OSLogger.shared.error("Package '\(package)' is not installed")
                    throw ExitCode.failure
                }

                // Get installed versions
                let versions = pathHelper.installedVersions(for: package)
                
                // Check receipts for all versions to see if any are dependencies
                var isDependency = false
                var dependents: Set<String> = []
                
                for version in versions {
                    if let receipt = try? receiptManager.loadReceipt(for: package, version: version),
                       !receipt.requestedBy.isEmpty {
                        isDependency = true
                        dependents = dependents.union(receipt.requestedBy)
                    }
                }
                
                if isDependency {
                    print("ℹ️  \(package) is a dependency of: \(dependents.sorted().joined(separator: ", "))")
                    
                    // Check if any version has symlinks
                    var hasSymlinks = false
                    for version in versions {
                        if let receipt = try? receiptManager.loadReceipt(for: package, version: version),
                           receipt.symlinksCreated {
                            hasSymlinks = true
                            break
                        }
                    }
                    
                    if hasSymlinks {
                        print("Removing symlinks only...")
                        
                        // Remove symlinks for all versions
                        for version in versions {
                            let packageDir = pathHelper.packagePath(for: package, version: version)
                            try installer.removeSymlinksForPackage(package: package, version: version, packageDir: packageDir)
                            
                            // Update receipt
                            try? receiptManager.updateReceipt(for: package, version: version) { receipt in
                                receipt.installedAs = .dependency
                                receipt.symlinksCreated = false
                            }
                        }
                        
                        OSLogger.shared.success("Removed symlinks for \(package). Package remains installed as dependency.")
                        return
                    } else {
                        print("⚠️  Warning: This package is required by other packages. Uninstalling may break them.")
                    }
                }

                // Confirm uninstall unless forced
                if !force {
                    print("The following versions will be uninstalled:")
                    for version in versions {
                        print("  \(package) \(version)")
                    }

                    print("\nAre you sure you want to uninstall \(package)? [y/N]: ", terminator: "")
                    let input = readLine()?.lowercased()

                    if input != "y" && input != "yes" {
                        OSLogger.shared.info("Uninstall cancelled")
                        return
                    }
                }

                do {
                    try installer.uninstall(package: package)
                    
                    // Delete all receipts
                    for version in versions {
                        try? receiptManager.deleteReceipt(for: package, version: version)
                    }
                    
                    OSLogger.shared.success("\(package) uninstalled successfully!")

                } catch {
                    OSLogger.shared.error("Uninstallation failed: \(error.localizedDescription)")
                    throw ExitCode.failure
                }
            }

            // Show cleanup info
            OSLogger.shared.info("Run 'velo doctor' to check for any orphaned dependencies")
        }
    }
}
