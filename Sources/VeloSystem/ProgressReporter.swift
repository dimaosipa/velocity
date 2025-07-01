import Foundation
import os.log

// MARK: - Progress Reporter

public final class ProgressReporter {
    public static let shared = ProgressReporter()
    
    private var currentStep: String = ""
    private var currentProgress: Double = 0.0
    private var isActive: Bool = false
    private let progressBarWidth: Int = 30
    
    private init() {}
    
    // MARK: - Step Management
    
    public func startStep(_ step: String) {
        currentStep = step
        currentProgress = 0.0
        isActive = true
        printProgress()
    }
    
    public func updateProgress(_ progress: Double, message: String? = nil) {
        currentProgress = min(max(progress, 0.0), 1.0)
        if let msg = message {
            currentStep = msg
        }
        printProgress()
    }
    
    public func completeStep(_ message: String? = nil) {
        currentProgress = 1.0
        if let msg = message {
            currentStep = msg
        }
        printProgress()
        print("") // New line after completion
        isActive = false
    }
    
    public func failStep(_ message: String) {
        currentStep = message
        print("\r\u{001B}[K❌ \(message)")
        isActive = false
    }
    
    // MARK: - Visual Progress
    
    private func printProgress() {
        guard isActive else { return }
        
        let percentage = Int(currentProgress * 100)
        let completedWidth = Int(Double(progressBarWidth) * currentProgress)
        let remainingWidth = progressBarWidth - completedWidth
        
        let progressBar = String(repeating: "█", count: completedWidth) + 
                         String(repeating: "░", count: remainingWidth)
        
        let emoji = getStepEmoji()
        let output = "\r\u{001B}[K\(emoji) \(currentStep) [\(progressBar)] \(percentage)%"
        
        print(output, terminator: "")
        fflush(stdout)
    }
    
    private func getStepEmoji() -> String {
        let step = currentStep.lowercased()
        
        if step.contains("resolv") || step.contains("graph") {
            return "🔍"
        } else if step.contains("download") {
            return "⬇️"
        } else if step.contains("extract") {
            return "📦"
        } else if step.contains("install") {
            return "🔧"
        } else if step.contains("link") {
            return "🔗"
        } else if step.contains("repair") {
            return "🛠️"
        } else if currentProgress >= 1.0 {
            return "✅"
        } else {
            return "⚙️"
        }
    }
}

// MARK: - Multi-Step Progress Manager

public final class MultiStepProgress {
    private let steps: [String]
    private var currentStepIndex: Int = 0
    private let reporter = ProgressReporter.shared
    
    public init(steps: [String]) {
        self.steps = steps
    }
    
    public func startNextStep() {
        guard currentStepIndex < steps.count else { return }
        
        let step = steps[currentStepIndex]
        let stepNumber = currentStepIndex + 1
        let totalSteps = steps.count
        
        reporter.startStep("[\(stepNumber)/\(totalSteps)] \(step)")
    }
    
    public func updateCurrentStep(progress: Double, message: String? = nil) {
        let stepNumber = currentStepIndex + 1
        let totalSteps = steps.count
        let stepMessage = message ?? steps[currentStepIndex]
        
        reporter.updateProgress(progress, message: "[\(stepNumber)/\(totalSteps)] \(stepMessage)")
    }
    
    public func completeCurrentStep() {
        guard currentStepIndex < steps.count else { return }
        
        let stepNumber = currentStepIndex + 1
        let totalSteps = steps.count
        let step = steps[currentStepIndex]
        
        reporter.completeStep("[\(stepNumber)/\(totalSteps)] \(step) ✓")
        currentStepIndex += 1
    }
    
    public func failCurrentStep(_ message: String) {
        let stepNumber = currentStepIndex + 1
        let totalSteps = steps.count
        
        reporter.failStep("[\(stepNumber)/\(totalSteps)] \(message)")
    }
    
    public var isComplete: Bool {
        return currentStepIndex >= steps.count
    }
}

// MARK: - Download Progress Tracker

public final class DownloadProgressTracker {
    private let packageCount: Int
    private var completedPackages: Int = 0
    private var currentPackage: String = ""
    private var currentBytes: Int64 = 0
    private var totalBytes: Int64 = 0
    private let reporter = ProgressReporter.shared
    
    public init(packageCount: Int) {
        self.packageCount = packageCount
    }
    
    public func startDownloads() {
        reporter.startStep("Downloading \(packageCount) packages")
    }
    
    public func startPackageDownload(_ package: String, totalSize: Int64?) {
        currentPackage = package
        currentBytes = 0
        totalBytes = totalSize ?? 0
        updateProgress()
    }
    
    public func updatePackageDownload(_ package: String, bytesDownloaded: Int64, totalBytes: Int64?) {
        if package == currentPackage {
            currentBytes = bytesDownloaded
            self.totalBytes = totalBytes ?? self.totalBytes
            updateProgress()
        }
    }
    
    public func completePackageDownload(_ package: String, success: Bool) {
        if package == currentPackage && success {
            completedPackages += 1
            updateProgress()
        }
    }
    
    public func completeAllDownloads() {
        reporter.completeStep("Downloaded \(completedPackages)/\(packageCount) packages")
    }
    
    private func updateProgress() {
        let packageProgress = Double(completedPackages) + (totalBytes > 0 ? Double(currentBytes) / Double(totalBytes) : 0.0)
        let overallProgress = packageProgress / Double(packageCount)
        
        let sizeInfo = totalBytes > 0 ? " (\(formatBytes(currentBytes))/\(formatBytes(totalBytes)))" : ""
        let message = "Downloading \(currentPackage)\(sizeInfo) (\(completedPackages)/\(packageCount))"
        
        reporter.updateProgress(overallProgress, message: message)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Installation Progress Tracker

public final class InstallationProgressTracker {
    private let packageNames: [String]
    private var currentPackageIndex: Int = 0
    private var currentPhase: String = "starting"
    private let reporter = ProgressReporter.shared
    
    public init(packageNames: [String]) {
        self.packageNames = packageNames
    }
    
    public func startInstallation() {
        reporter.startStep("Installing \(packageNames.count) packages")
    }
    
    public func startPackageInstallation(_ package: String) {
        if let index = packageNames.firstIndex(of: package) {
            currentPackageIndex = index
        }
        currentPhase = "installing"
        updateProgress(phase: "Installing \(package)")
    }
    
    public func updatePhase(_ phase: String) {
        currentPhase = phase
        updateProgress(phase: phase)
    }
    
    public func completePackageInstallation(_ package: String) {
        currentPackageIndex += 1
        updateProgress(phase: "Completed \(package)")
    }
    
    public func completeAllInstallations() {
        reporter.completeStep("Installed \(packageNames.count) packages")
    }
    
    private func updateProgress(phase: String) {
        let progress = Double(currentPackageIndex) / Double(packageNames.count)
        let message = "\(phase) (\(currentPackageIndex)/\(packageNames.count))"
        reporter.updateProgress(progress, message: message)
    }
}