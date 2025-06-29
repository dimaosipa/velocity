import Foundation

public struct NotificationHelper {
    private static let soundPath = "/System/Library/Sounds/Glass.aiff"

    public static func requestUserAttention(reason: String) {
        // Play sound
        playSound()

        // Log reason with visual separator
        print("\n" + String(repeating: "=", count: 80))
        print("🔔 ATTENTION NEEDED: \(reason)")
        print(String(repeating: "=", count: 80) + "\n")
    }

    public static func playSound() {
        let process = Process()
        process.launchPath = "/usr/bin/afplay"
        process.arguments = [soundPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            // Silently fail if sound can't be played
            Logger.shared.verbose("Failed to play notification sound: \(error)")
        }
    }

    public static func notifySuccess(_ message: String, playSound: Bool = false) {
        if playSound {
            self.playSound()
        }
        Logger.shared.success(message)
    }

    public static func notifyCompletion(_ taskName: String) {
        playSound()
        print("\n✨ Completed: \(taskName)")
    }
}
