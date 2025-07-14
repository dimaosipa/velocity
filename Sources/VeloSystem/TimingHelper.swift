import Foundation

// MARK: - Timing Helper

public struct TimingHelper {
    /// Format duration in seconds to a human-readable string with 1 decimal place
    public static func formatDuration(_ duration: TimeInterval) -> String {
        return String(format: "%.1f", duration)
    }

    /// Create a timing message in the standard format: "operation in X.Xs"
    public static func timingMessage(for operation: String, duration: TimeInterval) -> String {
        return "\(operation) in \(formatDuration(duration))s"
    }

    /// Create a success message with timing in the standard format: "✓ operation in X.Xs"
    public static func successMessage(for operation: String, duration: TimeInterval) -> String {
        return "✓ \(timingMessage(for: operation, duration: duration))"
    }
}

// MARK: - Date Extension for Timing

public extension Date {
    /// Calculate duration since this date and format it
    func formattedDurationSince() -> String {
        let duration = Date().timeIntervalSince(self)
        return TimingHelper.formatDuration(duration)
    }

    /// Create a timing message from this start time
    func timingMessage(for operation: String) -> String {
        let duration = Date().timeIntervalSince(self)
        return TimingHelper.timingMessage(for: operation, duration: duration)
    }

    /// Create a success message with timing from this start time
    func successMessage(for operation: String) -> String {
        let duration = Date().timeIntervalSince(self)
        return TimingHelper.successMessage(for: operation, duration: duration)
    }
}

// MARK: - Command Timing Protocol

public protocol TimedCommand {
    var startTime: Date { get set }

    mutating func startTiming()
    func getTimingDuration() -> TimeInterval
    func formatTiming(for operation: String) -> String
}

public extension TimedCommand {
    mutating func startTiming() {
        startTime = Date()
    }

    func getTimingDuration() -> TimeInterval {
        return Date().timeIntervalSince(startTime)
    }

    func formatTiming(for operation: String) -> String {
        return startTime.timingMessage(for: operation)
    }

    func formatSuccess(for operation: String) -> String {
        return startTime.successMessage(for: operation)
    }
}
