import Foundation
import VeloSystem

// MARK: - Wrapper Script Generator

public final class WrapperScriptGenerator {
    private let fileManager = FileManager.default
    private let pathHelper: PathHelper

    public init(pathHelper: PathHelper = PathHelper.shared) {
        self.pathHelper = pathHelper
    }

    /// Generate wrapper scripts for runtime packages to ensure environment isolation
    public func generateWrapperScripts(
        packageDir: URL,
        packageName: String,
        runtime: RuntimeEnvironment,
        binaries: [String]
    ) throws {
        OSLogger.shared.debug("Generating wrapper scripts for \(packageName) (\(runtime.type))", category: OSLogger.shared.installer)

        for binary in binaries {
            try generateWrapperScript(
                packageDir: packageDir,
                packageName: packageName,
                binary: binary,
                runtime: runtime
            )
        }
    }

    private func generateWrapperScript(
        packageDir: URL,
        packageName: String,
        binary: String,
        runtime: RuntimeEnvironment
    ) throws {
        // Check both bin/ and libexec/bin/ for the binary (Homebrew packages use libexec/bin)
        let binPath = packageDir.appendingPathComponent("bin/\(binary)")
        let libexecBinPath = packageDir.appendingPathComponent("libexec/bin/\(binary)")

        let originalBinaryPath: URL
        if fileManager.fileExists(atPath: binPath.path) {
            originalBinaryPath = binPath
        } else if fileManager.fileExists(atPath: libexecBinPath.path) {
            originalBinaryPath = libexecBinPath
        } else {
            OSLogger.shared.debug("Binary \(binary) not found in bin/ or libexec/bin/, skipping wrapper", category: OSLogger.shared.installer)
            return
        }

        let wrapperScriptPath = pathHelper.symlinkPath(for: binary)

        let wrapperContent = generateWrapperContent(
            originalBinaryPath: originalBinaryPath.path,
            binary: binary,
            runtime: runtime
        )

        // Write wrapper script
        try wrapperContent.write(to: wrapperScriptPath, atomically: true, encoding: .utf8)

        // Make wrapper executable
        try setExecutablePermissions(wrapperScriptPath)

        OSLogger.shared.debug("Created wrapper script: \(binary) -> \(wrapperScriptPath.path)", category: OSLogger.shared.installer)
    }

    private func generateWrapperContent(
        originalBinaryPath: String,
        binary: String,
        runtime: RuntimeEnvironment
    ) -> String {
        var script = "#!/bin/bash\n"
        script += "# Velo-generated wrapper script for \(binary)\n"
        script += "# Runtime: \(runtime.type)\n"
        script += "# Generated: \(Date())\n\n"

        // Export environment variables for runtime isolation
        for (key, value) in runtime.environmentVariables {
            if value.isEmpty {
                script += "unset \(key)\n"
            } else {
                script += "export \(key)=\"\(value)\"\n"
            }
        }

        if !runtime.environmentVariables.isEmpty {
            script += "\n"
        }

        // Add runtime-specific setup
        switch runtime.type {
        case .python:
            script += generatePythonSpecificSetup(runtime: runtime)
        case .nodejs:
            script += generateNodeJSSpecificSetup(runtime: runtime)
        case .ruby:
            script += generateRubySpecificSetup(runtime: runtime)
        case .java:
            script += generateJavaSpecificSetup(runtime: runtime)
        case .unknown:
            break
        }

        // Execute the original binary
        script += "# Execute the original binary with all arguments\n"
        script += "exec \"\(originalBinaryPath)\" \"$@\"\n"

        return script
    }

    private func generatePythonSpecificSetup(runtime: RuntimeEnvironment) -> String {
        var setup = ""

        // Ensure we're using the correct Python interpreter
        if !runtime.interpreterPath.isEmpty {
            setup += "# Ensure correct Python interpreter is used\n"
            setup += "export PYTHON_EXECUTABLE=\"\(runtime.interpreterPath)\"\n"
        }

        // Handle virtual environment activation if needed
        if let virtualEnv = runtime.environmentVariables["VIRTUAL_ENV"], !virtualEnv.isEmpty {
            setup += "# Activate virtual environment\n"
            setup += "export PATH=\"\(virtualEnv)/bin:$PATH\"\n"
        }

        // Add lib-dynload to PYTHONPATH to prevent _opcode errors
        if let pythonPath = runtime.environmentVariables["PYTHONPATH"], !pythonPath.isEmpty {
            setup += "# Add lib-dynload to prevent module import errors\n"
            setup += "if [ -d \"\(pythonPath)\" ]; then\n"
            setup += "    for python_lib in \(pythonPath)/python*/lib-dynload; do\n"
            setup += "        if [ -d \"$python_lib\" ]; then\n"
            setup += "            export PYTHONPATH=\"$python_lib:$PYTHONPATH\"\n"
            setup += "        fi\n"
            setup += "    done\n"
            setup += "fi\n"
        }

        setup += "\n"
        return setup
    }

    private func generateNodeJSSpecificSetup(runtime: RuntimeEnvironment) -> String {
        var setup = ""

        if let nodePath = runtime.environmentVariables["NODE_PATH"], !nodePath.isEmpty {
            setup += "# Set up Node.js module resolution\n"
            setup += "export PATH=\"\(nodePath)/.bin:$PATH\"\n"
        }

        setup += "\n"
        return setup
    }

    private func generateRubySpecificSetup(runtime: RuntimeEnvironment) -> String {
        var setup = ""

        if let gemHome = runtime.environmentVariables["GEM_HOME"], !gemHome.isEmpty {
            setup += "# Set up Ruby gem environment\n"
            setup += "export PATH=\"\(gemHome)/bin:$PATH\"\n"
        }

        setup += "\n"
        return setup
    }

    private func generateJavaSpecificSetup(runtime: RuntimeEnvironment) -> String {
        var setup = ""

        if let javaHome = runtime.environmentVariables["JAVA_HOME"], !javaHome.isEmpty {
            setup += "# Set up Java environment\n"
            setup += "export PATH=\"\(javaHome)/bin:$PATH\"\n"
        }

        setup += "\n"
        return setup
    }

    private func setExecutablePermissions(_ scriptPath: URL) throws {
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o755
        ]
        try fileManager.setAttributes(attributes, ofItemAtPath: scriptPath.path)
    }

    /// Check if a binary should use wrapper script vs direct symlink
    public func shouldUseWrapper(packageName: String, binary: String, runtime: RuntimeEnvironment?) -> Bool {
        guard let runtime = runtime else { return false }

        // Always use wrappers for runtime packages
        guard runtime.requiresWrapper else { return false }

        // For runtime packages, ALL binaries should use wrappers for environment isolation
        // This ensures that any script or executable in the package runs with the correct
        // runtime environment (virtual env, PYTHONPATH, etc.)
        switch runtime.type {
        case .python:
            // All binaries in Python packages need wrappers for proper environment isolation
            return true
        case .nodejs:
            // All binaries in Node.js packages need wrappers for proper module resolution
            return true
        case .ruby:
            // All binaries in Ruby packages need wrappers for proper gem environment
            return true
        case .java:
            // All binaries in Java packages need wrappers for proper JAVA_HOME
            return true
        case .unknown:
            return false
        }
    }

    /// Remove wrapper scripts for a package
    public func removeWrapperScripts(binaries: [String]) throws {
        for binary in binaries {
            let wrapperPath = pathHelper.symlinkPath(for: binary)
            if fileManager.fileExists(atPath: wrapperPath.path) {
                try fileManager.removeItem(at: wrapperPath)
                OSLogger.shared.debug("Removed wrapper script: \(binary)", category: OSLogger.shared.installer)
            }
        }
    }
}
