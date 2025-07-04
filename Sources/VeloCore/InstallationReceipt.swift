import Foundation
import VeloSystem

/// Tracks how and why a package was installed
public struct InstallationReceipt: Codable, Equatable {
    public enum InstallationType: String, Codable {
        case explicit    // User explicitly requested this package
        case dependency  // Installed as a dependency of another package
    }

    public let package: String
    public let version: String
    public let installedAt: Date
    public var installedAs: InstallationType
    public var requestedBy: [String]  // Packages that depend on this
    public var symlinksCreated: Bool

    public init(
        package: String,
        version: String,
        installedAt: Date = Date(),
        installedAs: InstallationType,
        requestedBy: [String] = [],
        symlinksCreated: Bool
    ) {
        self.package = package
        self.version = version
        self.installedAt = installedAt
        self.installedAs = installedAs
        self.requestedBy = requestedBy
        self.symlinksCreated = symlinksCreated
    }
}

/// Manages installation receipts
public final class ReceiptManager {
    private let pathHelper: PathHelper
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(pathHelper: PathHelper = PathHelper.shared) {
        self.pathHelper = pathHelper
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    /// Get the receipt file path for a package
    private func receiptPath(for package: String, version: String) -> URL {
        pathHelper.receiptsPath
            .appendingPathComponent(package)
            .appendingPathComponent(version)
            .appendingPathComponent("receipt.json")
    }

    /// Save a receipt
    public func saveReceipt(_ receipt: InstallationReceipt) throws {
        let path = receiptPath(for: receipt.package, version: receipt.version)

        // Ensure directory exists
        try pathHelper.ensureDirectoryExists(at: path.deletingLastPathComponent())

        // Write receipt
        let data = try encoder.encode(receipt)
        try data.write(to: path)
    }

    /// Load a receipt
    public func loadReceipt(for package: String, version: String) throws -> InstallationReceipt? {
        let path = receiptPath(for: package, version: version)

        guard fileManager.fileExists(atPath: path.path) else {
            return nil
        }

        let data = try Data(contentsOf: path)
        return try decoder.decode(InstallationReceipt.self, from: data)
    }

    /// Load receipt for any version of a package (returns latest)
    public func loadReceipt(for package: String) throws -> InstallationReceipt? {
        let packageReceiptsDir = pathHelper.receiptsPath.appendingPathComponent(package)

        guard fileManager.fileExists(atPath: packageReceiptsDir.path) else {
            return nil
        }

        let versions = try fileManager.contentsOfDirectory(atPath: packageReceiptsDir.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()

        guard let latestVersion = versions.last else {
            return nil
        }

        return try loadReceipt(for: package, version: latestVersion)
    }

    /// Delete a receipt
    public func deleteReceipt(for package: String, version: String) throws {
        let path = receiptPath(for: package, version: version)

        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }

        // Clean up empty directories
        let versionDir = path.deletingLastPathComponent()
        let packageDir = versionDir.deletingLastPathComponent()

        // Remove version directory if empty
        if let contents = try? fileManager.contentsOfDirectory(atPath: versionDir.path),
           contents.isEmpty {
            try? fileManager.removeItem(at: versionDir)
        }

        // Remove package directory if empty
        if let contents = try? fileManager.contentsOfDirectory(atPath: packageDir.path),
           contents.isEmpty {
            try? fileManager.removeItem(at: packageDir)
        }
    }

    /// Update a receipt
    public func updateReceipt(for package: String, version: String, update: (inout InstallationReceipt) throws -> Void) throws {
        guard var receipt = try loadReceipt(for: package, version: version) else {
            throw VeloError.receiptNotFound(package: package, version: version)
        }

        try update(&receipt)
        try saveReceipt(receipt)
    }

    /// Add a package to the requestedBy list of another package
    public func addDependent(_ dependent: String, to package: String, version: String) throws {
        try updateReceipt(for: package, version: version) { receipt in
            if !receipt.requestedBy.contains(dependent) {
                receipt.requestedBy.append(dependent)
            }
        }
    }

    /// Remove a package from the requestedBy list of another package
    public func removeDependent(_ dependent: String, from package: String, version: String) throws {
        try updateReceipt(for: package, version: version) { receipt in
            receipt.requestedBy.removeAll { $0 == dependent }
        }
    }
}
