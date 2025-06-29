import Foundation
import VeloSystem

/// Represents the velo.json manifest file
public struct VeloManifest: Codable {
    public let name: String?
    public let version: String?
    public var dependencies: [String: String]
    public var devDependencies: [String: String]?
    public var scripts: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case name
        case version
        case dependencies
        case devDependencies
        case scripts
    }
    
    public init(
        name: String? = nil,
        version: String? = nil,
        dependencies: [String: String] = [:],
        devDependencies: [String: String]? = nil,
        scripts: [String: String]? = nil
    ) {
        self.name = name
        self.version = version
        self.dependencies = dependencies
        self.devDependencies = devDependencies
        self.scripts = scripts
    }
}

/// Manages reading and writing velo.json files
public final class VeloManifestManager {
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    public init() {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }
    
    /// Read manifest from a file
    public func read(from url: URL) throws -> VeloManifest {
        let data = try Data(contentsOf: url)
        return try decoder.decode(VeloManifest.self, from: data)
    }
    
    /// Write manifest to a file
    public func write(_ manifest: VeloManifest, to url: URL) throws {
        let data = try encoder.encode(manifest)
        try data.write(to: url)
    }
    
    /// Create a new manifest file interactively
    public func createInteractive(at url: URL) throws {
        // Check if file already exists
        if fileManager.fileExists(atPath: url.path) {
            print("velo.json already exists at \(url.path)")
            print("Overwrite? [y/N]: ", terminator: "")
            let input = readLine()?.lowercased()
            if input != "y" && input != "yes" {
                return
            }
        }
        
        print("Creating new velo.json...")
        
        // Get project name (default to directory name)
        let defaultName = url.deletingLastPathComponent().lastPathComponent
        print("Project name (\(defaultName)): ", terminator: "")
        let name = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectName = name?.isEmpty == false ? name : defaultName
        
        // Get version
        print("Version (1.0.0): ", terminator: "")
        let versionInput = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = versionInput?.isEmpty == false ? versionInput : "1.0.0"
        
        // Create manifest
        let manifest = VeloManifest(
            name: projectName,
            version: version,
            dependencies: [:],
            devDependencies: [:],
            scripts: [:]
        )
        
        // Write to file
        try write(manifest, to: url)
        
        print("✅ Created velo.json successfully!")
        print("\nNext steps:")
        print("  - Add dependencies: velo install <package> --save")
        print("  - Install all dependencies: velo install")
    }
    
    /// Add a dependency to the manifest
    public func addDependency(
        _ package: String,
        version: String,
        isDev: Bool = false,
        to manifestURL: URL
    ) throws {
        var manifest = try read(from: manifestURL)
        
        if isDev {
            if manifest.devDependencies == nil {
                manifest.devDependencies = [:]
            }
            manifest.devDependencies?[package] = version
        } else {
            manifest.dependencies[package] = version
        }
        
        try write(manifest, to: manifestURL)
    }
    
    /// Remove a dependency from the manifest
    public func removeDependency(
        _ package: String,
        isDev: Bool = false,
        from manifestURL: URL
    ) throws {
        var manifest = try read(from: manifestURL)
        
        if isDev {
            manifest.devDependencies?.removeValue(forKey: package)
        } else {
            manifest.dependencies.removeValue(forKey: package)
        }
        
        try write(manifest, to: manifestURL)
    }
    
    /// Get all dependencies (including dev dependencies based on context)
    public func getAllDependencies(
        from manifest: VeloManifest,
        includeDev: Bool = true
    ) -> [String: String] {
        var all = manifest.dependencies
        
        if includeDev, let devDeps = manifest.devDependencies {
            for (package, version) in devDeps {
                all[package] = version
            }
        }
        
        return all
    }
}