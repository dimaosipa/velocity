import Foundation

public enum VeloError: LocalizedError {
    // Formula errors
    case formulaNotFound(name: String)
    case formulaParseError(formula: String, details: String)
    case invalidFormulaFormat(details: String)
    case versionNotAvailable(package: String, requestedVersion: String, availableVersion: String)

    // Download errors
    case downloadFailed(url: String, error: Error)
    case checksumMismatch(expected: String, actual: String)
    case networkError(Error)
    case bottleNotAccessible(url: String, reason: String)

    // Installation errors
    case installationFailed(package: String, reason: String)
    case alreadyInstalled(package: String)
    case extractionFailed(reason: String)
    case symlinkFailed(from: String, to: String)

    // System errors
    case unsupportedArchitecture(current: String)
    case insufficientPermissions(path: String)
    case pathNotFound(path: String)
    case ioError(Error)

    // Dependency errors
    case dependencyNotFound(dependency: String, package: String)
    case circularDependency(packages: [String])

    // Tap errors
    case tapCloneFailed(url: String, error: Error)
    case tapUpdateFailed(tap: String, error: Error)
    case tapNotFound(name: String)
    case invalidTapName(String)

    // Process errors
    case processError(command: String, exitCode: Int, description: String)

    // Library path errors
    case libraryPathRewriteFailed(binary: String, reason: String)

    // Project context errors
    case notInProjectContext

    // Update errors
    case updateCheckFailed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .formulaNotFound(let name):
            return "Formula not found: \(name)"
        case .formulaParseError(let formula, let details):
            return "Failed to parse formula '\(formula)': \(details)"
        case .invalidFormulaFormat(let details):
            return "Invalid formula format: \(details)"
        case .versionNotAvailable(let package, let requestedVersion, let availableVersion):
            return "Version \(requestedVersion) of '\(package)' is not available. Available version: \(availableVersion)"
        case .downloadFailed(let url, let error):
            return "Download failed for \(url): \(error.localizedDescription)"
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch. Expected: \(expected), got: \(actual)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .bottleNotAccessible(let url, let reason):
            return "Bottle not accessible at \(url): \(reason)"
        case .installationFailed(let package, let reason):
            return "Installation failed for '\(package)': \(reason)"
        case .alreadyInstalled(let package):
            return "Package '\(package)' is already installed"
        case .extractionFailed(let reason):
            return "Extraction failed: \(reason)"
        case .symlinkFailed(let from, let to):
            return "Failed to create symlink from \(from) to \(to)"
        case .unsupportedArchitecture(let current):
            return "Unsupported architecture: \(current). Velo requires Apple Silicon (arm64)"
        case .insufficientPermissions(let path):
            return "Insufficient permissions for path: \(path)"
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .ioError(let error):
            return "I/O error: \(error.localizedDescription)"
        case .dependencyNotFound(let dependency, let package):
            return "Dependency '\(dependency)' not found for package '\(package)'"
        case .circularDependency(let packages):
            return "Circular dependency detected: \(packages.joined(separator: " → "))"
        case .tapCloneFailed(let url, let error):
            return "Failed to clone tap from \(url): \(error.localizedDescription)"
        case .tapUpdateFailed(let tap, let error):
            return "Failed to update tap '\(tap)': \(error.localizedDescription)"
        case .tapNotFound(let name):
            return "Tap not found: \(name)"
        case .invalidTapName(let name):
            return "Invalid tap name: '\(name)'. Use format 'user/repo' or full GitHub URL."
        case .processError(let command, let exitCode, let description):
            return "Process '\(command)' failed with exit code \(exitCode): \(description)"
        case .libraryPathRewriteFailed(let binary, let reason):
            return "Failed to rewrite library paths for '\(binary)': \(reason)"
        case .notInProjectContext:
            return "Not in a project context. Run 'velo init' to create a velo.json file."
        case .updateCheckFailed(let reason):
            return "Update check failed: \(reason)"
        }
    }
}
