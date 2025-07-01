import Foundation
import VeloSystem

public struct FormulaParser {

    public init() {}

    public func parse(rubyContent: String, formulaName: String) throws -> Formula {
        // Extract basic information
        do {
            let description = try extractDescription(from: rubyContent, formulaName: formulaName)
            let homepage = try extractHomepage(from: rubyContent, formulaName: formulaName)
            let url = try extractURL(from: rubyContent, formulaName: formulaName)
            let sha256 = try extractSHA256(from: rubyContent, formulaName: formulaName)
            let version = try extractVersion(from: rubyContent, url: url, formulaName: formulaName)

            // Extract dependencies
            let dependencies = extractDependencies(from: rubyContent)

            // Extract bottles
            let bottles = try extractBottles(from: rubyContent)

            return Formula(
                name: formulaName,
                description: description,
                homepage: homepage,
                url: url,
                sha256: sha256,
                version: version,
                dependencies: dependencies,
                bottles: bottles
            )
        } catch {
            // Re-throw with formula name for better error reporting
            if let veloError = error as? VeloError {
                throw veloError
            } else {
                throw VeloError.formulaParseError(formula: formulaName, details: "Parse error: \(error)")
            }
        }
    }

    // MARK: - Basic Field Extraction

    private func extractDescription(from content: String, formulaName: String) throws -> String {
        // Handle both double and single quoted descriptions
        // For double quotes: desc "content with 'quotes' inside"
        // For single quotes: desc 'content with "quotes" inside'
        let doubleQuotePattern = #"desc\s+"([^"]*)\""#
        let singleQuotePattern = #"desc\s+'([^']*)'"#
        
        if let match = extractFirstMatch(pattern: doubleQuotePattern, from: content) {
            return match
        }
        if let match = extractFirstMatch(pattern: singleQuotePattern, from: content) {
            return match
        }
        
        throw VeloError.formulaParseError(formula: formulaName, details: "Could not find description")
    }

    private func extractHomepage(from content: String, formulaName: String) throws -> String {
        // Handle both double and single quoted homepages
        let doubleQuotePattern = #"homepage\s+"([^"]*)\""#
        let singleQuotePattern = #"homepage\s+'([^']*)'"#
        
        if let match = extractFirstMatch(pattern: doubleQuotePattern, from: content) {
            return match
        }
        if let match = extractFirstMatch(pattern: singleQuotePattern, from: content) {
            return match
        }
        
        throw VeloError.formulaParseError(formula: formulaName, details: "Could not find homepage")
    }

    private func extractURL(from content: String, formulaName: String) throws -> String {
        let pattern = #"^\s*url\s+["']([^"']+)["']"#
        let lines = content.components(separatedBy: .newlines)
        var inBottleBlock = false
        var inHeadBlock = false

        // First pass: look for main URL (not in bottle or head blocks)
        for line in lines {
            if line.contains("bottle do") {
                inBottleBlock = true
            } else if line.contains("head do") {
                inHeadBlock = true
            } else if line.contains("end") && (inBottleBlock || inHeadBlock) {
                inBottleBlock = false
                inHeadBlock = false
            } else if !inBottleBlock && !inHeadBlock,
                      let match = extractFirstMatch(pattern: pattern, from: line) {
                return match
            }
        }

        // For Git-based formulae without main URL, construct from tag/revision info
        if content.contains("tag:") {
            let gitUrlPattern = #"url\s+["']([^"']+\.git)["']"#
            if let gitUrl = extractFirstMatch(pattern: gitUrlPattern, from: content) {
                return gitUrl
            }
        }

        throw VeloError.formulaParseError(formula: formulaName, details: "Could not find URL")
    }

    private func extractSHA256(from content: String, formulaName: String) throws -> String {
        let pattern = #"^\s*sha256\s+["']([a-fA-F0-9]{64})["']"#
        let lines = content.components(separatedBy: .newlines)
        var inBottleBlock = false

        for line in lines {
            if line.contains("bottle do") {
                inBottleBlock = true
            } else if line.contains("end") && inBottleBlock {
                inBottleBlock = false
            } else if !inBottleBlock,
                      let match = extractFirstMatch(pattern: pattern, from: line) {
                return match
            }
        }

        // For VCS-based formulae, return a placeholder SHA256
        // The actual source will be cloned/checked out, not downloaded as a tarball
        if content.contains("git") && (content.contains("tag:") || content.contains("revision:")) {
            return "0000000000000000000000000000000000000000000000000000000000000000"
        }
        
        // Handle SVN, Mercurial, and other VCS checkouts
        if content.contains("revision:") || content.contains("hg ") || content.contains("svn.") {
            return "0000000000000000000000000000000000000000000000000000000000000000"
        }

        throw VeloError.formulaParseError(formula: formulaName, details: "Could not find SHA256")
    }

    private func extractVersion(from content: String, url: String, formulaName: String) throws -> String {
        var baseVersion: String?
        
        // First try to find explicit version
        let versionPattern = #"version\s+["']([^"']+)["']"#
        if let match = extractFirstMatch(pattern: versionPattern, from: content) {
            baseVersion = match
        }

        // Try to extract from tag field (for Git-based formulae)
        if baseVersion == nil {
            let tagPattern = #"tag:\s*["']v?([^"']+)["']"#
            if let match = extractFirstMatch(pattern: tagPattern, from: content) {
                baseVersion = match
            }
        }

        // Try to extract from URL - match version numbers after dash, slash, underscore, or 'v'
        if baseVersion == nil {
            let urlVersionPatterns = [
                #"[-/_]v?(\d+\.\d+(?:\.\d+)*(?:-[\w]+)*)"#,  // v2.2.26 or 2.2.26-beta1 or x265_4.1 (including underscore)
                #"/(\d+\.\d+(?:\.\d+)*(?:-[\w]+)*)"#,        // fallback without v
                #"(\d+\.\d+\.\d+)"#,                          // simple three-part version
                #"(\d{4}-\d{2}-\d{2})"#,                      // date-based versions (2025-05-20)
                #"[-/_](\d{8})"#,                             // 8-digit date format (20250622, 20200209)
                #"/archive/refs/tags/([^/]+)\.tar"#,          // GitHub archive URLs (for argon2-style date versions)
                #"[-/_](\d{4}[a-z])"#,                        // year + letter (2007f)
                #"[-/_](\d{3,})"#,                            // 3+ digit numbers (018)
                #"(\d+_\d+_\d+)"#,                            // underscore separated (2_8_9)
                #"[a-zA-Z]+(\d+\.\d+)"#,                      // name directly followed by version (tth4.16)
                #"[-/_](\d{1,2})"#,                           // single or double digit numbers (ngircd-27)
                #"\.v(\d+[a-z]?)"#,                           // .v prefix with letter suffix (jpegsrc.v9f)
                #"[-/_]r(\d+)"#,                              // r prefix versions (bootstrap-bin-r9)
                #"/v(\d+)\.tar"#,                             // single digit /v versions (/v7.tar.gz)
                #"v(\d{8})"#                                  // 8-digit date versions in paths (v20250528)
            ]

            for pattern in urlVersionPatterns {
                if let match = extractFirstMatch(pattern: pattern, from: url) {
                    // Convert underscores to dots for consistency (nauty2_8_9 -> 2.8.9)
                    baseVersion = match.replacingOccurrences(of: "_", with: ".")
                    break
                }
            }
        }
        
        guard let version = baseVersion else {
            throw VeloError.formulaParseError(formula: formulaName, details: "Could not determine version")
        }

        // Check for revision field and append if found
        let revisionPattern = #"revision\s+(\d+)"#
        if let revision = extractFirstMatch(pattern: revisionPattern, from: content) {
            return "\(version)_\(revision)"
        }

        return version
    }

    // MARK: - Dependency Extraction

    private func extractDependencies(from content: String) -> [Formula.Dependency] {
        var dependencies: [Formula.Dependency] = []
        var blockStack: [String] = []

        // Split content into lines for better parsing
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip comment lines
            if trimmedLine.hasPrefix("#") {
                continue
            }

            // Track platform-specific blocks with proper nesting
            if trimmedLine.starts(with: "on_linux do") {
                blockStack.append("linux")
                continue
            } else if trimmedLine.contains("on_bsd do") || trimmedLine.contains("on_freebsd do") || 
                      trimmedLine.contains("on_openbsd do") || trimmedLine.contains("on_netbsd do") {
                blockStack.append("other_platform")
                continue
            } else if trimmedLine.starts(with: "on_macos do") || trimmedLine.starts(with: "on_intel do") {
                blockStack.append("macos_compatible")
                continue
            } else if trimmedLine == "end" && !blockStack.isEmpty {
                blockStack.removeLast()
                continue
            }

            // Skip dependencies inside Linux or other non-macOS platform blocks
            let currentContext = blockStack.last
            if currentContext == "linux" || currentContext == "other_platform" {
                continue
            }

            // Skip platform-specific dependencies that don't apply to macOS
            if shouldSkipPlatformDependency(line: line) {
                continue
            }

            // Match depends_on with version constraints and build flag
            // Format: depends_on "name", ">= 1.0", "< 2.0" => :build
            let buildDependsWithVersionPattern = #"depends_on\s+["']([^"']+)["'](?:\s*,\s*["']([^"']+)["'])*\s*=>\s*:build"#
            if let dependency = parseDependencyLine(line, pattern: buildDependsWithVersionPattern, type: .build) {
                dependencies.append(dependency)
                continue
            }

            // Match depends_on with build flag (no version): depends_on "name" => :build
            let buildDependsPattern = #"depends_on\s+["']([^"']+)["']\s*=>\s*:build"#
            if let match = extractFirstMatch(pattern: buildDependsPattern, from: line) {
                dependencies.append(Formula.Dependency(name: match, type: .build))
                continue
            }

            // Match depends_on with version constraints
            // Format: depends_on "name", ">= 1.0", "< 2.0"
            if let dependency = parseDependencyWithVersions(line) {
                dependencies.append(dependency)
                continue
            }

            // Match regular depends_on: depends_on "name"
            let dependsPattern = #"depends_on\s+["']([^"']+)["']"#
            if let match = extractFirstMatch(pattern: dependsPattern, from: line) {
                dependencies.append(Formula.Dependency(name: match, type: .required))
            }
        }

        return dependencies
    }

    /// Parse dependency line with version constraints
    private func parseDependencyWithVersions(_ line: String) -> Formula.Dependency? {
        // Pattern to match: depends_on "package", "constraint1", "constraint2", ...
        let basePattern = #"depends_on\s+["']([^"']+)["']"#
        
        guard let packageName = extractFirstMatch(pattern: basePattern, from: line) else {
            return nil
        }
        
        // Extract all quoted strings after the package name
        let allQuotedStrings = extractAllMatches(pattern: #"["']([^"']+)["']"#, from: line)
        
        // First quoted string is the package name, rest are version constraints
        if allQuotedStrings.count > 1 {
            let constraints = Array(allQuotedStrings.dropFirst())
            // Filter out non-version constraints (like platform specifiers)
            let versionConstraints = constraints.filter { isVersionConstraint($0) }
            
            if !versionConstraints.isEmpty {
                return Formula.Dependency(name: packageName, type: .required, versionConstraints: versionConstraints)
            }
        }
        
        return nil
    }
    
    /// Parse dependency line with pattern for specific type
    private func parseDependencyLine(_ line: String, pattern: String, type: Formula.Dependency.DependencyType) -> Formula.Dependency? {
        guard let packageName = extractFirstMatch(pattern: pattern, from: line) else {
            return nil
        }
        
        // Extract version constraints from the line
        let allQuotedStrings = extractAllMatches(pattern: #"["']([^"']+)["']"#, from: line)
        let constraints = Array(allQuotedStrings.dropFirst()).filter { isVersionConstraint($0) }
        
        return Formula.Dependency(name: packageName, type: type, versionConstraints: constraints)
    }
    
    /// Check if a string looks like a version constraint
    private func isVersionConstraint(_ string: String) -> Bool {
        let versionOperators = [">=", "<=", ">", "<", "==", "~>", "^"]
        return versionOperators.contains { string.hasPrefix($0) } || 
               string.range(of: #"\d+\.\d+"#, options: .regularExpression) != nil
    }

    /// Check if a line contains a platform-specific dependency that should be skipped on macOS
    private func shouldSkipPlatformDependency(line: String) -> Bool {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip Linux-only dependencies
        if trimmedLine.contains("depends_on :linux") {
            return true
        }
        
        // Skip other non-macOS platform dependencies
        let nonMacOSPlatforms = [":bsd", ":freebsd", ":openbsd", ":netbsd"]
        for platform in nonMacOSPlatforms {
            if trimmedLine.contains("depends_on \(platform)") {
                return true
            }
        }
        
        // Keep macOS dependencies and regular string dependencies
        return false
    }

    // MARK: - Bottle Extraction

    private func extractBottles(from content: String) throws -> [Formula.Bottle] {
        var bottles: [Formula.Bottle] = []

        // Find bottle block
        guard let bottleBlockRange = findBottleBlock(in: content) else {
            return bottles // No bottles is valid
        }

        let bottleBlock = String(content[bottleBlockRange])

        // Extract sha256 entries for all supported platforms
        // Handle formats:
        // - sha256 cellar: :any, arm64_sonoma: "hash"  
        // - sha256 arm64_sonoma: "hash"
        // - sha256 cellar: :any_skip_relocation, all: "hash"
        // - sha256 sonoma: "hash" (x86_64)
        
        let platformPatterns = [
            // ARM64 platforms
            #"sha256\s+(arm64_\w+):\s*["']([a-fA-F0-9]{64})["']"#,
            #"sha256\s+[^,]*,\s*(arm64_\w+):\s*["']([a-fA-F0-9]{64})["']"#,
            
            // x86_64 platforms (without arm64_ prefix)
            #"sha256\s+(monterey|ventura|sonoma|sequoia|big_sur|catalina|mojave):\s*["']([a-fA-F0-9]{64})["']"#,
            #"sha256\s+[^,]*,\s*(monterey|ventura|sonoma|sequoia|big_sur|catalina|mojave):\s*["']([a-fA-F0-9]{64})["']"#,
            
            // Universal/all platforms
            #"sha256\s+(all):\s*["']([a-fA-F0-9]{64})["']"#,
            #"sha256\s+[^,]*,\s*(all):\s*["']([a-fA-F0-9]{64})["']"#
        ]

        var matches: [(String, String)] = []
        for pattern in platformPatterns {
            matches.append(contentsOf: extractAllMatchPairs(pattern: pattern, from: bottleBlock))
        }

        for (platformStr, sha) in matches {
            if let platform = Formula.Bottle.Platform(rawValue: platformStr) {
                bottles.append(Formula.Bottle(sha256: sha, platform: platform))
            }
        }

        return bottles
    }

    private func findBottleBlock(in content: String) -> Range<String.Index>? {
        guard let startRange = content.range(of: "bottle do") else {
            return nil
        }

        let afterStart = content[startRange.upperBound...]
        var depth = 1
        var currentIndex = afterStart.startIndex

        while currentIndex < afterStart.endIndex && depth > 0 {
            if afterStart[currentIndex...].hasPrefix("do") {
                depth += 1
                currentIndex = afterStart.index(currentIndex, offsetBy: 2)
            } else if afterStart[currentIndex...].hasPrefix("end") {
                depth -= 1
                if depth == 0 {
                    let endIndex = afterStart.index(currentIndex, offsetBy: 3)
                    return startRange.lowerBound..<endIndex
                }
                currentIndex = afterStart.index(currentIndex, offsetBy: 3)
            } else {
                currentIndex = afterStart.index(after: currentIndex)
            }
        }

        return nil
    }

    // MARK: - Helper Methods using NSRegularExpression

    private func extractFirstMatch(pattern: String, from text: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: text.utf16.count)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               match.numberOfRanges > 1 {
                let captureRange = match.range(at: 1)
                if let swiftRange = Range(captureRange, in: text) {
                    return String(text[swiftRange])
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func extractAllMatches(pattern: String, from text: String) -> [String] {
        var results: [String] = []
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: text.utf16.count)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                if match.numberOfRanges > 1 {
                    let captureRange = match.range(at: 1)
                    if let swiftRange = Range(captureRange, in: text) {
                        results.append(String(text[swiftRange]))
                    }
                }
            }
        } catch {
            return results
        }
        return results
    }

    private func extractAllMatchPairs(pattern: String, from text: String) -> [(String, String)] {
        var results: [(String, String)] = []
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: text.utf16.count)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                if match.numberOfRanges > 2 {
                    let firstRange = match.range(at: 1)
                    let secondRange = match.range(at: 2)

                    if let firstSwiftRange = Range(firstRange, in: text),
                       let secondSwiftRange = Range(secondRange, in: text) {
                        let first = String(text[firstSwiftRange])
                        let second = String(text[secondSwiftRange])
                        results.append((first, second))
                    }
                }
            }
        } catch {
            return results
        }
        return results
    }
}
