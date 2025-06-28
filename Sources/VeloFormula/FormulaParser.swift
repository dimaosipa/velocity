import Foundation
import VeloCore

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
        // Match desc "..." or desc '...'
        let pattern = #"desc\s+["']([^"']+)["']"#
        guard let match = content.range(of: pattern, options: .regularExpression),
              let descMatch = content[match].firstMatch(of: try Regex(pattern)),
              descMatch.count >= 2 else {
            throw VeloError.formulaParseError(formula: "unknown", details: "Could not find description")
        }
        return String(descMatch.output[1].substring ?? "")
    }
    
    private func extractHomepage(from content: String) throws -> String {
        // Match homepage "..." or homepage '...'
        let pattern = #"homepage\s+["']([^"']+)["']"#
        guard let match = content.range(of: pattern, options: .regularExpression),
              let homepageMatch = content[match].firstMatch(of: try Regex(pattern)),
              homepageMatch.count >= 2 else {
            throw VeloError.formulaParseError(formula: "unknown", details: "Could not find homepage")
        }
        return String(homepageMatch.output[1].substring ?? "")
    }
    
    private func extractURL(from content: String) throws -> String {
        // Match url "..." but not inside bottle block
        let pattern = #"^\s*url\s+["']([^"']+)["']"#
        let lines = content.components(separatedBy: .newlines)
        var inBottleBlock = false
        
        for line in lines {
            if line.contains("bottle do") {
                inBottleBlock = true
            } else if line.contains("end") && inBottleBlock {
                inBottleBlock = false
            } else if !inBottleBlock,
                      let match = line.firstMatch(of: try Regex(pattern)),
                      match.count >= 2 {
                return String(match.output[1].substring ?? "")
            }
        }
        
        throw VeloError.formulaParseError(formula: "unknown", details: "Could not find URL")
    }
    
    private func extractSHA256(from content: String) throws -> String {
        // Match sha256 "..." but not inside bottle block
        let pattern = #"^\s*sha256\s+["']([a-fA-F0-9]{64})["']"#
        let lines = content.components(separatedBy: .newlines)
        var inBottleBlock = false
        
        for line in lines {
            if line.contains("bottle do") {
                inBottleBlock = true
            } else if line.contains("end") && inBottleBlock {
                inBottleBlock = false
            } else if !inBottleBlock,
                      let match = line.firstMatch(of: try Regex(pattern)),
                      match.count >= 2 {
                return String(match.output[1].substring ?? "")
            }
        }
        
        throw VeloError.formulaParseError(formula: "unknown", details: "Could not find SHA256")
    }
    
    private func extractVersion(from content: String, url: String) throws -> String {
        // First try to find explicit version
        let versionPattern = #"version\s+["']([^"']+)["']"#
        if let match = content.firstMatch(of: try Regex(versionPattern)),
           match.count >= 2 {
            return String(match.output[1].substring ?? "")
        }
        
        // Try to extract from URL
        let urlVersionPattern = #"/(\d+\.\d+(?:\.\d+)*(?:-[\w.]+)?)"#
        if let match = url.firstMatch(of: try Regex(urlVersionPattern)),
           match.count >= 2 {
            return String(match.output[1].substring ?? "")
        }
        
        throw VeloError.formulaParseError(formula: "unknown", details: "Could not determine version")
    }
    
    // MARK: - Dependency Extraction
    
    private func extractDependencies(from content: String) -> [Formula.Dependency] {
        var dependencies: [Formula.Dependency] = []
        
        // Match depends_on "..."
        let dependsPattern = #"depends_on\s+["']([^"']+)["']"#
        if let regex = try? Regex(dependsPattern) {
            for match in content.matches(of: regex) {
                if match.count >= 2,
                   let depName = match.output[1].substring {
                    dependencies.append(Formula.Dependency(name: String(depName)))
                }
            }
        }
        
        // Match depends_on :... => "..."
        let conditionalPattern = #"depends_on\s+:(\w+)\s*=>\s*["']([^"']+)["']"#
        if let regex = try? Regex(conditionalPattern) {
            for match in content.matches(of: regex) {
                if match.count >= 3,
                   let typeStr = match.output[1].substring,
                   let depName = match.output[2].substring {
                    let type: Formula.Dependency.DependencyType
                    switch String(typeStr) {
                    case "build":
                        type = .build
                    case "optional":
                        type = .optional
                    case "recommended":
                        type = .recommended
                    default:
                        type = .required
                    }
                    dependencies.append(Formula.Dependency(name: String(depName), type: type))
                }
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
        let sha256Pattern = #"sha256\s+cellar:\s*:\w+,\s*(\w+):\s*["']([a-fA-F0-9]{64})["']"#
        if let regex = try? Regex(sha256Pattern) {
            for match in bottleBlock.matches(of: regex) {
                if match.count >= 3,
                   let platformStr = match.output[1].substring,
                   let sha = match.output[2].substring {
                    // Only process arm64 platforms
                    if let platform = Formula.Bottle.Platform(rawValue: String(platformStr)) {
                        bottles.append(Formula.Bottle(sha256: String(sha), platform: platform))
                    }
                }
            }
        }
        
        // Alternative format: sha256 arm64_monterey: "..."
        let altPattern = #"sha256\s+(\w+):\s*["']([a-fA-F0-9]{64})["']"#
        if let regex = try? Regex(altPattern) {
            for match in bottleBlock.matches(of: regex) {
                if match.count >= 3,
                   let platformStr = match.output[1].substring,
                   let sha = match.output[2].substring {
                    if let platform = Formula.Bottle.Platform(rawValue: String(platformStr)) {
                        bottles.append(Formula.Bottle(sha256: String(sha), platform: platform))
                    }
                }
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
}