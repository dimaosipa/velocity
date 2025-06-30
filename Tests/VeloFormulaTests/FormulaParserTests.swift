import XCTest
@testable import VeloFormula
@testable import VeloCore
@testable import VeloSystem

final class FormulaParserTests: XCTestCase {
    var parser: FormulaParser!

    override func setUp() {
        super.setUp()
        parser = FormulaParser()
    }

    // MARK: - Basic Parsing Tests

    func testParseSimpleFormula() throws {
        let content = """
        class Simple < Formula
          desc "A simple test formula"
          homepage "https://example.com/simple"
          url "https://example.com/downloads/simple-1.0.0.tar.gz"
          sha256 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

          bottle do
            sha256 arm64_sonoma: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
            sha256 arm64_ventura: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
          end

          depends_on "dependency1"
          depends_on "dependency2"

          def install
            bin.install "simple"
          end
        end
        """
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
        let content = """
        class Wget < Formula
          desc "Internet file retriever"
          homepage "https://www.gnu.org/software/wget/"
          url "https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz"
          sha256 "766e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784"

          depends_on "pkg-config" => :build
          depends_on "openssl@3"

          bottle do
            sha256 arm64_sonoma: "4d180cd4ead91a34e2c2672189fc366b87ae86e6caa3acbf4845b272f57c859a"
            sha256 arm64_ventura: "7fce09705a52a2aff61c4bdd81b9d2a1a110539718ded2ad45562254ef0f5c22"
            sha256 arm64_monterey: "498cea03c8c9f5ab7b90a0c333122415f0360c09f837cafae6d8685d6846ced2"
          end
        end
        """
        let formula = try parser.parse(rubyContent: content, formulaName: "wget")

        XCTAssertEqual(formula.name, "wget")
        XCTAssertEqual(formula.description, "Internet file retriever")
        XCTAssertEqual(formula.homepage, "https://www.gnu.org/software/wget/")
        XCTAssertEqual(formula.url, "https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz")
        XCTAssertEqual(formula.sha256, "766e48423e79359ea31e41db9e5c289675947a7fcf2efdcedb726ac9d0da3784")
        XCTAssertEqual(formula.version, "1.25.0")

        // Check dependencies
        XCTAssertTrue(formula.dependencies.contains { $0.name == "pkg-config" && $0.type == .build })
        XCTAssertTrue(formula.dependencies.contains { $0.name == "openssl@3" && $0.type == .required })

        // Check bottles (should have arm64 variants)
        let arm64Bottles = formula.bottles.filter { $0.platform.rawValue.hasPrefix("arm64") }
        XCTAssertEqual(arm64Bottles.count, 3) // monterey, ventura, sonoma
    }

    func testParseComplexFormula() throws {
        let content = """
        class Complex < Formula
          desc "A complex formula with various features"
          homepage "https://complex.example.com"
          url "https://github.com/example/complex/archive/v2.5.1.tar.gz"
          sha256 "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
          version "2.5.1"
          license "MIT"

          bottle do
            rebuild 1
            sha256 cellar: :any_skip_relocation, arm64_sequoia: "1111111111111111111111111111111111111111111111111111111111111111"
            sha256 cellar: :any_skip_relocation, arm64_sonoma:  "2222222222222222222222222222222222222222222222222222222222222222"
            sha256 cellar: :any_skip_relocation, arm64_ventura: "3333333333333333333333333333333333333333333333333333333333333333"
            sha256 cellar: :any_skip_relocation, arm64_monterey: "4444444444444444444444444444444444444444444444444444444444444444"
            sha256 cellar: :any, x86_64_sonoma: "5555555555555555555555555555555555555555555555555555555555555555"
          end

          depends_on "cmake" => :build
          depends_on "rust" => :build
          depends_on "openssl@3"
          depends_on "zstd"
          depends_on :macos => :monterey

          def install
            system "cmake", "-S", ".", "-B", "build", *std_cmake_args
            system "cmake", "--build", "build"
            system "cmake", "--install", "build"
          end

          test do
            system "#{bin}/complex", "--version"
          end
        end
        """
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
            ("https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz", "1.25.0")
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

    func testVersionExtractionComprehensive() throws {
        let testCases = [
            // Standard semantic versions
            ("https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz", "1.25.0"),
            ("https://example.com/package-2.1.3.tar.gz", "2.1.3"),
            ("https://github.com/user/repo/archive/v4.5.6.tar.gz", "4.5.6"),

            // Pre-release versions
            ("https://example.com/tool-1.0.0-alpha1.tar.gz", "1.0.0-alpha1"),
            ("https://example.com/tool-2.0.0-beta1.tar.gz", "2.0.0-beta1"),
            ("https://example.com/tool-1.5.0-rc2.tar.gz", "1.5.0-rc2"),

            // Four-part versions
            ("https://example.com/app-1.2.3.4.tar.gz", "1.2.3.4"),

            // GitHub patterns
            ("https://github.com/user/repo/archive/refs/tags/1.2.3.tar.gz", "1.2.3"),
            ("https://github.com/user/repo/archive/refs/tags/v2.0.0.tar.gz", "2.0.0"),

            // Different separators
            ("https://example.com/tool_1.5.2.tar.gz", "1.5.2"),
            ("https://example.com/downloads/app/1.0.0/source.tar.gz", "1.0.0"),

            // Date-based versions (argon2 style)
            ("https://github.com/P-H-C/phc-winner-argon2/archive/refs/tags/20190702.tar.gz", "20190702"),
            ("https://github.com/user/repo/archive/refs/tags/20241225.tar.gz", "20241225")
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

    func testArgon2VersionExtraction() throws {
        // Test date-based version extraction for argon2-style formulae
        let content = """
        class Argon2 < Formula
          desc "Password hashing library and CLI utility"
          homepage "https://github.com/P-H-C/phc-winner-argon2"
          url "https://github.com/P-H-C/phc-winner-argon2/archive/refs/tags/20190702.tar.gz"
          sha256 "daf972a89577f8772602bf2eb38b6a3dd3d922bf5724d45e7f9589b5e830442c"
        end
        """

        let formula = try parser.parse(rubyContent: content, formulaName: "argon2")
        XCTAssertEqual(formula.version, "20190702")
        XCTAssertEqual(formula.name, "argon2")
        XCTAssertEqual(formula.description, "Password hashing library and CLI utility")
    }

    // MARK: - Helper Methods

}
