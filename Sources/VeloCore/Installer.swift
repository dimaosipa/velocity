import Foundation
import VeloSystem
import VeloFormula

public protocol InstallationProgress {
    func installationDidStart(package: String, version: String)
    func extractionDidStart(totalFiles: Int?)
    func extractionDidUpdate(filesExtracted: Int, totalFiles: Int?)
    func linkingDidStart(binariesCount: Int)
    func linkingDidUpdate(binariesLinked: Int, totalBinaries: Int)
    func installationDidComplete(package: String)
    func installationDidFail(package: String, error: Error)
}

public final class Installer {
    private let pathHelper: PathHelper
    private let fileManager = FileManager.default
    
    public init(pathHelper: PathHelper = PathHelper.shared) {
        self.pathHelper = pathHelper
    }
    
    public func install(
        formula: Formula,
        from bottleFile: URL,
        progress: InstallationProgress? = nil
    ) async throws {
        progress?.installationDidStart(package: formula.name, version: formula.version)
        
        // Ensure Velo directories exist
        try pathHelper.ensureVeloDirectories()
        
        // Check if already installed
        if pathHelper.isPackageInstalled(formula.name) {
            throw VeloError.alreadyInstalled(package: formula.name)
        }
        
        // Create package directory
        let packageDir = pathHelper.packagePath(for: formula.name, version: formula.version)
        try pathHelper.ensureDirectoryExists(at: packageDir)
        
        do {
            // Extract bottle
            try await extractBottle(from: bottleFile, to: packageDir, progress: progress)
            
            // Create symlinks
            try await createSymlinks(for: formula, packageDir: packageDir, progress: progress)
            
            progress?.installationDidComplete(package: formula.name)
            
        } catch {
            // Clean up on failure
            try? fileManager.removeItem(at: packageDir)
            progress?.installationDidFail(package: formula.name, error: error)
            throw error
        }
    }
    
    public func uninstall(package: String) throws {
        guard pathHelper.isPackageInstalled(package) else {
            throw VeloError.formulaNotFound(name: package)
        }
        
        let packageBaseDir = pathHelper.cellarPath.appendingPathComponent(package)
        let versions = pathHelper.installedVersions(for: package)
        
        // Remove all symlinks for this package
        for version in versions {
            let packageDir = pathHelper.packagePath(for: package, version: version)
            try removeSymlinks(for: package, packageDir: packageDir)
        }
        
        // Remove package directory
        try fileManager.removeItem(at: packageBaseDir)
    }
    
    // MARK: - Extraction
    
    private func extractBottle(
        from bottleFile: URL,
        to destination: URL,
        progress: InstallationProgress?
    ) async throws {
        progress?.extractionDidStart(totalFiles: nil)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-xf", bottleFile.path,
            "-C", destination.path,
            "--strip-components=2"  // Strip 2 levels: package/version/...
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw VeloError.extractionFailed(reason: errorOutput)
        }
        
        // Count extracted files for progress
        let extractedFiles = try countFiles(in: destination)
        progress?.extractionDidUpdate(filesExtracted: extractedFiles, totalFiles: extractedFiles)
    }
    
    // MARK: - Symlink Management
    
    private func createSymlinks(
        for formula: Formula,
        packageDir: URL,
        progress: InstallationProgress?
    ) async throws {
        let binDir = packageDir.appendingPathComponent("bin")
        guard fileManager.fileExists(atPath: binDir.path) else {
            // No binaries to link
            progress?.linkingDidStart(binariesCount: 0)
            return
        }
        
        let binaries = try fileManager.contentsOfDirectory(atPath: binDir.path)
            .filter { !$0.hasPrefix(".") }
        
        progress?.linkingDidStart(binariesCount: binaries.count)
        
        for (index, binary) in binaries.enumerated() {
            let sourcePath = binDir.appendingPathComponent(binary)
            let destinationPath = pathHelper.symlinkPath(for: binary)
            
            try pathHelper.createSymlink(from: sourcePath, to: destinationPath)
            
            progress?.linkingDidUpdate(binariesLinked: index + 1, totalBinaries: binaries.count)
        }
    }
    
    private func removeSymlinks(for package: String, packageDir: URL) throws {
        let binDir = packageDir.appendingPathComponent("bin")
        guard fileManager.fileExists(atPath: binDir.path) else {
            return
        }
        
        let binaries = try fileManager.contentsOfDirectory(atPath: binDir.path)
            .filter { !$0.hasPrefix(".") }
        
        for binary in binaries {
            let symlinkPath = pathHelper.symlinkPath(for: binary)
            if fileManager.fileExists(atPath: symlinkPath.path) {
                try fileManager.removeItem(at: symlinkPath)
            }
        }
    }
    
    // MARK: - Verification
    
    public func verifyInstallation(formula: Formula) throws -> InstallationStatus {
        let packageDir = pathHelper.packagePath(for: formula.name, version: formula.version)
        
        guard fileManager.fileExists(atPath: packageDir.path) else {
            return .notInstalled
        }
        
        // Check if binaries are properly linked
        let binDir = packageDir.appendingPathComponent("bin")
        if fileManager.fileExists(atPath: binDir.path) {
            let binaries = try fileManager.contentsOfDirectory(atPath: binDir.path)
                .filter { !$0.hasPrefix(".") }
            
            for binary in binaries {
                let symlinkPath = pathHelper.symlinkPath(for: binary)
                if !fileManager.fileExists(atPath: symlinkPath.path) {
                    return .corrupted(reason: "Missing symlink for \(binary)")
                }
                
                // Verify symlink points to correct location
                let resolvedPath = try fileManager.destinationOfSymbolicLink(atPath: symlinkPath.path)
                let expectedPath = binDir.appendingPathComponent(binary).path
                if resolvedPath != expectedPath {
                    return .corrupted(reason: "Symlink \(binary) points to wrong location")
                }
            }
        }
        
        return .installed
    }
    
    // MARK: - Helper Methods
    
    private func countFiles(in directory: URL) throws -> Int {
        var count = 0
        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for _ in enumerator {
                count += 1
            }
        }
        return count
    }
    
    public enum InstallationStatus {
        case notInstalled
        case installed
        case corrupted(reason: String)
        
        public var isInstalled: Bool {
            switch self {
            case .installed:
                return true
            case .notInstalled, .corrupted:
                return false
            }
        }
    }
}

// MARK: - Convenience Extensions

extension Installer {
    public func repairInstallation(formula: Formula, bottleFile: URL) async throws {
        // Uninstall if partially installed
        if pathHelper.isPackageInstalled(formula.name) {
            try uninstall(package: formula.name)
        }
        
        // Reinstall
        try await install(formula: formula, from: bottleFile)
    }
    
    public func upgradePackage(
        oldFormula: Formula,
        newFormula: Formula,
        bottleFile: URL,
        progress: InstallationProgress? = nil
    ) async throws {
        // Install new version first
        try await install(formula: newFormula, from: bottleFile, progress: progress)
        
        // Remove old version
        try uninstall(package: oldFormula.name)
    }
}