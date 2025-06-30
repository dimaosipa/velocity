import Foundation
import VeloSystem

public struct TapCacheMetadata: Codable {
    public let lastUpdated: Date
    public let lastCommit: String?
    public let updateDuration: TimeInterval
    public let searchIndexBuilt: Date?
    
    public init(lastUpdated: Date = Date(), lastCommit: String? = nil, updateDuration: TimeInterval = 0, searchIndexBuilt: Date? = nil) {
        self.lastUpdated = lastUpdated
        self.lastCommit = lastCommit
        self.updateDuration = updateDuration
        self.searchIndexBuilt = searchIndexBuilt
    }
}

public class TapCacheManager {
    private let pathHelper: PathHelper
    private var cache: [String: TapCacheMetadata] = [:]
    
    public init(pathHelper: PathHelper = PathHelper.shared) {
        self.pathHelper = pathHelper
        loadCacheMetadata()
    }
    
    // MARK: - Public Interface
    
    public func isCacheFresh(for tapName: String, maxAge: TimeInterval) -> Bool {
        guard let metadata = cache[tapName] else {
            return false // No cache = not fresh
        }
        
        let age = Date().timeIntervalSince(metadata.lastUpdated)
        return age < maxAge
    }
    
    public func getCacheAge(for tapName: String) -> TimeInterval? {
        guard let metadata = cache[tapName] else {
            return nil
        }
        
        return Date().timeIntervalSince(metadata.lastUpdated)
    }
    
    public func updateCacheMetadata(for tapName: String, lastCommit: String? = nil, updateDuration: TimeInterval = 0) {
        let currentMetadata = cache[tapName]
        let metadata = TapCacheMetadata(
            lastUpdated: Date(),
            lastCommit: lastCommit,
            updateDuration: updateDuration,
            searchIndexBuilt: currentMetadata?.searchIndexBuilt  // Preserve existing search index timestamp
        )
        
        cache[tapName] = metadata
        saveCacheMetadata()
        
        logInfo("Updated cache metadata for \(tapName)")
    }
    
    public func getCacheStatus(for tapName: String) -> String {
        guard let metadata = cache[tapName] else {
            return "No cache data"
        }
        
        let age = Date().timeIntervalSince(metadata.lastUpdated)
        let ageMinutes = Int(age / 60)
        let ageHours = Int(age / 3600)
        
        if ageHours > 0 {
            return "Updated \(ageHours) hours ago"
        } else {
            return "Updated \(ageMinutes) minutes ago"
        }
    }
    
    public func clearCache() {
        cache.removeAll()
        saveCacheMetadata()
        logInfo("Cleared tap cache metadata")
    }
    
    // MARK: - Search Index Cache Management
    
    public func isSearchIndexFresh(for tapName: String) -> Bool {
        guard let metadata = cache[tapName],
              let searchIndexBuilt = metadata.searchIndexBuilt else {
            return false  // No search index built yet
        }
        
        // Search index is fresh if it was built after the tap was last updated
        return searchIndexBuilt >= metadata.lastUpdated
    }
    
    public func updateSearchIndexTimestamp(for tapName: String) {
        guard let currentMetadata = cache[tapName] else {
            // Create new metadata entry if tap doesn't exist
            let metadata = TapCacheMetadata(searchIndexBuilt: Date())
            cache[tapName] = metadata
            saveCacheMetadata()
            return
        }
        
        let metadata = TapCacheMetadata(
            lastUpdated: currentMetadata.lastUpdated,
            lastCommit: currentMetadata.lastCommit,
            updateDuration: currentMetadata.updateDuration,
            searchIndexBuilt: Date()
        )
        
        cache[tapName] = metadata
        saveCacheMetadata()
        
        logInfo("Updated search index timestamp for \(tapName)")
    }
    
    // MARK: - Private Methods
    
    private func loadCacheMetadata() {
        let metadataFile = pathHelper.tapMetadataFile
        
        guard FileManager.default.fileExists(atPath: metadataFile.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: metadataFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cache = try decoder.decode([String: TapCacheMetadata].self, from: data)
        } catch {
            logWarning("Failed to load tap cache metadata: \(error)")
            // Clear corrupted cache file and start fresh
            try? FileManager.default.removeItem(at: metadataFile)
            cache = [:]
        }
    }
    
    private func saveCacheMetadata() {
        let metadataFile = pathHelper.tapMetadataFile
        
        do {
            // Ensure cache directory exists
            try pathHelper.ensureDirectoryExists(at: pathHelper.cachePath)
            
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(cache)
            try data.write(to: metadataFile)
        } catch {
            logWarning("Failed to save tap cache metadata: \(error)")
        }
    }
}