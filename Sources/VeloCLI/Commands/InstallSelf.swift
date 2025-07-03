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

        @Flag(help: "Create symlink instead of copying binary (useful for development)")
        var symlink = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
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
                // Check if it's the same installation type and version
                let isCurrentlySymlink = try isSymlink(targetPath)
                if isCurrentlySymlink == symlink {
                    var isSameVersion = false
                    if symlink {
                        // For symlinks, we just check that both are symlinks
                        isSameVersion = true
                    } else {
                        // For copies, check if it's the same binary
                        isSameVersion = try isSameBinary(currentBinaryPath, targetPath)
                    }

                    if isSameVersion {
                        let installType = symlink ? "symlinked" : "installed"
                        OSLogger.shared.info("Velo is already \(installType) at \(targetPath.path)")

                        if !skipPath {
                            try updateShellProfiles()
                        }

                        OSLogger.shared.success("Velo installation verified!")
                        showNextSteps()
                        return
                    }
                }

                let oldType = isCurrentlySymlink ? "symlink" : "copy"
                let newType = symlink ? "symlink" : "copy"
                OSLogger.shared.info("Updating velo installation (\(oldType) → \(newType))...")
            }

            // Install binary (copy or symlink)
            let installType = symlink ? "Symlinking" : "Installing"
            OSLogger.shared.info("\(installType) velo to \(targetPath.path)...")

            // Remove existing if present
            if fileManager.fileExists(atPath: targetPath.path) {
                try fileManager.removeItem(at: targetPath)
            }

            if symlink {
                // Create symlink
                try fileManager.createSymbolicLink(at: targetPath, withDestinationURL: currentBinaryPath)
                OSLogger.shared.success("Velo binary symlinked successfully!")
            } else {
                // Copy binary
                try fileManager.copyItem(at: currentBinaryPath, to: targetPath)

                // Make executable
                let attributes = [FileAttributeKey.posixPermissions: 0o755]
                try fileManager.setAttributes(attributes, ofItemAtPath: targetPath.path)

                OSLogger.shared.success("Velo binary installed successfully!")
            }

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

        private func isSymlink(_ url: URL) throws -> Bool {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileType = attributes[.type] as? FileAttributeType
            return fileType == .typeSymbolicLink
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
                    
                    // Parse and update PATH more intelligently
                    let updatedContent = try updatePathInShellProfile(content: content, veloPath: veloPath)
                    
                    if updatedContent != content {
                        try updatedContent.write(to: profilePath, atomically: true, encoding: .utf8)
                        profilesUpdated.append(displayName)
                    } else {
                        profilesAlreadyConfigured.append(displayName)
                    }
                }
            }

            // Report results
            if !profilesUpdated.isEmpty {
                OSLogger.shared.info("Added ~/.velo/bin to PATH in: \(profilesUpdated.joined(separator: ", "))")
            }

            if !profilesAlreadyConfigured.isEmpty {
                OSLogger.shared.info("PATH already configured in: \(profilesAlreadyConfigured.joined(separator: ", "))")
            }

            if profilesUpdated.isEmpty && profilesAlreadyConfigured.isEmpty {
                OSLogger.shared.warning("No shell profile files found. You may need to manually add to PATH:")
                print("  echo '\(exportLine)' >> ~/.zshrc")
            }
        }

        private func updatePathInShellProfile(content: String, veloPath: String) throws -> String {
            let lines = content.components(separatedBy: .newlines)
            var updatedLines: [String] = []
            var foundVeloPath = false
            
            // First pass: analyze existing PATH exports and remove old Velo entries
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                
                // Skip Velo installer comment lines
                if trimmedLine.contains("# Added by Velo installer") {
                    continue
                }
                
                // Check for PATH export lines
                if trimmedLine.hasPrefix("export PATH=") || trimmedLine.hasPrefix("PATH=") {
                    // Parse PATH to see if it contains Velo path
                    if let pathValue = extractPathValue(from: trimmedLine) {
                        let pathComponents = pathValue.components(separatedBy: ":")
                        
                        // Check if Velo path is present
                        let veloPathVariants = [veloPath, "$HOME/.velo/bin", "~/.velo/bin"]
                        let hasVeloPath = pathComponents.contains { component in
                            veloPathVariants.contains(component)
                        }
                        
                        if hasVeloPath {
                            foundVeloPath = true
                            
                            // Remove existing Velo paths and reconstruct
                            let filteredComponents = pathComponents.filter { component in
                                !veloPathVariants.contains(component)
                            }
                            
                            // Add Velo path at the beginning
                            let newPathComponents = [veloPath] + filteredComponents
                            let newPathValue = newPathComponents.joined(separator: ":")
                            
                            // Reconstruct the export line
                            if trimmedLine.hasPrefix("export PATH=") {
                                updatedLines.append("export PATH=\"\(newPathValue)\"")
                            } else {
                                updatedLines.append("PATH=\"\(newPathValue)\"")
                            }
                        } else {
                            // No Velo path in this export, keep as is
                            updatedLines.append(line)
                        }
                    } else {
                        // Couldn't parse PATH value, keep as is
                        updatedLines.append(line)
                    }
                } else {
                    // Not a PATH export line, keep as is
                    updatedLines.append(line)
                }
            }
            
            // If no PATH export with Velo was found, add it
            if !foundVeloPath {
                var newContent = updatedLines.joined(separator: "\n")
                if !newContent.hasSuffix("\n") && !newContent.isEmpty {
                    newContent += "\n"
                }
                newContent += "\n# Added by Velo installer\nexport PATH=\"\(veloPath):$PATH\"\n"
                return newContent
            }
            
            // If Velo path was found and properly positioned, return updated content
            return updatedLines.joined(separator: "\n")
        }
        
        private func extractPathValue(from line: String) -> String? {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Handle both export PATH="..." and PATH="..." formats
            let patterns = [
                #"^export PATH="(.+)"$"#,
                #"^export PATH=(.+)$"#,
                #"^PATH="(.+)"$"#,
                #"^PATH=(.+)$"#
            ]
            
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: trimmedLine, options: [], range: NSRange(location: 0, length: trimmedLine.count)) {
                    if let range = Range(match.range(at: 1), in: trimmedLine) {
                        return String(trimmedLine[range])
                    }
                }
            }
            
            return nil
        }

        private func showNextSteps() {
            print("")
            let installType = symlink ? "symlinked" : "installed"
            print("🎉 Velo is now \(installType)!")
            print("")
            print("Next steps:")
            print("  1. Restart your terminal or run: source ~/.zshrc")
            print("  2. Verify installation: velo doctor")
            print("  3. Install your first package: velo install wget")
            print("")
            if symlink {
                print("Note: Velo is symlinked for development. Changes to the binary will be reflected immediately.")
                print("")
            }
            print("To uninstall: velo uninstall-self")
        }
    }
}
