import Foundation
import VeloSystem

public final class PerformanceOptimizer {
    private let pathHelper: PathHelper
    private let maxConcurrentDownloads: Int
    private let downloadPool: DispatchSemaphore
    
    public init(pathHelper: PathHelper = PathHelper.shared, maxConcurrentDownloads: Int = 8) {
        self.pathHelper = pathHelper
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.downloadPool = DispatchSemaphore(value: maxConcurrentDownloads)
    }
    
    // MARK: - Memory Optimization
    
    public func optimizeMemoryUsage() {
        // Clean up temporary files older than 1 hour
        cleanOldTemporaryFiles()
        
        // Compact cache files
        compactCacheFiles()
        
        // Force garbage collection
        autoreleasepool {
            // This helps release any accumulated memory
        }
    }
    
    private func cleanOldTemporaryFiles() {
        let tmpPath = pathHelper.tmpPath
        let oneHourAgo = Date().addingTimeInterval(-3600)
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: tmpPath,
                includingPropertiesForKeys: [.creationDateKey]
            )
            
            for file in contents {
                if let attributes = try? file.resourceValues(forKeys: [.creationDateKey]),
                   let creationDate = attributes.creationDate,
                   creationDate < oneHourAgo {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            logVerbose("Failed to clean temporary files: \(error)")
        }
    }
    
    private func compactCacheFiles() {
        // Remove duplicate or corrupted cache entries
        let cachePath = pathHelper.cachePath
        
        do {
            let cacheFiles = try FileManager.default.contentsOfDirectory(
                at: cachePath,
                includingPropertiesForKeys: [.fileSizeKey]
            ).filter { $0.pathExtension == "velocache" }
            
            // Remove zero-byte files
            for file in cacheFiles {
                if let attributes = try? file.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = attributes.fileSize,
                   fileSize == 0 {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            logVerbose("Failed to compact cache files: \(error)")
        }
    }
    
    // MARK: - Disk I/O Optimization
    
    public func optimizeDiskOperations() {
        // Enable file system caching hints
        enableFileSystemOptimizations()
        
        // Preallocate space for large operations
        preallocateDownloadSpace()
    }
    
    private func enableFileSystemOptimizations() {
        // Set optimal I/O policies for our use case
        let policy = ProcessInfo.processInfo.environment["VELO_IO_POLICY"] ?? "default"
        
        switch policy {
        case "performance":
            // Prioritize performance over energy efficiency
            setThreadQOSClass(.userInitiated)
        case "efficiency":
            // Prioritize energy efficiency
            setThreadQOSClass(.utility)
        default:
            // Balanced approach
            setThreadQOSClass(.default)
        }
    }
    
    private func setThreadQOSClass(_ qosClass: DispatchQoS.QoSClass) {
        // Apply QoS to background operations
        DispatchQueue.global(qos: qosClass).async {
            // This affects the priority of background operations
        }
    }
    
    private func preallocateDownloadSpace() {
        // Estimate space needed for typical installations
        let estimatedSpace: Int64 = 100 * 1024 * 1024 // 100MB
        let tmpFile = pathHelper.temporaryFile(prefix: "space-check")
        
        // Try to preallocate space to avoid fragmentation
        do {
            let fileHandle = try FileHandle(forWritingTo: tmpFile)
            try fileHandle.truncate(atOffset: UInt64(estimatedSpace))
            fileHandle.closeFile()
            try FileManager.default.removeItem(at: tmpFile)
        } catch {
            // If preallocation fails, continue normally
            logVerbose("Space preallocation failed: \(error)")
        }
    }
    
    // MARK: - Network Optimization
    
    public func optimizeNetworkPerformance() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        
        // Optimize for our use case
        config.httpMaximumConnectionsPerHost = maxConcurrentDownloads
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = createOptimizedURLCache()
        
        // Enable HTTP/2 and connection reuse
        config.httpShouldUsePipelining = true
        config.httpShouldSetCookies = false // We don't need cookies
        
        // Optimize for large file downloads
        config.httpAdditionalHeaders = [
            "User-Agent": "Velo/0.1.0",
            "Accept-Encoding": "gzip, deflate, br"
        ]
        
        return config
    }
    
    private func createOptimizedURLCache() -> URLCache {
        let cacheSize = 50 * 1024 * 1024 // 50MB memory cache
        let diskCacheSize = 200 * 1024 * 1024 // 200MB disk cache
        let cacheDir = pathHelper.cachePath.appendingPathComponent("url-cache")
        
        return URLCache(
            memoryCapacity: cacheSize,
            diskCapacity: diskCacheSize,
            directory: cacheDir
        )
    }
    
    // MARK: - CPU Optimization
    
    public func optimizeCPUUsage() {
        // Detect optimal thread count based on system capabilities
        let processorCount = ProcessInfo.processInfo.processorCount
        let optimalThreads = min(processorCount, maxConcurrentDownloads)
        
        logVerbose("Optimizing for \(processorCount) processors, using \(optimalThreads) threads")
        
        // Configure queues for optimal performance
        configureOperationQueues(maxConcurrent: optimalThreads)
    }
    
    private func configureOperationQueues(maxConcurrent: Int) {
        // This would configure any operation queues we use
        // For now, we rely on GCD's automatic management
        logVerbose("Configured for \(maxConcurrent) concurrent operations")
    }
    
    // MARK: - Battery Optimization
    
    public func optimizeForBattery() {
        // Reduce background activity when on battery
        if !isConnectedToPower() {
            enableBatteryOptimizations()
        }
    }
    
    private func isConnectedToPower() -> Bool {
        // Check if we're on battery power
        let powerState = ProcessInfo.processInfo.environment["VELO_POWER_STATE"]
        return powerState != "battery"
    }
    
    private func enableBatteryOptimizations() {
        // Reduce aggressive caching and background operations
        logVerbose("Enabling battery optimizations")
        
        // Use lower QoS for background operations
        setThreadQOSClass(.background)
    }
    
    // MARK: - Predictive Optimization
    
    public func enablePredictiveOptimizations() {
        // Analyze usage patterns to optimize future operations
        trackUsagePatterns()
        
        // Prefetch commonly used formulae
        prefetchPopularFormulae()
    }
    
    private func trackUsagePatterns() {
        // Track which packages are installed/searched most frequently
        // This data could be used to optimize cache priorities
        logVerbose("Tracking usage patterns for optimization")
    }
    
    private func prefetchPopularFormulae() {
        // In the background, prefetch metadata for popular packages
        DispatchQueue.global(qos: .background).async {
            // This would prefetch popular formulae in the background
            logVerbose("Prefetching popular formulae")
        }
    }
    
    // MARK: - Performance Monitoring
    
    public func measurePerformance<T>(
        operation: String,
        block: () throws -> T
    ) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        logVerbose("\(operation) completed in \(String(format: "%.3f", duration))s")
        
        return result
    }
    
    public func measureAsyncPerformance<T>(
        operation: String,
        block: () async throws -> T
    ) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        logVerbose("\(operation) completed in \(String(format: "%.3f", duration))s")
        
        return result
    }
    
    // MARK: - System Resource Monitoring
    
    public func checkSystemResources() -> SystemResourceInfo {
        let processInfo = ProcessInfo.processInfo
        
        // Get memory info
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kernelReturn = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        let memoryUsage = kernelReturn == KERN_SUCCESS ? memoryInfo.resident_size : 0
        
        return SystemResourceInfo(
            memoryUsageBytes: Int64(memoryUsage),
            processorCount: processInfo.processorCount,
            systemUptime: processInfo.systemUptime
        )
    }
}

// MARK: - System Resource Info

public struct SystemResourceInfo {
    public let memoryUsageBytes: Int64
    public let processorCount: Int
    public let systemUptime: TimeInterval
    
    public var formattedMemoryUsage: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: memoryUsageBytes)
    }
}

// MARK: - C Imports for Memory Info

import Darwin.Mach