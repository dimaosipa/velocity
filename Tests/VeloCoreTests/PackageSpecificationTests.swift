import XCTest
@testable import VeloCore

final class PackageSpecificationTests: XCTestCase {

    // MARK: - Basic Parsing Tests

    func testParsePackageWithoutVersion() {
        let spec = PackageSpecification.parse("wget")

        XCTAssertEqual(spec.name, "wget")
        XCTAssertNil(spec.version)
        XCTAssertEqual(spec.fullSpecification, "wget")
        XCTAssertTrue(spec.isValid)
    }

    func testParsePackageWithVersion() {
        let spec = PackageSpecification.parse("wget@1.25.0")

        XCTAssertEqual(spec.name, "wget")
        XCTAssertEqual(spec.version, "1.25.0")
        XCTAssertEqual(spec.fullSpecification, "wget@1.25.0")
        XCTAssertTrue(spec.isValid)
    }

    func testParsePackageWithSimpleVersion() {
        let spec = PackageSpecification.parse("openssl@3")

        XCTAssertEqual(spec.name, "openssl")
        XCTAssertEqual(spec.version, "3")
        XCTAssertEqual(spec.fullSpecification, "openssl@3")
        XCTAssertTrue(spec.isValid)
    }

    func testParsePackageWithComplexVersion() {
        let spec = PackageSpecification.parse("python@3.11")

        XCTAssertEqual(spec.name, "python")
        XCTAssertEqual(spec.version, "3.11")
        XCTAssertEqual(spec.fullSpecification, "python@3.11")
        XCTAssertTrue(spec.isValid)
    }

    // MARK: - Edge Cases

    func testParseEmptyString() {
        let spec = PackageSpecification.parse("")

        XCTAssertEqual(spec.name, "")
        XCTAssertNil(spec.version)
        XCTAssertFalse(spec.isValid)
    }

    func testParsePackageWithEmptyVersion() {
        let spec = PackageSpecification.parse("wget@")

        XCTAssertEqual(spec.name, "wget")
        XCTAssertNil(spec.version)
        XCTAssertEqual(spec.fullSpecification, "wget")
        XCTAssertTrue(spec.isValid)
    }

    func testParsePackageWithMultipleAtSigns() {
        // Only the first @ should be used for splitting
        let spec = PackageSpecification.parse("package@1.0@extra")

        XCTAssertEqual(spec.name, "package")
        XCTAssertEqual(spec.version, "1.0@extra")
        XCTAssertEqual(spec.fullSpecification, "package@1.0@extra")
        XCTAssertTrue(spec.isValid)
    }

    func testParsePackageWithWhitespace() {
        let spec = PackageSpecification.parse("  wget  @  1.25.0  ")

        XCTAssertEqual(spec.name, "wget")
        XCTAssertEqual(spec.version, "1.25.0")
        XCTAssertEqual(spec.fullSpecification, "wget@1.25.0")
        XCTAssertTrue(spec.isValid)
    }

    func testParseOnlyAtSign() {
        let spec = PackageSpecification.parse("@")

        XCTAssertEqual(spec.name, "")
        XCTAssertEqual(spec.version, "")
        XCTAssertFalse(spec.isValid)
    }

    func testParseEmptyPackageName() {
        let spec = PackageSpecification.parse("@1.0.0")

        XCTAssertEqual(spec.name, "@1.0.0")
        XCTAssertNil(spec.version)
        XCTAssertFalse(spec.isValid)
    }

    // MARK: - Validation Tests

    func testValidPackageNames() {
        let validNames = [
            "wget",
            "openssl",
            "python3",
            "node-js",
            "my_package",
            "package.name",
            "a1b2c3",
            "test-123_456.789"
        ]

        for name in validNames {
            let spec = PackageSpecification(name: name, version: nil)
            XCTAssertTrue(spec.isValid, "Package name '\(name)' should be valid")
        }
    }

    func testInvalidPackageNames() {
        let invalidNames = [
            "",
            "package with spaces",
            "package/slash",
            "package\\backslash",
            "package:colon",
            "package;semicolon",
            "package=equals",
            "package+plus",
            "package(parens)",
            "package[brackets]",
            "package{braces}",
            "package<angle>",
            "package*star",
            "package?question",
            "package|pipe"
        ]

        for name in invalidNames {
            let spec = PackageSpecification(name: name, version: nil)
            XCTAssertFalse(spec.isValid, "Package name '\(name)' should be invalid")
        }
    }

    func testVersionValidation() {
        // Valid specifications
        let validSpecs = [
            PackageSpecification(name: "wget", version: nil),
            PackageSpecification(name: "wget", version: "1.25.0"),
            PackageSpecification(name: "wget", version: "3"),
            PackageSpecification(name: "wget", version: "1.0.0-beta1")
        ]

        for spec in validSpecs {
            XCTAssertTrue(spec.isValid, "Specification '\(spec.fullSpecification)' should be valid")
        }

        // Invalid specifications
        let invalidSpecs = [
            PackageSpecification(name: "wget", version: ""),
            PackageSpecification(name: "", version: "1.0.0"),
            PackageSpecification(name: "", version: nil)
        ]

        for spec in invalidSpecs {
            XCTAssertFalse(spec.isValid, "Specification '\(spec.fullSpecification)' should be invalid")
        }
    }

    // MARK: - Real-World Examples

    func testRealWorldExamples() {
        let examples = [
            ("wget", "wget", nil),
            ("wget@1.25.0", "wget", "1.25.0"),
            ("openssl@3", "openssl", "3"),
            ("node@18", "node", "18"),
            ("python@3.11", "python", "3.11"),
            ("gcc@13", "gcc", "13"),
            ("llvm@17", "llvm", "17"),
            ("ruby@3.2", "ruby", "3.2"),
            ("go@1.21", "go", "1.21"),
            ("rust@1.70.0", "rust", "1.70.0")
        ]

        for (input, expectedName, expectedVersion) in examples {
            let spec = PackageSpecification.parse(input)

            XCTAssertEqual(spec.name, expectedName, "Name parsing failed for '\(input)'")
            XCTAssertEqual(spec.version, expectedVersion, "Version parsing failed for '\(input)'")
            XCTAssertTrue(spec.isValid, "Specification '\(input)' should be valid")

            // Test round-trip
            if expectedVersion != nil {
                XCTAssertEqual(spec.fullSpecification, input, "Round-trip failed for '\(input)'")
            }
        }
    }

    // MARK: - Direct Initialization Tests

    func testDirectInitialization() {
        let spec1 = PackageSpecification(name: "test", version: nil)
        XCTAssertEqual(spec1.name, "test")
        XCTAssertNil(spec1.version)
        XCTAssertEqual(spec1.fullSpecification, "test")

        let spec2 = PackageSpecification(name: "test", version: "1.0.0")
        XCTAssertEqual(spec2.name, "test")
        XCTAssertEqual(spec2.version, "1.0.0")
        XCTAssertEqual(spec2.fullSpecification, "test@1.0.0")
    }
}
