import Foundation
import ArgumentParser
import VeloCore
import VeloSystem

extension Velo {
    struct InstallSelf: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Install velo binary to ~/.velo/bin and add to PATH"
        )
        
        @Flag(help: "Skip adding to PATH (for CI/automated installs)")
        var skipPath = false
        
        @Flag(help: "Force reinstall even if already installed")
        var force = false
        
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
            let fileManager = FileManager.default
            
            // Ensure velo directories exist
            try pathHelper.ensureVeloDirectories()
            
            // Get current binary path
            guard let currentBinaryPath = getCurrentBinaryPath() else {
                throw VeloError.installationFailed(
                    package: "velo",
                    reason: "Could not determine current binary location"
                )
            }
            
            let targetPath = pathHelper.binPath.appendingPathComponent("velo")
            
            // Check if already installed
            if fileManager.fileExists(atPath: targetPath.path) && !force {
                // Check if it's the same version
                if try isSameBinary(currentBinaryPath, targetPath) {
                    logInfo("Velo is already installed at \(targetPath.path)")
                    
                    if !skipPath {
                        try updateShellProfiles()
                    }
                    
                    Logger.shared.success("Velo installation verified!")
                    showNextSteps()
                    return
                } else {
                    logInfo("Updating existing velo installation...")
                }
            }
            
            // Copy binary
            logInfo("Installing velo to \(targetPath.path)...")
            
            // Remove existing if present
            if fileManager.fileExists(atPath: targetPath.path) {
                try fileManager.removeItem(at: targetPath)
            }
            
            try fileManager.copyItem(at: currentBinaryPath, to: targetPath)
            
            // Make executable
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try fileManager.setAttributes(attributes, ofItemAtPath: targetPath.path)
            
            Logger.shared.success("Velo binary installed successfully!")
            
            // Update shell profiles
            if !skipPath {
                try updateShellProfiles()
            }
            
            showNextSteps()
        }
        
        private func getCurrentBinaryPath() -> URL? {
            let currentPath = CommandLine.arguments[0]
            
            // If it's a relative path, make it absolute
            if currentPath.hasPrefix("./") || !currentPath.hasPrefix("/") {
                let currentDir = FileManager.default.currentDirectoryPath
                let fullPath = URL(fileURLWithPath: currentDir).appendingPathComponent(currentPath)
                return fullPath.standardized
            }
            
            return URL(fileURLWithPath: currentPath)
        }
        
        private func isSameBinary(_ source: URL, _ target: URL) throws -> Bool {
            // Compare file sizes and modification dates as a simple check
            let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
            let targetAttributes = try FileManager.default.attributesOfItem(atPath: target.path)
            
            let sourceSize = sourceAttributes[.size] as? Int64 ?? 0
            let targetSize = targetAttributes[.size] as? Int64 ?? 0
            
            let sourceDate = sourceAttributes[.modificationDate] as? Date ?? Date.distantPast
            let targetDate = targetAttributes[.modificationDate] as? Date ?? Date.distantPast
            
            return sourceSize == targetSize && abs(sourceDate.timeIntervalSince(targetDate)) < 1.0
        }
        
        private func updateShellProfiles() throws {
            let pathHelper = PathHelper.shared
            let veloPath = pathHelper.binPath.path
            let exportLine = "export PATH=\"\(veloPath):$PATH\""
            
            var profilesUpdated: [String] = []
            var profilesAlreadyConfigured: [String] = []
            
            // List of shell profile files to check/update
            let profileFiles = [
                ("~/.zshrc", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")),
                ("~/.bashrc", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bashrc")),
                ("~/.bash_profile", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".bash_profile")),
                ("~/.profile", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".profile"))
            ]
            
            for (displayName, profilePath) in profileFiles {
                if FileManager.default.fileExists(atPath: profilePath.path) {
                    let content = try String(contentsOf: profilePath)
                    
                    // Check if already configured
                    if content.contains(veloPath) || content.contains("$HOME/.velo/bin") {
                        profilesAlreadyConfigured.append(displayName)
                        continue
                    }
                    
                    // Add PATH export
                    var newContent = content
                    if !newContent.hasSuffix("\n") && !newContent.isEmpty {
                        newContent += "\n"
                    }
                    newContent += "\n# Added by Velo installer\n\(exportLine)\n"
                    
                    try newContent.write(to: profilePath, atomically: true, encoding: .utf8)
                    profilesUpdated.append(displayName)
                }
            }
            
            // Report results
            if !profilesUpdated.isEmpty {
                logInfo("Added ~/.velo/bin to PATH in: \(profilesUpdated.joined(separator: ", "))")
            }
            
            if !profilesAlreadyConfigured.isEmpty {
                logInfo("PATH already configured in: \(profilesAlreadyConfigured.joined(separator: ", "))")
            }
            
            if profilesUpdated.isEmpty && profilesAlreadyConfigured.isEmpty {
                logWarning("No shell profile files found. You may need to manually add to PATH:")
                print("  echo '\(exportLine)' >> ~/.zshrc")
            }
        }
        
        private func showNextSteps() {
            print("")
            print("🎉 Velo is now installed!")
            print("")
            print("Next steps:")
            print("  1. Restart your terminal or run: source ~/.zshrc")
            print("  2. Verify installation: velo doctor")
            print("  3. Install your first package: velo install wget")
            print("")
            print("To uninstall: velo uninstall-self")
        }
    }
}