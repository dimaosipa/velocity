import Foundation

public enum LogLevel: Int, Comparable {
    case verbose = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var icon: String {
        switch self {
        case .verbose: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        }
    }

    var prefix: String {
        switch self {
        case .verbose: return "VERBOSE"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        }
    }
}

public final class Logger {
    public static let shared = Logger()

    public var logLevel: LogLevel = .info
    public var enableTimestamps = false
    public var enableColors = true

    private let queue = DispatchQueue(label: "com.velo.logger", qos: .utility)
    private var logFile: FileHandle?

    private init() {}

    public func setLogFile(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        FileManager.default.createFile(atPath: path, contents: nil)
        logFile = try FileHandle(forWritingTo: url)
    }

    public func verbose(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .verbose, file: file, line: line)
    }

    public func info(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .info, file: file, line: line)
    }

    public func warning(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .warning, file: file, line: line)
    }

    public func error(_ message: String, file: String = #file, line: Int = #line) {
        log(message, level: .error, file: file, line: line)
    }

    public func progress(_ message: String) {
        // Progress messages are always shown
        print("\r\(message)", terminator: "")
        fflush(stdout)
    }

    public func success(_ message: String) {
        print("\n✅ \(message)")
    }

    private func log(_ message: String, level: LogLevel, file: String, line: Int) {
        guard level >= logLevel else { return }

        queue.async { [weak self] in
            let timestamp = self?.enableTimestamps ?? false ? "[\(Date().ISO8601Format())] " : ""
            let location = level == .verbose ? " [\(URL(fileURLWithPath: file).lastPathComponent):\(line)]" : ""

            let formattedMessage = "\(timestamp)\(level.icon) \(level.prefix): \(message)\(location)"

            // Console output
            if self?.enableColors ?? true {
                let coloredMessage = self?.colorize(formattedMessage, level: level) ?? formattedMessage
                print(coloredMessage)
            } else {
                print(formattedMessage)
            }

            // File output
            if let data = "\(formattedMessage)\n".data(using: .utf8) {
                self?.logFile?.write(data)
            }
        }
    }

    private func colorize(_ message: String, level: LogLevel) -> String {
        let colorCode: String
        switch level {
        case .verbose: return message // No color for verbose
        case .info: return message // No color for info
        case .warning: colorCode = "33" // Yellow
        case .error: colorCode = "31" // Red
        }
        return "\u{001B}[0;\(colorCode)m\(message)\u{001B}[0m"
    }
}

// Convenience global functions
public func logVerbose(_ message: String, file: String = #file, line: Int = #line) {
    Logger.shared.verbose(message, file: file, line: line)
}

public func logInfo(_ message: String, file: String = #file, line: Int = #line) {
    Logger.shared.info(message, file: file, line: line)
}

public func logWarning(_ message: String, file: String = #file, line: Int = #line) {
    Logger.shared.warning(message, file: file, line: line)
}

public func logError(_ message: String, file: String = #file, line: Int = #line) {
    Logger.shared.error(message, file: file, line: line)
}
