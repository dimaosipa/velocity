import Foundation
import VeloSystem

public struct FormulaParser {

    public init() {}

    public func parse(rubyContent: String, formulaName: String) throws -> Formula {
        // Extract basic information
        let description = try extractDescription(from: rubyContent)
        let homepage = try extractHomepage(from: rubyContent)
        let url = try extractURL(from: rubyContent)
        let sha256 = try extractSHA256(from: rubyContent)
        let version = try extractVersion(from: rubyContent, url: url)

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
    }

    // MARK: - Basic Field Extraction

    private func extractDescription(from content: String) throws -> String {
        let pattern = #"desc\s+["']([^"']+)["']"#
        guard let match = extractFirstMatch(pattern: pattern, from: content) else {
            throw VeloError.formulaParseError(formula: "unknown", details: "Could not find description")
        }
        return match
    }

    private func extractHomepage(from content: String) throws -> String {
        let pattern = #"homepage\s+["']([^"']+)["']"#
        guard let match = extractFirstMatch(pattern: pattern, from: content) else {
            throw VeloError.formulaParseError(formula: "unknown", details: "Could not find homepage")
        }
        return match
    }

    private func extractURL(from content: String) throws -> String {
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

        throw VeloError.formulaParseError(formula: "unknown", details: "Could not find URL")
    }

    private func extractSHA256(from content: String) throws -> String {
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

        // For Git-based formulae, return a placeholder SHA256
        // The actual source will be cloned, not downloaded as a tarball
        if content.contains("git") && (content.contains("tag:") || content.contains("revision:")) {
            return "0000000000000000000000000000000000000000000000000000000000000000"
        }

        throw VeloError.formulaParseError(formula: "unknown", details: "Could not find SHA256")
    }

    private func extractVersion(from content: String, url: String) throws -> String {
        // First try to find explicit version
        let versionPattern = #"version\s+["']([^"']+)["']"#
        if let match = extractFirstMatch(pattern: versionPattern, from: content) {
            return match
        }

        // Try to extract from tag field (for Git-based formulae)
        let tagPattern = #"tag:\s*["']v?([^"']+)["']"#
        if let match = extractFirstMatch(pattern: tagPattern, from: content) {
            return match
        }

        // Try to extract from URL - match version numbers after dash, slash, or 'v'
        let urlVersionPatterns = [
            #"[-/]v?(\d+\.\d+(?:\.\d+)*(?:-[\w]+)*)"#,   // v2.2.26 or 2.2.26-beta1 (excluding dots after dashes)
            #"/(\d+\.\d+(?:\.\d+)*(?:-[\w]+)*)"#,        // fallback without v
            #"(\d+\.\d+\.\d+)"#,                          // simple three-part version
            #"/archive/refs/tags/([^/]+)\.tar"#           // GitHub archive URLs (for argon2-style date versions)
        ]

        for pattern in urlVersionPatterns {
            if let match = extractFirstMatch(pattern: pattern, from: url) {
                return match
            }
        }

        throw VeloError.formulaParseError(formula: "unknown", details: "Could not determine version")
    }

    // MARK: - Dependency Extraction

    private func extractDependencies(from content: String) -> [Formula.Dependency] {
        var dependencies: [Formula.Dependency] = []

        // Split content into lines for better parsing
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            // Skip comment lines
            if line.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") {
                continue
            }

            // Match depends_on with build flag: depends_on "name" => :build
            let buildDependsPattern = #"depends_on\s+["']([^"']+)["']\s*=>\s*:build"#
            if let match = extractFirstMatch(pattern: buildDependsPattern, from: line) {
                dependencies.append(Formula.Dependency(name: match, type: .build))
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

    // MARK: - Bottle Extraction

    private func extractBottles(from content: String) throws -> [Formula.Bottle] {
        var bottles: [Formula.Bottle] = []

        // Find bottle block
        guard let bottleBlockRange = findBottleBlock(in: content) else {
            return bottles // No bottles is valid
        }

        let bottleBlock = String(content[bottleBlockRange])

        // Extract sha256 entries for arm64 platforms
        // Handle both formats:
        // - sha256 cellar: :any, arm64_sonoma: "hash"
        // - sha256 arm64_sonoma: "hash"
        let simplePattern = #"sha256\s+(arm64_\w+):\s*["']([a-fA-F0-9]{64})["']"#
        let complexPattern = #"sha256\s+[^,]*,\s*(arm64_\w+):\s*["']([a-fA-F0-9]{64})["']"#

        var matches = extractAllMatchPairs(pattern: simplePattern, from: bottleBlock)
        matches.append(contentsOf: extractAllMatchPairs(pattern: complexPattern, from: bottleBlock))

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
