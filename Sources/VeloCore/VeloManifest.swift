import Foundation
import VeloSystem

/// Represents the velo.json manifest file
public struct VeloManifest: Codable {
    public var dependencies: [String: String]
    public var taps: [String]

    public init(dependencies: [String: String] = [:], taps: [String] = []) {
        self.dependencies = dependencies
        self.taps = taps
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

        // Create simple manifest with empty dependencies and taps
        let manifest = VeloManifest(dependencies: [:], taps: [])

        // Write to file
        try write(manifest, to: url)

        print("✅ Created velo.json successfully!")
    }

    /// Add a dependency to the manifest
    public func addDependency(
        _ package: String,
        version: String,
        to manifestURL: URL
    ) throws {
        var manifest = try read(from: manifestURL)
        manifest.dependencies[package] = version
        try write(manifest, to: manifestURL)
    }

    /// Remove a dependency from the manifest
    public func removeDependency(
        _ package: String,
        from manifestURL: URL
    ) throws {
        var manifest = try read(from: manifestURL)
        manifest.dependencies.removeValue(forKey: package)
        try write(manifest, to: manifestURL)
    }

    /// Get all dependencies
    public func getAllDependencies(from manifest: VeloManifest) -> [String: String] {
        return manifest.dependencies
    }

    /// Get all taps
    public func getAllTaps(from manifest: VeloManifest) -> [String] {
        return manifest.taps
    }

    /// Add a tap to the manifest
    public func addTap(
        _ tap: String,
        to manifestURL: URL
    ) throws {
        var manifest = try read(from: manifestURL)
        if !manifest.taps.contains(tap) {
            manifest.taps.append(tap)
            manifest.taps.sort() // Keep taps sorted
            try write(manifest, to: manifestURL)
        }
    }

    /// Remove a tap from the manifest
    public func removeTap(
        _ tap: String,
        from manifestURL: URL
    ) throws {
        var manifest = try read(from: manifestURL)
        manifest.taps.removeAll { $0 == tap }
        try write(manifest, to: manifestURL)
    }
}
