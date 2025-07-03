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
    public let postInstallScript: String?

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
            // Apple Silicon (arm64) platforms
            case arm64_monterey
            case arm64_ventura
            case arm64_sonoma
            case arm64_sequoia
            
            // Intel (x86_64) platforms - for Rosetta compatibility
            case monterey
            case ventura 
            case sonoma
            case sequoia
            case big_sur
            case catalina
            case mojave
            
            // Universal platforms
            case all

            var osVersion: String {
                switch self {
                case .arm64_monterey, .monterey: return "12"
                case .arm64_ventura, .ventura: return "13"
                case .arm64_sonoma, .sonoma: return "14"
                case .arm64_sequoia, .sequoia: return "15"
                case .big_sur: return "11"
                case .catalina: return "10.15"
                case .mojave: return "10.14"
                case .all: return "all"
                }
            }
            
            var architecture: String {
                switch self {
                case .arm64_monterey, .arm64_ventura, .arm64_sonoma, .arm64_sequoia:
                    return "arm64"
                case .monterey, .ventura, .sonoma, .sequoia, .big_sur, .catalina, .mojave:
                    return "x86_64"
                case .all:
                    return "universal"
                }
            }

            public var isCompatible: Bool {
                // "all" platform is compatible with everything
                if self == .all {
                    return true
                }
                
                // Check if current macOS version is compatible
                let currentVersion = ProcessInfo.processInfo.operatingSystemVersion
                let requiredMajor = Int(osVersion.split(separator: ".").first.map(String.init) ?? "12") ?? 12
                
                // macOS version compatibility
                let isVersionCompatible = currentVersion.majorVersion >= requiredMajor
                
                // Architecture compatibility
                #if arch(arm64)
                // Apple Silicon can run both arm64 and x86_64 (via Rosetta)
                return isVersionCompatible
                #elseif arch(x86_64)
                // Intel Macs can only run x86_64
                return isVersionCompatible && (architecture == "x86_64" || architecture == "universal")
                #else
                // Fallback for other architectures
                return isVersionCompatible && architecture == "universal"
                #endif
            }
            
            /// Priority for bottle selection (higher is better)
            public var priority: Int {
                #if arch(arm64)
                // On Apple Silicon, prefer native arm64, then universal, then x86_64 (Rosetta)
                switch self {
                case .arm64_sequoia: return 100
                case .arm64_sonoma: return 99
                case .arm64_ventura: return 98
                case .arm64_monterey: return 97
                case .all: return 50
                case .sequoia: return 30
                case .sonoma: return 29
                case .ventura: return 28
                case .monterey: return 27
                case .big_sur: return 26
                default: return 10
                }
                #elseif arch(x86_64)
                // On Intel, prefer native x86_64, then universal
                switch self {
                case .sequoia: return 100
                case .sonoma: return 99
                case .ventura: return 98
                case .monterey: return 97
                case .big_sur: return 96
                case .catalina: return 95
                case .mojave: return 94
                case .all: return 50
                default: return 10
                }
                #else
                // Fallback
                return self == .all ? 50 : 10
                #endif
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
        bottles: [Bottle] = [],
        postInstallScript: String? = nil
    ) {
        self.name = name
        self.description = description
        self.homepage = homepage
        self.url = url
        self.sha256 = sha256
        self.version = version
        self.dependencies = dependencies
        self.bottles = bottles
        self.postInstallScript = postInstallScript
    }

    /// Returns the best bottle for the current system
    public var preferredBottle: Bottle? {
        // Filter compatible bottles
        let compatible = bottles.filter { $0.platform.isCompatible }
        
        // If no compatible bottles, return nil
        guard !compatible.isEmpty else {
            return nil
        }

        // Sort by priority (highest first), then by OS version (newest first)
        return compatible.sorted { bottle1, bottle2 in
            if bottle1.platform.priority != bottle2.platform.priority {
                return bottle1.platform.priority > bottle2.platform.priority
            }
            return bottle1.platform.osVersion > bottle2.platform.osVersion
        }.first
    }
    
    /// Get the best available bottle (may include Rosetta compatibility)
    public var bestAvailableBottle: Bottle? {
        return preferredBottle
    }
    
    /// Check if we can run this package via Rosetta (x86_64 on Apple Silicon)
    public var hasRosettaCompatibleBottle: Bool {
        #if arch(arm64)
        return bottles.contains { bottle in
            bottle.platform.architecture == "x86_64" && bottle.platform.isCompatible
        }
        #else
        return false
        #endif
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
