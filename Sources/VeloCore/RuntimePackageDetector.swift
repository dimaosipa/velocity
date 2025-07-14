import Foundation
import VeloSystem

// MARK: - Runtime Package Types

public enum RuntimeType {
    case python
    case nodejs
    case ruby
    case java
    case unknown
}

public struct RuntimeEnvironment {
    public let type: RuntimeType
    public let interpreterPath: String
    public let environmentVariables: [String: String]
    public let requiresWrapper: Bool

    public init(type: RuntimeType, interpreterPath: String, environmentVariables: [String: String] = [:], requiresWrapper: Bool = true) {
        self.type = type
        self.interpreterPath = interpreterPath
        self.environmentVariables = environmentVariables
        self.requiresWrapper = requiresWrapper
    }
}

// MARK: - Runtime Package Detector

public final class RuntimePackageDetector {
    private let fileManager = FileManager.default

    public init() {}

    /// Detect if a package contains runtime environment that needs isolation
    public func detectRuntime(packageDir: URL, packageName: String) -> RuntimeEnvironment? {
        OSLogger.shared.debug("Detecting runtime for package \(packageName) at \(packageDir.path)", category: OSLogger.shared.installer)

        // Check for Python virtual environment
        if let pythonRuntime = detectPythonRuntime(packageDir: packageDir, packageName: packageName) {
            OSLogger.shared.debug("Detected Python runtime for \(packageName)", category: OSLogger.shared.installer)
            return pythonRuntime
        }

        // Check for Node.js runtime
        if let nodeRuntime = detectNodeJSRuntime(packageDir: packageDir, packageName: packageName) {
            OSLogger.shared.debug("Detected Node.js runtime for \(packageName)", category: OSLogger.shared.installer)
            return nodeRuntime
        }

        // Check for Ruby runtime
        if let rubyRuntime = detectRubyRuntime(packageDir: packageDir, packageName: packageName) {
            OSLogger.shared.debug("Detected Ruby runtime for \(packageName)", category: OSLogger.shared.installer)
            return rubyRuntime
        }

        // Check for Java runtime
        if let javaRuntime = detectJavaRuntime(packageDir: packageDir, packageName: packageName) {
            OSLogger.shared.debug("Detected Java runtime for \(packageName)", category: OSLogger.shared.installer)
            return javaRuntime
        }

        OSLogger.shared.debug("No runtime detected for package \(packageName)", category: OSLogger.shared.installer)
        return nil
    }

    // MARK: - Python Detection

    private func detectPythonRuntime(packageDir: URL, packageName: String) -> RuntimeEnvironment? {
        let libexecDir = packageDir.appendingPathComponent("libexec")

        // Check for pyvenv.cfg (Python virtual environment)
        let pyvenvConfig = libexecDir.appendingPathComponent("pyvenv.cfg")
        OSLogger.shared.debug("Checking for pyvenv.cfg at \(pyvenvConfig.path)", category: OSLogger.shared.installer)
        if fileManager.fileExists(atPath: pyvenvConfig.path) {
            OSLogger.shared.debug("Found pyvenv.cfg, creating Python virtual environment", category: OSLogger.shared.installer)
            return createPythonEnvironment(packageDir: packageDir, packageName: packageName, isVirtualEnv: true)
        }

        // Check for lib/python* directories (embedded Python)
        let libDir = packageDir.appendingPathComponent("lib")
        if fileManager.fileExists(atPath: libDir.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(atPath: libDir.path)
                if contents.contains(where: { $0.hasPrefix("python") }) {
                    return createPythonEnvironment(packageDir: packageDir, packageName: packageName, isVirtualEnv: false)
                }
            } catch {
                OSLogger.shared.debug("Could not read lib directory: \(error)", category: OSLogger.shared.installer)
            }
        }

        // Check for common Python package indicators
        if packageName.contains("python") || packageName.hasSuffix("-py") {
            // Look for Python executables in bin/
            let binDir = packageDir.appendingPathComponent("bin")
            if fileManager.fileExists(atPath: binDir.path) {
                do {
                    let contents = try fileManager.contentsOfDirectory(atPath: binDir.path)
                    if contents.contains(where: { $0.hasPrefix("python") || $0.hasSuffix(".py") }) {
                        return createPythonEnvironment(packageDir: packageDir, packageName: packageName, isVirtualEnv: false)
                    }
                } catch {
                    OSLogger.shared.debug("Could not read bin directory: \(error)", category: OSLogger.shared.installer)
                }
            }
        }

        return nil
    }

    private func createPythonEnvironment(packageDir: URL, packageName: String, isVirtualEnv: Bool) -> RuntimeEnvironment {
        var interpreterPath = packageDir.appendingPathComponent("bin/python3").path

        // Check for libexec/bin/python3 (common in Homebrew packages)
        let libexecPython = packageDir.appendingPathComponent("libexec/bin/python3")
        if fileManager.fileExists(atPath: libexecPython.path) {
            interpreterPath = libexecPython.path
        }

        var environmentVariables: [String: String] = [:]

        if isVirtualEnv {
            // For virtual environments, set VIRTUAL_ENV and adjust PYTHONPATH
            let libexecDir = packageDir.appendingPathComponent("libexec")
            environmentVariables["VIRTUAL_ENV"] = libexecDir.path
            environmentVariables["PYTHONHOME"] = "" // Unset PYTHONHOME for virtual envs

            // Add virtual env site-packages to PYTHONPATH
            // Find the Python version directory in lib/ (e.g., python3.13)
            let libDir = libexecDir.appendingPathComponent("lib")
            var sitePackagesPath = libDir.path

            // Look for python version directories
            if let pythonDirs = try? fileManager.contentsOfDirectory(atPath: libDir.path) {
                if let pythonVersionDir = pythonDirs.first(where: { $0.hasPrefix("python") }) {
                    sitePackagesPath = libDir.appendingPathComponent(pythonVersionDir)
                        .appendingPathComponent("site-packages").path
                }
            }

            environmentVariables["PYTHONPATH"] = sitePackagesPath
        } else {
            // For embedded Python, set PYTHONHOME to the package directory
            environmentVariables["PYTHONHOME"] = packageDir.path

            // Set PYTHONPATH to include the package's lib directory
            let libPath = packageDir.appendingPathComponent("lib").path
            environmentVariables["PYTHONPATH"] = libPath
        }

        return RuntimeEnvironment(
            type: .python,
            interpreterPath: interpreterPath,
            environmentVariables: environmentVariables,
            requiresWrapper: true
        )
    }

    // MARK: - Node.js Detection

    private func detectNodeJSRuntime(packageDir: URL, packageName: String) -> RuntimeEnvironment? {
        // Check for node_modules directory
        let nodeModulesDir = packageDir.appendingPathComponent("node_modules")
        if fileManager.fileExists(atPath: nodeModulesDir.path) {
            return createNodeJSEnvironment(packageDir: packageDir, packageName: packageName)
        }

        // Check for Node.js executable
        let nodeExecutable = packageDir.appendingPathComponent("bin/node")
        if fileManager.fileExists(atPath: nodeExecutable.path) {
            return createNodeJSEnvironment(packageDir: packageDir, packageName: packageName)
        }

        // Check for npm/yarn in package name
        if packageName.contains("node") || packageName.contains("npm") || packageName.contains("yarn") {
            return createNodeJSEnvironment(packageDir: packageDir, packageName: packageName)
        }

        return nil
    }

    private func createNodeJSEnvironment(packageDir: URL, packageName: String) -> RuntimeEnvironment {
        let nodeExecutable = packageDir.appendingPathComponent("bin/node")
        let interpreterPath = fileManager.fileExists(atPath: nodeExecutable.path) ? nodeExecutable.path : "/usr/bin/node"

        var environmentVariables: [String: String] = [:]

        // Set NODE_PATH for module resolution
        let nodeModulesPath = packageDir.appendingPathComponent("node_modules").path
        if fileManager.fileExists(atPath: nodeModulesPath) {
            environmentVariables["NODE_PATH"] = nodeModulesPath
        }

        return RuntimeEnvironment(
            type: .nodejs,
            interpreterPath: interpreterPath,
            environmentVariables: environmentVariables,
            requiresWrapper: true
        )
    }

    // MARK: - Ruby Detection

    private func detectRubyRuntime(packageDir: URL, packageName: String) -> RuntimeEnvironment? {
        // Check for Ruby gems directory
        let gemsDir = packageDir.appendingPathComponent("lib/ruby/gems")
        if fileManager.fileExists(atPath: gemsDir.path) {
            return createRubyEnvironment(packageDir: packageDir, packageName: packageName)
        }

        // Check for Gemfile or .gemspec
        let gemfile = packageDir.appendingPathComponent("Gemfile")
        let gemspec = packageDir.pathExtension == "gemspec"
        if fileManager.fileExists(atPath: gemfile.path) || gemspec {
            return createRubyEnvironment(packageDir: packageDir, packageName: packageName)
        }

        return nil
    }

    private func createRubyEnvironment(packageDir: URL, packageName: String) -> RuntimeEnvironment {
        let rubyExecutable = packageDir.appendingPathComponent("bin/ruby")
        let interpreterPath = fileManager.fileExists(atPath: rubyExecutable.path) ? rubyExecutable.path : "/usr/bin/ruby"

        var environmentVariables: [String: String] = [:]

        // Set GEM_HOME and GEM_PATH
        let gemPath = packageDir.appendingPathComponent("lib/ruby/gems").path
        if fileManager.fileExists(atPath: gemPath) {
            environmentVariables["GEM_HOME"] = gemPath
            environmentVariables["GEM_PATH"] = gemPath
        }

        return RuntimeEnvironment(
            type: .ruby,
            interpreterPath: interpreterPath,
            environmentVariables: environmentVariables,
            requiresWrapper: true
        )
    }

    // MARK: - Java Detection

    private func detectJavaRuntime(packageDir: URL, packageName: String) -> RuntimeEnvironment? {
        // Check for Java executable
        let javaExecutable = packageDir.appendingPathComponent("bin/java")
        if fileManager.fileExists(atPath: javaExecutable.path) {
            return createJavaEnvironment(packageDir: packageDir, packageName: packageName)
        }

        // Check for lib/java or Contents/Home (macOS Java structure)
        let javaLibDir = packageDir.appendingPathComponent("lib/java")
        let macOSJavaHome = packageDir.appendingPathComponent("Contents/Home")
        if fileManager.fileExists(atPath: javaLibDir.path) || fileManager.fileExists(atPath: macOSJavaHome.path) {
            return createJavaEnvironment(packageDir: packageDir, packageName: packageName)
        }

        return nil
    }

    private func createJavaEnvironment(packageDir: URL, packageName: String) -> RuntimeEnvironment {
        // Check for macOS Java structure first
        let macOSJavaHome = packageDir.appendingPathComponent("Contents/Home")
        let javaHome = fileManager.fileExists(atPath: macOSJavaHome.path) ? macOSJavaHome.path : packageDir.path

        let javaExecutable = packageDir.appendingPathComponent("bin/java")
        let interpreterPath = fileManager.fileExists(atPath: javaExecutable.path) ? javaExecutable.path : "/usr/bin/java"

        var environmentVariables: [String: String] = [:]
        environmentVariables["JAVA_HOME"] = javaHome

        return RuntimeEnvironment(
            type: .java,
            interpreterPath: interpreterPath,
            environmentVariables: environmentVariables,
            requiresWrapper: true
        )
    }
}
