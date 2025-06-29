import Foundation

public struct Formula: Codable, Equatable {
    public let name: String
    public let description: String
    public let homepage: String
    public let url: String
    public let sha256: String
    public let version: String
    public let dependencies: [Dependency]
    public let bottles: [Bottle]
    
    public struct Dependency: Codable, Equatable {
        public let name: String
        public let type: DependencyType
        
        public enum DependencyType: String, Codable {
            case required
            case recommended
            case optional
            case build
        }
        
        public init(name: String, type: DependencyType = .required) {
            self.name = name
            self.type = type
        }
    }
    
    public struct Bottle: Codable, Equatable {
        public let sha256: String
        public let platform: Platform
        
        public enum Platform: String, Codable {
            case arm64_monterey
            case arm64_ventura 
            case arm64_sonoma
            case arm64_sequoia
            
            var osVersion: String {
                switch self {
                case .arm64_monterey: return "12"
                case .arm64_ventura: return "13"
                case .arm64_sonoma: return "14"
                case .arm64_sequoia: return "15"
                }
            }
            
            public var isCompatible: Bool {
                // Check if current macOS version is compatible
                let currentVersion = ProcessInfo.processInfo.operatingSystemVersion
                let requiredMajor = Int(osVersion) ?? 12
                return currentVersion.majorVersion >= requiredMajor
            }
        }
        
        public init(sha256: String, platform: Platform) {
            self.sha256 = sha256
            self.platform = platform
        }
    }
    
    public init(
        name: String,
        description: String,
        homepage: String,
        url: String,
        sha256: String,
        version: String,
        dependencies: [Dependency] = [],
        bottles: [Bottle] = []
    ) {
        self.name = name
        self.description = description
        self.homepage = homepage
        self.url = url
        self.sha256 = sha256
        self.version = version
        self.dependencies = dependencies
        self.bottles = bottles
    }
    
    /// Returns the best bottle for the current system
    public var preferredBottle: Bottle? {
        // Filter compatible bottles
        let compatible = bottles.filter { $0.platform.isCompatible }
        
        // Sort by OS version (newest first)
        return compatible.sorted { bottle1, bottle2 in
            bottle1.platform.osVersion > bottle2.platform.osVersion
        }.first
    }
    
    /// Check if formula has any compatible bottles
    public var hasCompatibleBottle: Bool {
        return preferredBottle != nil
    }
    
    /// Get bottle download URL for GHCR
    public func bottleURL(for bottle: Bottle) -> String? {
        // GHCR uses hierarchical paths for @-versioned packages
        // Format: ghcr.io/v2/homebrew/core/PACKAGE/VERSION_SLOT/blobs/sha256:HASH
        // Examples:
        //   openssl@3 -> openssl/3
        //   node@18 -> node/18  
        //   python@3.11 -> python/3.11
        //   tree (no @) -> tree
        
        let ghcrPath: String
        if name.contains("@") {
            // Split package@version into hierarchical path
            let parts = name.split(separator: "@", maxSplits: 1)
            if parts.count == 2 {
                let packageName = String(parts[0]).lowercased()
                let versionSlot = String(parts[1])
                ghcrPath = "\(packageName)/\(versionSlot)"
            } else {
                // Fallback if split fails
                ghcrPath = name.lowercased()
            }
        } else {
            // Non-versioned packages use simple name
            ghcrPath = name.lowercased()
        }
        
        return "https://ghcr.io/v2/homebrew/core/\(ghcrPath)/blobs/sha256:\(bottle.sha256)"
    }
}