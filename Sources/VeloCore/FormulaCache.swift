import Foundation
import VeloSystem
import VeloFormula

public protocol FormulaCacheProtocol {
    func get(_ name: String) throws -> Formula?
    func set(_ formula: Formula) throws
    func contains(_ name: String) -> Bool
    func remove(_ name: String) throws
    func clear() throws
    func preload(formulae: [Formula]) throws
    func statistics() -> CacheStatistics
}

public final class FormulaCache: FormulaCacheProtocol {
    private let pathHelper: PathHelper
    private let queue = DispatchQueue(label: "com.velo.formula-cache", attributes: .concurrent)
    private var memoryCache: [String: Formula] = [:]
    private let maxMemoryCacheSize: Int
    
    public init(pathHelper: PathHelper = PathHelper.shared, maxMemoryCacheSize: Int = 1000) {
        self.pathHelper = pathHelper
        self.maxMemoryCacheSize = maxMemoryCacheSize
    }
    
    // MARK: - Public Interface
    
    public func get(_ name: String) throws -> Formula? {
        return try queue.sync {
            // Check memory cache first
            if let cached = memoryCache[name] {
                return cached
            }
            
            // Check disk cache
            let cacheFile = pathHelper.cacheFile(for: "formula-\(name)")
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                return nil
            }
            
            let data = try Data(contentsOf: cacheFile)
            let formula = try JSONDecoder().decode(Formula.self, from: data)
            
            // Store in memory cache
            setMemoryCache(formula)
            
            return formula
        }
    }
    
    public func set(_ formula: Formula) throws {
        try queue.sync(flags: .barrier) {
            // Update memory cache
            setMemoryCache(formula)
            
            // Update disk cache
            let cacheFile = pathHelper.cacheFile(for: "formula-\(formula.name)")
            let data = try JSONEncoder().encode(formula)
            try data.write(to: cacheFile)
        }
    }
    
    public func contains(_ name: String) -> Bool {
        return queue.sync {
            if memoryCache[name] != nil {
                return true
            }
            
            let cacheFile = pathHelper.cacheFile(for: "formula-\(name)")
            return FileManager.default.fileExists(atPath: cacheFile.path)
        }
    }
    
    public func remove(_ name: String) throws {
        try queue.sync(flags: .barrier) {
            memoryCache.removeValue(forKey: name)
            
            let cacheFile = pathHelper.cacheFile(for: "formula-\(name)")
            if FileManager.default.fileExists(atPath: cacheFile.path) {
                try FileManager.default.removeItem(at: cacheFile)
            }
        }
    }
    
    public func clear() throws {
        try queue.sync(flags: .barrier) {
            memoryCache.removeAll()
            
            let cacheDir = pathHelper.cachePath
            let contents = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            
            for file in contents where file.pathExtension == "velocache" && file.lastPathComponent.hasPrefix("formula-") {
                try FileManager.default.removeItem(at: file)
            }
        }
    }
    
    public func preload(formulae: [Formula]) throws {
        try queue.sync(flags: .barrier) {
            logInfo("Preloading \(formulae.count) formulae to cache...")
            
            for formula in formulae {
                // Update memory cache
                setMemoryCache(formula)
                
                // Update disk cache
                let cacheFile = pathHelper.cacheFile(for: "formula-\(formula.name)")
                let data = try JSONEncoder().encode(formula)
                try data.write(to: cacheFile)
            }
            
            logInfo("Formula cache preloaded successfully")
        }
    }
    
    // MARK: - Cache Statistics
    
    public func statistics() -> CacheStatistics {
        return queue.sync {
            let memoryCacheSize = memoryCache.count
            
            let cacheDir = pathHelper.cachePath
            let diskCacheSize = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil))?.count { file in
                file.pathExtension == "velocache" && file.lastPathComponent.hasPrefix("formula-")
            } ?? 0
            
            var totalDiskSize: Int64 = 0
            if let contents = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey]) {
                for file in contents where file.pathExtension == "velocache" && file.lastPathComponent.hasPrefix("formula-") {
                    if let attributes = try? file.resourceValues(forKeys: [.fileSizeKey]),
                       let fileSize = attributes.fileSize {
                        totalDiskSize += Int64(fileSize)
                    }
                }
            }
            
            return CacheStatistics(
                memoryCacheCount: memoryCacheSize,
                diskCacheCount: diskCacheSize,
                totalDiskSizeBytes: totalDiskSize
            )
        }
    }
    
    // MARK: - Private Methods
    
    private func setMemoryCache(_ formula: Formula) {
        memoryCache[formula.name] = formula
        
        // Evict oldest entries if cache is too large
        if memoryCache.count > maxMemoryCacheSize {
            let excess = memoryCache.count - maxMemoryCacheSize
            let keysToRemove = Array(memoryCache.keys.prefix(excess))
            for key in keysToRemove {
                memoryCache.removeValue(forKey: key)
            }
        }
    }
}

// MARK: - Cache Statistics

public struct CacheStatistics {
    public let memoryCacheCount: Int
    public let diskCacheCount: Int
    public let totalDiskSizeBytes: Int64
    
    public var formattedDiskSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: totalDiskSizeBytes)
    }
}

// MARK: - High-Performance Formula Index

public final class FormulaIndex {
    private let cache: FormulaCacheProtocol
    private let queue = DispatchQueue(label: "com.velo.formula-index", attributes: .concurrent)
    private var nameIndex: [String: String] = [:] // lowercase name -> actual name
    private var descriptionIndex: [String: Set<String>] = [:] // keyword -> formula names
    
    public init(cache: FormulaCacheProtocol) {
        self.cache = cache
    }
    
    public func buildIndex(from formulae: [Formula]) throws {
        queue.sync(flags: .barrier) {
            logInfo("Building formula search index...")
            
            nameIndex.removeAll()
            descriptionIndex.removeAll()
            
            for formula in formulae {
                // Index by name
                nameIndex[formula.name.lowercased()] = formula.name
                
                // Index by description keywords
                let keywords = formula.description.lowercased()
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty && $0.count > 2 } // Skip very short words
                
                for keyword in keywords {
                    var formulas = descriptionIndex[keyword] ?? Set<String>()
                    formulas.insert(formula.name)
                    descriptionIndex[keyword] = formulas
                }
            }
            
            logInfo("Index built with \(nameIndex.count) formulae and \(descriptionIndex.count) keywords")
        }
    }
    
    public func search(_ term: String, includeDescriptions: Bool = false) -> [String] {
        return queue.sync {
            var results = Set<String>()
            let searchTerm = term.lowercased()
            
            // Search by name (exact and partial matches)
            for (indexedName, actualName) in nameIndex {
                if indexedName.contains(searchTerm) {
                    results.insert(actualName)
                }
            }
            
            // Search by description if requested
            if includeDescriptions {
                for (keyword, formulaNames) in descriptionIndex {
                    if keyword.contains(searchTerm) {
                        results.formUnion(formulaNames)
                    }
                }
            }
            
            // Sort results by relevance
            return Array(results).sorted { name1, name2 in
                let exact1 = name1.lowercased() == searchTerm
                let exact2 = name2.lowercased() == searchTerm
                
                if exact1 && !exact2 { return true }
                if !exact1 && exact2 { return false }
                
                return name1.localizedCompare(name2) == .orderedAscending
            }
        }
    }
    
    public func find(_ name: String) -> String? {
        return queue.sync {
            return nameIndex[name.lowercased()]
        }
    }
}

// MARK: - Performance Optimized Tap Manager

public final class TapManager {
    private let pathHelper: PathHelper
    private let cache: FormulaCacheProtocol
    private let index: FormulaIndex
    
    public init(pathHelper: PathHelper = PathHelper.shared) {
        self.pathHelper = pathHelper
        self.cache = FormulaCache(pathHelper: pathHelper)
        self.index = FormulaIndex(cache: cache)
    }
    
    public func updateTaps() async throws {
        logInfo("Updating taps...")
        
        // In a real implementation, this would:
        // 1. Clone/pull core tap repository
        // 2. Parse all formulae in parallel
        // 3. Update cache and index
        
        // For now, simulate by using test fixtures
        let parser = FormulaParser()
        var formulae: [Formula] = []
        
        let fixturesPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Formulae")
        
        if FileManager.default.fileExists(atPath: fixturesPath.path) {
            let formulaFiles = try FileManager.default.contentsOfDirectory(atPath: fixturesPath.path)
                .filter { $0.hasSuffix(".rb") }
            
            for file in formulaFiles {
                let formulaPath = fixturesPath.appendingPathComponent(file)
                let formulaName = String(file.dropLast(3))
                
                do {
                    let content = try String(contentsOf: formulaPath)
                    let formula = try parser.parse(rubyContent: content, formulaName: formulaName)
                    formulae.append(formula)
                } catch {
                    logWarning("Failed to parse \(formulaName): \(error)")
                }
            }
        }
        
        // Update cache and index
        try cache.preload(formulae: formulae)
        try index.buildIndex(from: formulae)
        
        logInfo("Tap update completed with \(formulae.count) formulae")
    }
    
    public func findFormula(_ name: String) throws -> Formula? {
        // Try exact name first
        if let formula = try cache.get(name) {
            return formula
        }
        
        // Try case-insensitive search
        if let actualName = index.find(name) {
            return try cache.get(actualName)
        }
        
        return nil
    }
    
    public func searchFormulae(_ term: String, includeDescriptions: Bool = false) -> [String] {
        return index.search(term, includeDescriptions: includeDescriptions)
    }
    
    public func cacheStatistics() -> CacheStatistics {
        return cache.statistics()
    }
}