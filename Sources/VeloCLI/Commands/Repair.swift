import Foundation
import ArgumentParser
import VeloCore
import VeloFormula
import VeloSystem

extension Velo {
    struct Repair: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Repair existing package installations"
        )

        @Argument(help: "The package to repair (optional, repairs all if not specified)")
        var package: String?

        @Flag(help: "Show what would be repaired without making changes")
        var dryRun = false

        @Flag(help: "Force repair even if no issues are detected")
        var force = false
        
        @Flag(help: "Also check and fix PATH configuration")
        var fixPath = false

        func run() throws {
            try runAsyncAndWait {
                try await self.runAsync()
            }
        }

        private func runAsync() async throws {
            let context = ProjectContext()
            let pathHelper = context.getPathHelper(preferLocal: false) // Always use global for repair

            // Check and fix PATH configuration if requested
            if fixPath {
                try checkAndFixPathConfiguration(pathHelper: pathHelper)
            }
            
            // Check and fix hardcoded wrapper scripts
            try await checkAndFixWrapperScripts(pathHelper: pathHelper)

            if let packageName = package {
                // Repair specific package
                try await repairPackage(packageName, pathHelper: pathHelper)
            } else {
                // Repair all packages
                try await repairAllPackages(pathHelper: pathHelper)
            }
        }

        private func repairPackage(_ packageName: String, pathHelper: PathHelper) async throws {
            guard pathHelper.isPackageInstalled(packageName) else {
                OSLogger.shared.error("Package '\(packageName)' is not installed")
                throw ExitCode.failure
            }

            let versions = pathHelper.installedVersions(for: packageName)
            OSLogger.shared.info("Repairing \(packageName) (\(versions.count) version(s))...")

            for version in versions {
                try await repairPackageVersion(packageName, version: version, pathHelper: pathHelper)
            }

            OSLogger.shared.success("\(packageName) repair completed!")
        }

        private func repairAllPackages(pathHelper: PathHelper) async throws {
            let cellarPath = pathHelper.cellarPath
            guard FileManager.default.fileExists(atPath: cellarPath.path) else {
                OSLogger.shared.info("No packages installed to repair")
                return
            }

            let packages = try FileManager.default.contentsOfDirectory(atPath: cellarPath.path)
                .filter { !$0.hasPrefix(".") }
                .sorted()

            if packages.isEmpty {
                OSLogger.shared.info("No packages installed to repair")
                return
            }

            OSLogger.shared.info("Scanning \(packages.count) packages for repair issues...")

            var repairedCount = 0
            var issuesFound = 0

            for packageName in packages {
                let versions = pathHelper.installedVersions(for: packageName)
                
                for version in versions {
                    let (hasIssues, fixed) = try await repairPackageVersion(
                        packageName, 
                        version: version, 
                        pathHelper: pathHelper
                    )
                    
                    if hasIssues {
                        issuesFound += 1
                        if fixed {
                            repairedCount += 1
                        }
                    }
                }
            }

            if issuesFound == 0 {
                OSLogger.shared.success("✅ All packages are healthy - no repairs needed!")
            } else {
                if dryRun {
                    OSLogger.shared.info("Found \(issuesFound) packages with issues that could be repaired")
                } else {
                    OSLogger.shared.success("✅ Repair completed: \(repairedCount)/\(issuesFound) packages fixed")
                }
            }
        }

        @discardableResult
        private func repairPackageVersion(
            _ packageName: String, 
            version: String, 
            pathHelper: PathHelper
        ) async throws -> (hasIssues: Bool, fixed: Bool) {
            let packageDir = pathHelper.packagePath(for: packageName, version: version)
            let packageDisplayName = "\(packageName) \(version)"

            // Find all files that need repair (binaries, scripts, etc.)
            let filesToRepair = try await findAllFilesNeedingRepair(in: packageDir)

            if filesToRepair.isEmpty {
                if force {
                    OSLogger.shared.info("  \(packageDisplayName): No issues found (forced repair skipped)")
                }
                return (hasIssues: false, fixed: false)
            }

            OSLogger.shared.info("  \(packageDisplayName): Found \(filesToRepair.count) files with unreplaced placeholders")

            if dryRun {
                for file in filesToRepair {
                    let relativePath = file.url.path.replacingOccurrences(of: packageDir.path + "/", with: "")
                    let typeDescription = file.type == .binary ? "binary" : file.type == .script ? "script" : "Python shebang"
                    OSLogger.shared.info("    - \(relativePath) (\(typeDescription))")
                }
                return (hasIssues: true, fixed: false)
            }

            // Perform the repair
            var fixedCount = 0
            let installer = Installer(pathHelper: pathHelper)

            for file in filesToRepair {
                do {
                    let relativePath = file.url.path.replacingOccurrences(of: packageDir.path + "/", with: "")
                    let typeDescription = file.type == .binary ? "binary" : file.type == .script ? "script" : "Python shebang"
                    OSLogger.shared.info("    Repairing \(relativePath) (\(typeDescription))...")
                    
                    switch file.type {
                    case .binary:
                        try await installer.repairBinaryLibraryPaths(binaryPath: file.url)
                    case .script:
                        try await repairScriptFile(file.url, pathHelper: pathHelper)
                    case .pythonShebang:
                        try await repairPythonShebang(file.url)
                    }
                    
                    fixedCount += 1
                } catch {
                    OSLogger.shared.warning("    Failed to repair \(file.url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            if fixedCount == filesToRepair.count {
                OSLogger.shared.info("  ✅ \(packageDisplayName): All \(fixedCount) files repaired successfully")
                return (hasIssues: true, fixed: true)
            } else {
                OSLogger.shared.warning("  ⚠️ \(packageDisplayName): \(fixedCount)/\(filesToRepair.count) files repaired")
                return (hasIssues: true, fixed: false)
            }
        }

        private func findFilesNeedingRepair(in packageDir: URL) throws -> [URL] {
            var filesToRepair: [URL] = []
            let fileManager = FileManager.default

            // Check binaries in bin/
            let binDir = packageDir.appendingPathComponent("bin")
            if fileManager.fileExists(atPath: binDir.path) {
                let binaries = try fileManager.contentsOfDirectory(atPath: binDir.path)
                    .filter { !$0.hasPrefix(".") }
                
                for binary in binaries {
                    let binaryPath = binDir.appendingPathComponent(binary)
                    if try fileNeedsRepair(binaryPath) {
                        filesToRepair.append(binaryPath)
                    }
                }
            }

            // Check dylib files in lib/
            let libDir = packageDir.appendingPathComponent("lib")
            if fileManager.fileExists(atPath: libDir.path) {
                let libraries = try fileManager.contentsOfDirectory(atPath: libDir.path)
                    .filter { $0.hasSuffix(".dylib") }
                
                for library in libraries {
                    let libraryPath = libDir.appendingPathComponent(library)
                    if try fileNeedsRepair(libraryPath) {
                        filesToRepair.append(libraryPath)
                    }
                }
            }

            // Check framework binaries (especially for Python, Node.js, etc.)
            let frameworksDir = packageDir.appendingPathComponent("Frameworks")
            if fileManager.fileExists(atPath: frameworksDir.path) {
                try scanFrameworksDirectory(frameworksDir, filesToRepair: &filesToRepair)
            }

            return filesToRepair
        }

        private func scanFrameworksDirectory(_ frameworksDir: URL, filesToRepair: inout [URL]) throws {
            let fileManager = FileManager.default
            
            // Recursively scan the Frameworks directory for Mach-O files
            if let enumerator = fileManager.enumerator(at: frameworksDir, includingPropertiesForKeys: [.isRegularFileKey, .isExecutableKey]) {
                for case let fileURL as URL in enumerator {
                    // Skip directories, symlinks, and obviously non-binary files
                    guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey]),
                          resourceValues.isRegularFile == true else {
                        continue
                    }
                    
                    let fileName = fileURL.lastPathComponent
                    
                    // Check for framework executables and dynamic libraries
                    let isFrameworkBinary = fileName.hasSuffix(".dylib") || 
                                           fileName.hasSuffix(".so") ||
                                           resourceValues.isExecutable == true ||
                                           fileURL.pathExtension.isEmpty // Framework main binary (e.g., Python)
                    
                    // Skip obvious non-binary files
                    let skipExtensions = ["txt", "py", "pyc", "pyo", "h", "plist", "strings", "md", "rst", "html", "xml", "json"]
                    if skipExtensions.contains(fileURL.pathExtension.lowercased()) {
                        continue
                    }
                    
                    if isFrameworkBinary {
                        do {
                            if try fileNeedsRepair(fileURL) {
                                filesToRepair.append(fileURL)
                            }
                        } catch {
                            // If we can't read the file with otool, it's probably not a Mach-O binary
                            continue
                        }
                    }
                }
            }
        }

        private func fileNeedsRepair(_ filePath: URL) throws -> Bool {
            let otoolProcess = Process()
            otoolProcess.executableURL = URL(fileURLWithPath: "/usr/bin/otool")
            otoolProcess.arguments = ["-L", filePath.path]

            let otoolPipe = Pipe()
            otoolProcess.standardOutput = otoolPipe
            otoolProcess.standardError = otoolPipe

            try otoolProcess.run()
            otoolProcess.waitUntilExit()

            guard otoolProcess.terminationStatus == 0 else {
                return false // Can't read, assume no repair needed
            }

            let otoolOutput = otoolPipe.fileHandleForReading.readDataToEndOfFile()
            let dependencies = String(data: otoolOutput, encoding: .utf8) ?? ""

            return dependencies.contains("@@HOMEBREW_PREFIX@@") || dependencies.contains("@@HOMEBREW_CELLAR@@")
        }

        // MARK: - PATH Configuration Repair

        private func checkAndFixPathConfiguration(pathHelper: PathHelper) throws {
            OSLogger.shared.info("🛤️  Checking PATH configuration...")

            let veloPath = pathHelper.binPath.path
            
            // Check if Velo is in PATH at all
            guard pathHelper.isInPath() else {
                OSLogger.shared.warning("  ❌ ~/.velo/bin is not in PATH")
                if dryRun {
                    OSLogger.shared.info("  Would run: velo install-self")
                } else {
                    OSLogger.shared.info("  Run 'velo install-self' to fix PATH setup")
                }
                return
            }

            // Check PATH position
            let pathPosition = checkVeloPathPosition(veloPath: veloPath)
            
            switch pathPosition {
            case .first:
                OSLogger.shared.info("  ✅ ~/.velo/bin is correctly positioned first in PATH")
            case .notFirst(let position):
                OSLogger.shared.warning("  ⚠️  ~/.velo/bin is in PATH but not first (position \(position))")
                if dryRun {
                    OSLogger.shared.info("  Would run: velo install-self")
                } else {
                    OSLogger.shared.info("  Run 'velo install-self' to fix PATH ordering")
                }
            case .notFound:
                OSLogger.shared.warning("  ❌ ~/.velo/bin not found in PATH (inconsistent state)")
                if dryRun {
                    OSLogger.shared.info("  Would run: velo install-self")
                } else {
                    OSLogger.shared.info("  Run 'velo install-self' to fix PATH setup")
                }
            }
        }

        private enum PathPosition {
            case first
            case notFirst(Int)
            case notFound
        }
        
        private func checkVeloPathPosition(veloPath: String) -> PathPosition {
            guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else {
                return .notFound
            }
            
            let pathComponents = pathEnv.components(separatedBy: ":")
                .filter { !$0.isEmpty }
            
            // Check for various Velo path representations
            let veloPathVariants = [
                veloPath,
                "$HOME/.velo/bin", 
                "~/.velo/bin",
                NSString(string: veloPath).expandingTildeInPath
            ]
            
            for (index, component) in pathComponents.enumerated() {
                let expandedComponent = NSString(string: component).expandingTildeInPath
                
                if veloPathVariants.contains(component) || veloPathVariants.contains(expandedComponent) {
                    return index == 0 ? .first : .notFirst(index + 1)
                }
            }
            
            return .notFound
        }

        // MARK: - Comprehensive File Repair

        private func findAllFilesNeedingRepair(in packageDir: URL) async throws -> [RepairableFile] {
            var filesToRepair: [RepairableFile] = []
            
            // Find binary files needing repair
            let binaryFiles = try findFilesNeedingRepair(in: packageDir)
            filesToRepair.append(contentsOf: binaryFiles.map { RepairableFile(url: $0, type: .binary) })
            
            // Find script files with placeholders
            let scriptFiles = try await findScriptFilesWithPlaceholders(in: packageDir)
            filesToRepair.append(contentsOf: scriptFiles.map { RepairableFile(url: $0, type: .script) })
            
            // Find Python files with hardcoded shebangs
            let pythonFiles = try await findPythonFilesWithHardcodedShebangs(in: packageDir)
            filesToRepair.append(contentsOf: pythonFiles.map { RepairableFile(url: $0, type: .pythonShebang) })
            
            return filesToRepair
        }

        private struct RepairableFile {
            let url: URL
            let type: RepairType
            
            enum RepairType {
                case binary
                case script
                case pythonShebang
            }
        }

        private func findScriptFilesWithPlaceholders(in directory: URL) async throws -> [URL] {
            let grepProcess = Process()
            grepProcess.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
            grepProcess.arguments = [
                "-r",  // Recursive
                "-l",  // Only show filenames, not content
                "--binary-files=without-match",  // Skip binary files
                "@@HOMEBREW_",  // Search pattern
                directory.path
            ]
            
            let grepPipe = Pipe()
            grepProcess.standardOutput = grepPipe
            grepProcess.standardError = Pipe() // Suppress error output
            
            try grepProcess.run()
            grepProcess.waitUntilExit()
            
            let output = grepPipe.fileHandleForReading.readDataToEndOfFile()
            let outputString = String(data: output, encoding: .utf8) ?? ""
            
            return outputString.components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
        }

        private func findPythonFilesWithHardcodedShebangs(in directory: URL) async throws -> [URL] {
            let grepProcess = Process()
            grepProcess.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
            grepProcess.arguments = [
                "-r",  // Recursive
                "-l",  // Only show filenames, not content
                "--binary-files=without-match",  // Skip binary files
                "^#!/.*\\.velo/.*python",  // Search for shebangs with .velo paths
                directory.path
            ]
            
            let grepPipe = Pipe()
            grepProcess.standardOutput = grepPipe
            grepProcess.standardError = Pipe() // Suppress error output
            
            try grepProcess.run()
            grepProcess.waitUntilExit()
            
            let output = grepPipe.fileHandleForReading.readDataToEndOfFile()
            let outputString = String(data: output, encoding: .utf8) ?? ""
            
            return outputString.components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0) }
        }

        private func repairScriptFile(_ filePath: URL, pathHelper: PathHelper) async throws {
            let content = try String(contentsOf: filePath, encoding: .utf8)
            
            // Replace Homebrew placeholders with actual Velo paths
            var newContent = content
            newContent = newContent.replacingOccurrences(of: "@@HOMEBREW_PREFIX@@", with: pathHelper.veloPrefix.path)
            newContent = newContent.replacingOccurrences(of: "@@HOMEBREW_CELLAR@@", with: pathHelper.cellarPath.path)
            
            // Only write if content actually changed
            if newContent != content {
                try newContent.write(to: filePath, atomically: true, encoding: .utf8)
            }
        }

        private func repairPythonShebang(_ filePath: URL) async throws {
            let content = try String(contentsOf: filePath, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            guard let firstLine = lines.first, firstLine.hasPrefix("#!") else {
                return // No shebang to fix
            }
            
            // Check if it's a hardcoded Python path
            let hardcodedPythonPatterns = [
                "/Users/[^/]+/\\.velo/.*python",
                "/.*\\.velo/.*python"
            ]
            
            var needsFixing = false
            for pattern in hardcodedPythonPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: firstLine, options: [], range: NSRange(location: 0, length: firstLine.count)) != nil {
                    needsFixing = true
                    break
                }
            }
            
            guard needsFixing else {
                return // Shebang doesn't need fixing
            }
            
            // Determine the appropriate portable shebang
            let portableShebang: String
            if firstLine.contains("python3") {
                portableShebang = "#!/usr/bin/env python3"
            } else if firstLine.contains("python") {
                portableShebang = "#!/usr/bin/env python3"  // Upgrade python to python3
            } else {
                return // Not a Python shebang
            }
            
            // Replace the first line with the portable shebang
            var newLines = lines
            newLines[0] = portableShebang
            let newContent = newLines.joined(separator: "\n")
            
            // Only write if content actually changed
            if newContent != content {
                try newContent.write(to: filePath, atomically: true, encoding: .utf8)
            }
        }

        // MARK: - Wrapper Script Repair

        private func checkAndFixWrapperScripts(pathHelper: PathHelper) async throws {
            OSLogger.shared.info("🔧 Checking wrapper scripts for hardcoded paths...")

            let binPath = pathHelper.binPath
            guard FileManager.default.fileExists(atPath: binPath.path) else {
                OSLogger.shared.info("  ℹ️  No bin directory found")
                return
            }

            let binContents = try FileManager.default.contentsOfDirectory(atPath: binPath.path)
            var wrapperScriptsChecked = 0
            var hardcodedPathsFound = 0
            var scriptsFixed = 0

            for filename in binContents {
                let scriptPath = binPath.appendingPathComponent(filename)
                
                // Skip if not a regular file
                guard let resourceValues = try? scriptPath.resourceValues(forKeys: [.isRegularFileKey]),
                      resourceValues.isRegularFile == true else {
                    continue
                }
                
                // Check if it's a shell script or Python script
                guard filename != "velo" && (isShellScript(scriptPath) || isPythonScript(scriptPath)) else {
                    continue
                }
                
                wrapperScriptsChecked += 1
                
                if try hasHardcodedPaths(scriptPath: scriptPath, pathHelper: pathHelper) {
                    hardcodedPathsFound += 1
                    OSLogger.shared.info("  ⚠️  Found hardcoded paths in \(filename)")
                    
                    if !dryRun {
                        if try await regenerateWrapperScript(scriptPath: scriptPath, pathHelper: pathHelper) {
                            scriptsFixed += 1
                            OSLogger.shared.info("    ✅ Regenerated \(filename) with portable paths")
                        } else {
                            OSLogger.shared.warning("    ❌ Could not regenerate \(filename)")
                        }
                    }
                }
            }

            if wrapperScriptsChecked == 0 {
                OSLogger.shared.info("  ℹ️  No wrapper scripts found to check")
            } else if hardcodedPathsFound == 0 {
                OSLogger.shared.info("  ✅ All \(wrapperScriptsChecked) wrapper scripts use portable paths")
            } else {
                if dryRun {
                    OSLogger.shared.info("  📊 Found \(hardcodedPathsFound) wrapper scripts with hardcoded paths")
                } else {
                    OSLogger.shared.info("  📊 Fixed \(scriptsFixed)/\(hardcodedPathsFound) wrapper scripts")
                }
            }
        }

        private func isShellScript(_ path: URL) -> Bool {
            guard let content = try? String(contentsOf: path, encoding: .utf8),
                  let firstLine = content.components(separatedBy: .newlines).first else {
                return false
            }
            return firstLine.hasPrefix("#!/bin/bash") || firstLine.hasPrefix("#!/bin/sh")
        }

        private func isPythonScript(_ path: URL) -> Bool {
            guard let content = try? String(contentsOf: path, encoding: .utf8),
                  let firstLine = content.components(separatedBy: .newlines).first else {
                return false
            }
            return firstLine.contains("python")
        }

        private func hasHardcodedPaths(scriptPath: URL, pathHelper: PathHelper) throws -> Bool {
            let content = try String(contentsOf: scriptPath, encoding: .utf8)
            
            // Check for hardcoded paths that should be made portable
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            let hardcodedPatterns = [
                "/Users/[^/]+/\\.velo/",
                "\(homeDir)/.velo/"
            ]
            
            for pattern in hardcodedPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: content, options: [], range: NSRange(location: 0, length: content.count)) != nil {
                    return true
                }
            }
            
            return false
        }

        private func regenerateWrapperScript(scriptPath: URL, pathHelper: PathHelper) async throws -> Bool {
            let filename = scriptPath.lastPathComponent
            
            // For now, we'll focus on the most common cases: Python framework wrappers
            if filename.hasPrefix("python") {
                try regeneratePythonWrapper(scriptPath: scriptPath, pathHelper: pathHelper)
                return true
            }
            
            // For other scripts that use #!/usr/bin/env python3, we can make them portable
            if isPythonScript(scriptPath) {
                try regenerateGenericPythonWrapper(scriptPath: scriptPath, pathHelper: pathHelper)
                return true
            }
            
            // For other wrapper scripts, we can't automatically regenerate them
            return false
        }

        private func regeneratePythonWrapper(scriptPath: URL, pathHelper: PathHelper) throws {
            let filename = scriptPath.lastPathComponent
            
            // Generate portable Python wrapper
            let wrapperContent = """
            #!/bin/bash
            # Velo framework wrapper script - portable version
            
            # Dynamically discover Velo installation root from script location
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            VELO_ROOT="$(dirname "$SCRIPT_DIR")"
            
            # Set framework path for dynamic library loading
            export DYLD_FRAMEWORK_PATH="$VELO_ROOT/Cellar/python@3.13/3.13.5/Frameworks:$DYLD_FRAMEWORK_PATH"
            
            # For Python specifically, set PYTHONHOME to help find the standard library
            if [[ "\(filename)" == python* ]]; then
                export PYTHONHOME="$VELO_ROOT/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13"
                # Also set PYTHONPATH for extension modules
                export PYTHONPATH="$VELO_ROOT/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/lib/python3.13:$VELO_ROOT/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/lib/python3.13/lib-dynload:$PYTHONPATH"
            fi
            
            # Execute the actual binary using relative path
            exec "$VELO_ROOT/Cellar/python@3.13/3.13.5/Frameworks/Python.framework/Versions/3.13/bin/\(filename)" "$@"
            """
            
            try wrapperContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            
            // Make executable
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: scriptPath.path)
        }

        private func regenerateGenericPythonWrapper(scriptPath: URL, pathHelper: PathHelper) throws {
            // For generic Python scripts, make them use #!/usr/bin/env python3 and dynamic path discovery
            let content = try String(contentsOf: scriptPath, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            guard lines.count > 1 else { return }
            
            // Update to portable version with dynamic site-packages discovery
            let portableContent = """
            #!/usr/bin/env python3
            # -*- coding: utf-8 -*-
            import sys
            import os
            
            # Dynamically discover Velo packages
            script_dir = os.path.dirname(os.path.abspath(__file__))
            velo_root = os.path.dirname(script_dir)
            
            # Add package-specific site-packages to Python path
            # This assumes the script is for a specific package with its own libexec
            package_name = os.path.basename(__file__)
            if package_name.endswith('.py'):
                package_name = package_name[:-3]
            
            # Try to find the package's site-packages directory
            for item in os.listdir(os.path.join(velo_root, 'Cellar')):
                if package_name in item:
                    potential_packages = os.path.join(velo_root, 'Cellar', item)
                    for version_dir in os.listdir(potential_packages):
                        site_packages = os.path.join(potential_packages, version_dir, 'libexec', 'lib', 'python3.13', 'site-packages')
                        if os.path.exists(site_packages) and site_packages not in sys.path:
                            sys.path.insert(0, site_packages)
                            break
            
            \(lines.dropFirst().joined(separator: "\n"))
            """
            
            try portableContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            
            // Make executable
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: scriptPath.path)
        }
    }
}