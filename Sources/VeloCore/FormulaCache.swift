import Foundation
import VeloSystem
import VeloFormula

// Helper extension for array chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

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

            // Ensure cache directory exists
            try pathHelper.ensureDirectoryExists(at: pathHelper.cachePath)

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
        return queue.sync { [self] in
            let memoryCacheSize = memoryCache.count

            let cacheDir = pathHelper.cachePath
            let diskCacheSize = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil))?.filter { file in
                file.pathExtension == "velocache" && file.lastPathComponent.hasPrefix("formula-")
            }.count ?? 0

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

// Search index data structure for serialization
private struct SearchIndexData: Codable {
    let nameIndex: [String: String]
    let descriptionIndex: [String: [String]]  // Set<String> -> [String] for Codable
    let buildTimestamp: Date
}

public final class FormulaIndex {
    private let cache: FormulaCacheProtocol
    private let pathHelper: PathHelper
    private let tapCacheManager: TapCacheManager
    private let queue = DispatchQueue(label: "com.velo.formula-index", attributes: .concurrent)
    private var nameIndex: [String: String] = [:] // lowercase name -> actual name
    private var descriptionIndex: [String: Set<String>] = [:] // keyword -> formula names

    public init(cache: FormulaCacheProtocol, pathHelper: PathHelper = PathHelper.shared, tapCacheManager: TapCacheManager) {
        self.cache = cache
        self.pathHelper = pathHelper
        self.tapCacheManager = tapCacheManager
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
    
    // MARK: - Cache Management
    
    public func loadIndexFromCache(for tapName: String) -> Bool {
        return queue.sync {
            let cacheFile = pathHelper.searchIndexCacheFile(for: tapName)
            
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                logVerbose("No search index cache found for \(tapName)")
                return false
            }
            
            do {
                let data = try Data(contentsOf: cacheFile)
                let searchData = try JSONDecoder().decode(SearchIndexData.self, from: data)
                
                // Convert back from [String] to Set<String>
                nameIndex = searchData.nameIndex
                descriptionIndex = searchData.descriptionIndex.mapValues { Set($0) }
                
                logInfo("Loaded search index from cache for \(tapName)")
                return true
            } catch {
                logWarning("Failed to load search index cache: \(error)")
                // Remove corrupted cache file
                try? FileManager.default.removeItem(at: cacheFile)
                return false
            }
        }
    }
    
    public func saveIndexToCache(for tapName: String) {
        queue.sync {
            let cacheFile = pathHelper.searchIndexCacheFile(for: tapName)
            
            do {
                // Ensure cache directory exists
                try pathHelper.ensureDirectoryExists(at: pathHelper.cachePath)
                
                // Convert Set<String> to [String] for Codable
                let searchData = SearchIndexData(
                    nameIndex: nameIndex,
                    descriptionIndex: descriptionIndex.mapValues { Array($0) },
                    buildTimestamp: Date()
                )
                
                let data = try JSONEncoder().encode(searchData)
                try data.write(to: cacheFile)
                
                // Update the tap cache manager with search index timestamp
                tapCacheManager.updateSearchIndexTimestamp(for: tapName)
                
                logInfo("Saved search index to cache for \(tapName)")
            } catch {
                logWarning("Failed to save search index cache: \(error)")
            }
        }
    }
}

// MARK: - Performance Optimized Tap Manager

public final class TapManager {
    private let pathHelper: PathHelper
    private let cache: FormulaCacheProtocol
    private let index: FormulaIndex
    private let cacheManager: TapCacheManager
    
    // Static flag to prevent concurrent tap updates
    private static var isUpdatingTaps = false
    private static let updateQueue = DispatchQueue(label: "com.velo.tap-update", attributes: .concurrent)

    public init(pathHelper: PathHelper = PathHelper.shared) {
        self.pathHelper = pathHelper
        self.cache = FormulaCache(pathHelper: pathHelper)
        self.cacheManager = TapCacheManager(pathHelper: pathHelper)
        self.index = FormulaIndex(cache: cache, pathHelper: pathHelper, tapCacheManager: cacheManager)
    }

    public func updateTaps(force: Bool = false, maxAge: TimeInterval = 3600) async throws {
        // Check if another tap update is already in progress
        let shouldUpdate = TapManager.updateQueue.sync {
            if TapManager.isUpdatingTaps {
                return false
            }
            TapManager.isUpdatingTaps = true
            return true
        }
        
        if !shouldUpdate {
            logInfo("Tap update already in progress, skipping...")
            return
        }
        
        defer {
            TapManager.updateQueue.sync {
                TapManager.isUpdatingTaps = false
            }
        }

        // Check cache freshness unless forced
        if !force && cacheManager.isCacheFresh(for: "homebrew/core", maxAge: maxAge) {
            let status = cacheManager.getCacheStatus(for: "homebrew/core")
            logInfo("Using cached homebrew/core tap (\(status))")
            return
        }

        let startTime = Date()
        logInfo("Updating homebrew/core tap...")

        // Ensure homebrew/core tap is cloned and up to date
        try await ensureCoreTap()

        // Update cache metadata
        let duration = Date().timeIntervalSince(startTime)
        cacheManager.updateCacheMetadata(for: "homebrew/core", updateDuration: duration)

        // For lazy loading, we don't parse all formulae upfront
        // Instead, we'll parse them on-demand as they're requested
        logInfo("Tap ready for on-demand formula parsing")
    }

    /// Full index build - only run when explicitly requested (e.g., for search functionality)
    public func buildFullIndex() async throws {
        // Check if we can load from cache for the primary tap (homebrew/core)
        let primaryTapName = "homebrew/core"
        
        if cacheManager.isSearchIndexFresh(for: primaryTapName) {
            if index.loadIndexFromCache(for: primaryTapName) {
                logInfo("Search index loaded from cache for \(primaryTapName)")
                return
            }
        }
        
        logInfo("Building full formula index...")

        let parser = FormulaParser()
        var formulae: [Formula] = []
        let tapsPath = pathHelper.tapsPath

        if FileManager.default.fileExists(atPath: tapsPath.path) {
            // Process all taps
            let organizations = try FileManager.default.contentsOfDirectory(atPath: tapsPath.path)
                .filter { !$0.hasPrefix(".") }

            for org in organizations {
                let orgPath = tapsPath.appendingPathComponent(org)
                let repos = try FileManager.default.contentsOfDirectory(atPath: orgPath.path)
                    .filter { !$0.hasPrefix(".") }

                for repo in repos {
                    let tapName = "\(org)/\(repo)"
                    let tapPath = orgPath.appendingPathComponent(repo)
                    let formulaPath = tapPath.appendingPathComponent("Formula")

                    guard FileManager.default.fileExists(atPath: formulaPath.path) else {
                        continue
                    }

                    logInfo("Parsing formulae from \(tapName) tap...")
                    try await processFormulaeFromTap(tapPath: formulaPath, tapName: tapName, parser: parser, formulae: &formulae)
                }
            }
        } else {
            #if DEBUG
            // Fallback to test fixtures if no taps available (development only)
            logWarning("No taps found, using test fixtures...")
            try await loadTestFixtures(parser: parser, formulae: &formulae)
            #else
            // In production, no taps means no formulae available
            logError("No taps found and no formulae available")
            #endif
        }

        // Update cache and index
        try cache.preload(formulae: formulae)
        try index.buildIndex(from: formulae)
        
        // Save the search index to cache
        index.saveIndexToCache(for: primaryTapName)

        logInfo("Full index built with \(formulae.count) formulae from all taps")
    }

    /// Process formulae from a specific tap
    private func processFormulaeFromTap(tapPath: URL, tapName: String, parser: FormulaParser, formulae: inout [Formula]) async throws {
        var allFormulaFiles: [(path: URL, name: String)] = []

        // Check if tap organizes formulae in subdirectories (like homebrew/core)
        let items = try FileManager.default.contentsOfDirectory(atPath: tapPath.path)
            .filter { !$0.hasPrefix(".") }

        var hasSubdirectories = false
        for item in items {
            let itemPath = tapPath.appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: itemPath.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                hasSubdirectories = true
                break
            }
        }

        if hasSubdirectories {
            // Process subdirectories (like homebrew/core structure)
            for item in items {
                let itemPath = tapPath.appendingPathComponent(item)
                var isDirectory: ObjCBool = false

                if FileManager.default.fileExists(atPath: itemPath.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                    let files = try FileManager.default.contentsOfDirectory(atPath: itemPath.path)
                        .filter { $0.hasSuffix(".rb") }

                    for file in files {
                        let formulaPath = itemPath.appendingPathComponent(file)
                        let formulaName = String(file.dropLast(3)) // Remove .rb
                        allFormulaFiles.append((path: formulaPath, name: formulaName))
                    }
                } else if item.hasSuffix(".rb") {
                    // Also check for .rb files in the main Formula directory
                    let formulaName = String(item.dropLast(3))
                    allFormulaFiles.append((path: itemPath, name: formulaName))
                }
            }
        } else {
            // Process .rb files directly in Formula directory
            let files = items.filter { $0.hasSuffix(".rb") }
            for file in files {
                let formulaPath = tapPath.appendingPathComponent(file)
                let formulaName = String(file.dropLast(3))
                allFormulaFiles.append((path: formulaPath, name: formulaName))
            }
        }

        let totalFormulae = allFormulaFiles.count
        if totalFormulae == 0 {
            logInfo("No formulae found in \(tapName)")
            return
        }

        var processed = 0
        logInfo("Found \(totalFormulae) formulae in \(tapName)")

        // Process formulae in batches to avoid memory issues
        let batchSize = 100
        for batch in allFormulaFiles.chunked(into: batchSize) {
            await withTaskGroup(of: Formula?.self) { group in
                for formulaInfo in batch {
                    group.addTask {
                        do {
                            let content = try String(contentsOf: formulaInfo.path)
                            return try parser.parse(rubyContent: content, formulaName: formulaInfo.name)
                        } catch {
                            logWarning("Failed to parse \(formulaInfo.name) from \(tapName): \(error)")
                            return nil
                        }
                    }
                }

                for await result in group {
                    if let formula = result {
                        formulae.append(formula)
                    }
                    processed += 1

                    if processed % 100 == 0 {
                        logInfo("Processed \(processed)/\(totalFormulae) formulae from \(tapName)...")
                    }
                }
            }
        }

        logInfo("Completed processing \(processed) formulae from \(tapName)")
    }

    /// Ensure the homebrew/core tap is cloned and up to date
    private func ensureCoreTap() async throws {
        let coreTapPath = pathHelper.tapsPath.appendingPathComponent("homebrew/core")

        if FileManager.default.fileExists(atPath: coreTapPath.path) {
            try await updateCoreTap(at: coreTapPath)
        } else {
            logInfo("Cloning homebrew/core tap...")
            try await cloneCoreTap(to: coreTapPath)
        }
    }

    /// Clone the homebrew/core tap
    private func cloneCoreTap(to path: URL) async throws {
        // Ensure parent directory exists
        let parentPath = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentPath, withIntermediateDirectories: true)

        // Clone the tap using git
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "clone",
            "--depth", "1", // Shallow clone for faster download
            "https://github.com/Homebrew/homebrew-core.git",
            path.path
        ]

        try await runProcess(process, description: "Cloning homebrew/core tap")
    }

    /// Update an existing tap
    private func updateCoreTap(at path: URL) async throws {
        logInfo("Updating homebrew/core tap...")

        // Check if we can update (not in detached HEAD state)
        let statusProcess = Process()
        statusProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        statusProcess.arguments = ["status", "--porcelain=v2", "--branch"]
        statusProcess.currentDirectoryURL = path

        let statusPipe = Pipe()
        statusProcess.standardOutput = statusPipe
        statusProcess.standardError = statusPipe

        do {
            try statusProcess.run()
            statusProcess.waitUntilExit()

            let output = String(data: statusPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            // Check if we're in detached HEAD state
            if output.contains("(no branch)") || output.contains("HEAD detached") {
                logInfo("Tap is in detached HEAD state - skipping update")
                return
            }

            // Perform git pull with timeout (increased for large repos like homebrew/core)
            try await gitPullWithTimeout(at: path, timeoutSeconds: 120)

        } catch {
            logWarning("Failed to update tap: \(error.localizedDescription)")
            logInfo("Continuing with existing tap content")
        }
    }

    private func gitPullWithTimeout(at path: URL, timeoutSeconds: Int) async throws {
        logInfo("Downloading tap updates (this may take up to \(timeoutSeconds) seconds)...")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["pull", "--ff-only"]
        process.currentDirectoryURL = path

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Wait for process with timeout
        let start = Date()
        var lastProgressTime = start
        while process.isRunning {
            let elapsed = Date().timeIntervalSince(start)
            
            // Show progress every 15 seconds
            if Date().timeIntervalSince(lastProgressTime) > 15 {
                logInfo("Still updating tap... (\(Int(elapsed)) seconds elapsed)")
                lastProgressTime = Date()
            }
            
            if elapsed > TimeInterval(timeoutSeconds) {
                process.terminate()
                // Give it a moment to terminate gracefully
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                // If still running, send SIGKILL via kill command
                if process.isRunning {
                    let killProcess = Process()
                    killProcess.executableURL = URL(fileURLWithPath: "/bin/kill")
                    killProcess.arguments = ["-9", "\(process.processIdentifier)"]
                    try? killProcess.run()
                    killProcess.waitUntilExit()
                }

                throw VeloError.processError(
                    command: "git pull",
                    exitCode: -1,
                    description: "Timeout after \(timeoutSeconds) seconds"
                )
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw VeloError.processError(
                command: "git pull",
                exitCode: Int(process.terminationStatus),
                description: errorOutput
            )
        }

        logInfo("Tap updated successfully")
    }

    /// Load test fixtures as fallback
    private func loadTestFixtures(parser: FormulaParser, formulae: inout [Formula]) async throws {
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
    }

    /// Run a process asynchronously
    private func runProcess(_ process: Process, description: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    logInfo("\(description) completed successfully")
                    continuation.resume()
                } else {
                    let error = VeloError.processError(
                        command: process.executableURL?.lastPathComponent ?? "unknown",
                        exitCode: Int(process.terminationStatus),
                        description: "\(description) failed"
                    )
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: VeloError.processError(
                    command: process.executableURL?.lastPathComponent ?? "unknown",
                    exitCode: -1,
                    description: "Failed to start \(description): \(error.localizedDescription)"
                ))
            }
        }
    }

    public func findFormula(_ name: String) throws -> Formula? {
        // Try exact name first from cache
        if let formula = try cache.get(name) {
            return formula
        }

        // Try case-insensitive search in index
        if let actualName = index.find(name) {
            if let formula = try cache.get(actualName) {
                return formula
            }
        }

        // If not in cache, try to parse it directly from the tap
        return try parseFormulaDirectly(name)
    }

    /// Parse a specific formula directly from all available taps without full index
    private func parseFormulaDirectly(_ name: String) throws -> Formula? {
        // Ensure cache directory exists
        try pathHelper.ensureDirectoryExists(at: pathHelper.cachePath)

        let tapsPath = pathHelper.tapsPath
        let parser = FormulaParser()
        let formulaFile = "\(name).rb"

        // Try to find in taps first
        if FileManager.default.fileExists(atPath: tapsPath.path) {
            // Get all available taps and prioritize them
            let availableTaps = try getAvailableTaps(from: tapsPath)
            let prioritizedTaps = prioritizeTaps(availableTaps)

            // Search taps in priority order
            for tapInfo in prioritizedTaps {
                let formulaPath = tapInfo.path.appendingPathComponent("Formula")

                guard FileManager.default.fileExists(atPath: formulaPath.path) else {
                    continue
                }

                // Try to find the formula in this tap
                if let formula = try findFormulaInTap(name: name, formulaFile: formulaFile, tapPath: formulaPath, parser: parser) {
                    logInfo("Successfully parsed \(name) from \(tapInfo.name) tap")
                    return formula
                }
            }
        }

        // Only use test fixtures in development/testing environments
        #if DEBUG
        return try parseFormulaFromFixtures(name: name, parser: parser)
        #else
        return nil
        #endif
    }

    /// Find a formula in a specific tap
    private func findFormulaInTap(name: String, formulaFile: String, tapPath: URL, parser: FormulaParser) throws -> Formula? {
        var possiblePaths: [URL] = []

        // First try common locations
        let firstLetter = String(name.prefix(1)).lowercased()
        possiblePaths.append(tapPath.appendingPathComponent(firstLetter).appendingPathComponent(formulaFile))
        possiblePaths.append(tapPath.appendingPathComponent(formulaFile))

        // If not found, search all subdirectories
        if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: tapPath.path) {
            for subdir in subdirs.filter({ !$0.hasPrefix(".") }) {
                let subdirPath = tapPath.appendingPathComponent(subdir)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: subdirPath.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                    possiblePaths.append(subdirPath.appendingPathComponent(formulaFile))
                }
            }
        }

        for formulaPath in possiblePaths {
            if FileManager.default.fileExists(atPath: formulaPath.path) {
                do {
                    let content = try String(contentsOf: formulaPath)
                    let formula = try parser.parse(rubyContent: content, formulaName: name)

                    // Cache the parsed formula for future use
                    try cache.set(formula)

                    return formula
                } catch {
                    logWarning("Failed to parse \(name) from \(formulaPath.path): \(error)")
                }
            }
        }

        return nil
    }

    /// Parse a specific formula from test fixtures
    private func parseFormulaFromFixtures(name: String, parser: FormulaParser) throws -> Formula? {
        let fixturesPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Formulae")

        guard FileManager.default.fileExists(atPath: fixturesPath.path) else {
            return nil
        }

        let formulaFile = "\(name).rb"
        let formulaPath = fixturesPath.appendingPathComponent(formulaFile)

        guard FileManager.default.fileExists(atPath: formulaPath.path) else {
            return nil
        }

        do {
            let content = try String(contentsOf: formulaPath)
            let formula = try parser.parse(rubyContent: content, formulaName: name)

            // Cache the parsed formula for future use
            try cache.set(formula)

            logInfo("Successfully parsed \(name) from test fixtures")
            return formula
        } catch {
            logWarning("Failed to parse \(name) from test fixtures: \(error)")
            return nil
        }
    }

    /// Get all available taps
    private func getAvailableTaps(from tapsPath: URL) throws -> [TapReference] {
        var taps: [TapReference] = []

        let organizations = try FileManager.default.contentsOfDirectory(atPath: tapsPath.path)
            .filter { !$0.hasPrefix(".") }

        for org in organizations {
            let orgPath = tapsPath.appendingPathComponent(org)
            let repos = (try? FileManager.default.contentsOfDirectory(atPath: orgPath.path)) ?? []

            for repo in repos.filter({ !$0.hasPrefix(".") }) {
                let tapPath = orgPath.appendingPathComponent(repo)
                let tapName = "\(org)/\(repo)"

                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: tapPath.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }

                taps.append(TapReference(name: tapName, path: tapPath))
            }
        }

        return taps
    }

    /// Prioritize taps for formula resolution
    /// homebrew/core has highest priority, then other homebrew taps, then third-party taps
    private func prioritizeTaps(_ taps: [TapReference]) -> [TapReference] {
        return taps.sorted { tap1, tap2 in
            // homebrew/core always comes first
            if tap1.name == "homebrew/core" { return true }
            if tap2.name == "homebrew/core" { return false }

            // Other homebrew taps come next
            let tap1IsHomebrew = tap1.name.hasPrefix("homebrew/")
            let tap2IsHomebrew = tap2.name.hasPrefix("homebrew/")

            if tap1IsHomebrew && !tap2IsHomebrew { return true }
            if !tap1IsHomebrew && tap2IsHomebrew { return false }

            // Within the same category, sort alphabetically
            return tap1.name.localizedCompare(tap2.name) == .orderedAscending
        }
    }

    public func searchFormulae(_ term: String, includeDescriptions: Bool = false) -> [String] {
        return index.search(term, includeDescriptions: includeDescriptions)
    }

    public func cacheStatistics() -> CacheStatistics {
        return cache.statistics()
    }
}

// MARK: - Supporting Types

private struct TapReference {
    let name: String
    let path: URL
}
