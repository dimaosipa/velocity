import XCTest
@testable import VeloFormula
@testable import VeloCore

final class FormulaParserTests: XCTestCase {
    var parser: FormulaParser!
    
    override func setUp() {
        super.setUp()
        parser = FormulaParser()
    }
    
    // MARK: - Basic Parsing Tests
    
    func testParseSimpleFormula() throws {
        let content = try loadFixture("simple.rb")
        let formula = try parser.parse(rubyContent: content, formulaName: "simple")
        
        XCTAssertEqual(formula.name, "simple")
        XCTAssertEqual(formula.description, "A simple test formula")
        XCTAssertEqual(formula.homepage, "https://example.com/simple")
        XCTAssertEqual(formula.url, "https://example.com/downloads/simple-1.0.0.tar.gz")
        XCTAssertEqual(formula.sha256, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(formula.version, "1.0.0")
        
        // Check dependencies
        XCTAssertEqual(formula.dependencies.count, 2)
        XCTAssertEqual(formula.dependencies[0].name, "dependency1")
        XCTAssertEqual(formula.dependencies[1].name, "dependency2")
        
        // Check bottles
        XCTAssertEqual(formula.bottles.count, 2)
        XCTAssertTrue(formula.bottles.contains { $0.platform == .arm64_sonoma })
        XCTAssertTrue(formula.bottles.contains { $0.platform == .arm64_ventura })
    }
    
    func testParseWgetFormula() throws {
        let content = try loadFixture("wget.rb")
        let formula = try parser.parse(rubyContent: content, formulaName: "wget")
        
        XCTAssertEqual(formula.name, "wget")
        XCTAssertEqual(formula.description, "Internet file retriever")
        XCTAssertEqual(formula.homepage, "https://www.gnu.org/software/wget/")
        XCTAssertEqual(formula.url, "https://ftp.gnu.org/gnu/wget/wget-1.21.3.tar.gz")
        XCTAssertEqual(formula.sha256, "5726bb8bc5ca0f6dc7110f6416c4bb7019e2d2ff5bf93d1ca2ffcc6656f220e5")
        XCTAssertEqual(formula.version, "1.21.3")
        
        // Check dependencies
        XCTAssertTrue(formula.dependencies.contains { $0.name == "pkg-config" && $0.type == .build })
        XCTAssertTrue(formula.dependencies.contains { $0.name == "openssl@3" && $0.type == .required })
        
        // Check bottles (should have arm64 variants)
        let arm64Bottles = formula.bottles.filter { $0.platform.rawValue.hasPrefix("arm64") }
        XCTAssertEqual(arm64Bottles.count, 3) // monterey, ventura, sonoma
    }
    
    func testParseComplexFormula() throws {
        let content = try loadFixture("complex.rb")
        let formula = try parser.parse(rubyContent: content, formulaName: "complex")
        
        XCTAssertEqual(formula.name, "complex")
        XCTAssertEqual(formula.description, "A complex formula with various features")
        XCTAssertEqual(formula.version, "2.5.1")
        
        // Check build dependencies
        let buildDeps = formula.dependencies.filter { $0.type == .build }
        XCTAssertEqual(buildDeps.count, 2)
        XCTAssertTrue(buildDeps.contains { $0.name == "cmake" })
        XCTAssertTrue(buildDeps.contains { $0.name == "rust" })
        
        // Check regular dependencies
        let regularDeps = formula.dependencies.filter { $0.type == .required }
        XCTAssertTrue(regularDeps.contains { $0.name == "openssl@3" })
        XCTAssertTrue(regularDeps.contains { $0.name == "zstd" })
        
        // Check all arm64 bottles are present
        XCTAssertTrue(formula.bottles.contains { $0.platform == .arm64_sequoia })
        XCTAssertTrue(formula.bottles.contains { $0.platform == .arm64_sonoma })
        XCTAssertTrue(formula.bottles.contains { $0.platform == .arm64_ventura })
        XCTAssertTrue(formula.bottles.contains { $0.platform == .arm64_monterey })
        
        // Ensure x86_64 bottles are NOT included
        XCTAssertFalse(formula.bottles.contains { $0.sha256 == "5555555555555555555555555555555555555555555555555555555555555555" })
    }
    
    // MARK: - Error Handling Tests
    
    func testParseFormulaWithoutDescription() {
        let content = """
        class NoDesc < Formula
          homepage "https://example.com"
          url "https://example.com/file.tar.gz"
          sha256 "abcd1234"
        end
        """
        
        XCTAssertThrowsError(try parser.parse(rubyContent: content, formulaName: "nodesc")) { error in
            guard case VeloError.formulaParseError(_, let details) = error else {
                XCTFail("Expected formulaParseError")
                return
            }
            XCTAssertTrue(details.contains("description"))
        }
    }
    
    func testParseFormulaWithoutURL() {
        let content = """
        class NoURL < Formula
          desc "No URL formula"
          homepage "https://example.com"
          sha256 "abcd1234"
        end
        """
        
        XCTAssertThrowsError(try parser.parse(rubyContent: content, formulaName: "nourl")) { error in
            guard case VeloError.formulaParseError(_, let details) = error else {
                XCTFail("Expected formulaParseError")
                return
            }
            XCTAssertTrue(details.contains("URL"))
        }
    }
    
    // MARK: - Version Extraction Tests
    
    func testVersionExtractionFromURL() throws {
        let testCases = [
            ("https://example.com/package-1.2.3.tar.gz", "1.2.3"),
            ("https://github.com/org/repo/archive/v4.5.6.tar.gz", "4.5.6"),
            ("https://example.com/downloads/tool-2.0.0-beta1.tar.gz", "2.0.0-beta1"),
            ("https://ftp.gnu.org/gnu/wget/wget-1.21.3.tar.gz", "1.21.3")
        ]
        
        for (url, expectedVersion) in testCases {
            let content = """
            class Test < Formula
              desc "Test formula"
              homepage "https://example.com"
              url "\(url)"
              sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            end
            """
            
            let formula = try parser.parse(rubyContent: content, formulaName: "test")
            XCTAssertEqual(formula.version, expectedVersion, "Failed to extract version from URL: \(url)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadFixture(_ filename: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "Fixtures/Formulae/\(filename)", withExtension: nil)
            ?? URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures")
                .appendingPathComponent("Formulae")
                .appendingPathComponent(filename)
        
        return try String(contentsOf: url, encoding: .utf8)
    }
}