import Foundation
import os.log

public enum LogLevel: String, CaseIterable {
    case essential = "essential"  // Default: Errors, warnings, essential progress
    case verbose = "verbose"      // Detailed debugging information
    case debug = "debug"         // Maximum detail including progress spam
    
    var osLogLevel: OSLogType {
        switch self {
        case .essential:
            return .default
        case .verbose:
            return .info
        case .debug:
            return .debug
        }
    }
}

public final class OSLogger {
    public static let shared = OSLogger()
    
    // Category-based loggers for filtering
    public let installer = Logger(subsystem: "com.velo", category: "installer")
    public let parser = Logger(subsystem: "com.velo", category: "parser")
    public let repair = Logger(subsystem: "com.velo", category: "repair")
    public let download = Logger(subsystem: "com.velo", category: "download")
    public let general = Logger(subsystem: "com.velo", category: "general")
    
    private let currentLogLevel: LogLevel
    
    private init() {
        // Read log level from environment variable
        if let envLevel = ProcessInfo.processInfo.environment["VELO_LOG_LEVEL"],
           let level = LogLevel(rawValue: envLevel.lowercased()) {
            self.currentLogLevel = level
        } else {
            self.currentLogLevel = .essential
        }
    }
    
    // MARK: - Essential Messages (Always Shown)
    
    public func info(_ message: String, category: Logger = OSLogger.shared.general) {
        category.info("\(message)")
    }
    
    public func warning(_ message: String, category: Logger = OSLogger.shared.general) {
        category.warning("\(message)")
    }
    
    public func error(_ message: String, category: Logger = OSLogger.shared.general) {
        category.error("\(message)")
    }
    
    public func success(_ message: String) {
        print("✅ \(message)")
    }
    
    // MARK: - Level-Controlled Messages
    
    public func verbose(_ message: String, category: Logger = OSLogger.shared.general) {
        guard shouldLog(.verbose) else { return }
        category.info("🔍 VERBOSE: \(message)")
    }
    
    public func debug(_ message: String, category: Logger = OSLogger.shared.general) {
        guard shouldLog(.debug) else { return }
        category.info("🐛 DEBUG: \(message)")
    }
    
    // MARK: - Progress Reporting
    
    public func progress(_ message: String) {
        // Progress messages are always shown but don't use os_log (real-time requirement)
        print("\r\(message)", terminator: "")
        fflush(stdout)
    }
    
    // MARK: - Level Management
    
    public func shouldLog(_ level: LogLevel) -> Bool {
        switch (currentLogLevel, level) {
        case (.essential, .essential):
            return true
        case (.verbose, .essential), (.verbose, .verbose):
            return true
        case (.debug, _):
            return true
        default:
            return false
        }
    }
    
    public var logLevel: LogLevel {
        return currentLogLevel
    }
}

// MARK: - Category-Specific Convenience Extensions

extension OSLogger {
    // Installer category logging
    public func installerInfo(_ message: String) {
        installer.info("\(message)")
    }
    
    public func installerWarning(_ message: String) {
        installer.warning("\(message)")
    }
    
    public func installerError(_ message: String) {
        installer.error("\(message)")
    }
    
    // Parser category logging (critical for Homebrew compatibility)
    public func parserInfo(_ message: String) {
        parser.info("\(message)")
    }
    
    public func parserWarning(_ message: String) {
        // Formula parsing failures are ALWAYS shown - critical for Homebrew compatibility
        parser.warning("⚠️ PARSER: \(message)")
    }
    
    public func parserError(_ message: String) {
        // Formula parsing errors are ALWAYS shown - critical for debugging
        parser.error("❌ PARSER: \(message)")
    }
    
    public func parserVerbose(_ message: String) {
        guard shouldLog(.verbose) else { return }
        parser.info("🔍 PARSER: \(message)")
    }
    
    // Repair category logging
    public func repairInfo(_ message: String) {
        repair.info("\(message)")
    }
    
    public func repairWarning(_ message: String) {
        // Repair issues are ALWAYS shown - indicate missing patterns
        repair.warning("⚠️ REPAIR: \(message)")
    }
    
    public func repairError(_ message: String) {
        repair.error("❌ REPAIR: \(message)")
    }
    
    // Download category logging
    public func downloadInfo(_ message: String) {
        download.info("\(message)")
    }
    
    public func downloadWarning(_ message: String) {
        download.warning("\(message)")
    }
    
    public func downloadError(_ message: String) {
        download.error("\(message)")
    }
    
    public func downloadVerbose(_ message: String) {
        guard shouldLog(.verbose) else { return }
        download.info("🔍 DOWNLOAD: \(message)")
    }
}