import XCTest
@testable import VeloFormula

final class FormulaTests: XCTestCase {

    func testFormulaInitialization() {
        let formula = Formula(
            name: "test",
            description: "Test package",
            homepage: "https://test.com",
            url: "https://test.com/test-1.0.tar.gz",
            sha256: "abc123",
            version: "1.0",
            dependencies: [
                Formula.Dependency(name: "dep1"),
                Formula.Dependency(name: "dep2", type: .build)
            ],
            bottles: [
                Formula.Bottle(sha256: "def456", platform: .arm64_sonoma)
            ]
        )

        XCTAssertEqual(formula.name, "test")
        XCTAssertEqual(formula.version, "1.0")
        XCTAssertEqual(formula.dependencies.count, 2)
        XCTAssertEqual(formula.bottles.count, 1)
    }

    func testBottlePlatformCompatibility() {
        let platforms: [Formula.Bottle.Platform] = [
            .arm64_monterey,
            .arm64_ventura,
            .arm64_sonoma,
            .arm64_sequoia
        ]

        let currentVersion = ProcessInfo.processInfo.operatingSystemVersion

        for platform in platforms {
            let requiredMajor = Int(platform.osVersion) ?? 12
            let isCompatible = currentVersion.majorVersion >= requiredMajor
            XCTAssertEqual(platform.isCompatible, isCompatible)
        }
    }

    func testPreferredBottleSelection() {
        // Create bottles for different OS versions
        let bottles = [
            Formula.Bottle(sha256: "monterey_sha", platform: .arm64_monterey),
            Formula.Bottle(sha256: "ventura_sha", platform: .arm64_ventura),
            Formula.Bottle(sha256: "sonoma_sha", platform: .arm64_sonoma),
            Formula.Bottle(sha256: "sequoia_sha", platform: .arm64_sequoia)
        ]

        let formula = Formula(
            name: "test",
            description: "Test",
            homepage: "https://test.com",
            url: "https://test.com/test.tar.gz",
            sha256: "source_sha",
            version: "1.0",
            dependencies: [],
            bottles: bottles
        )

        // The preferred bottle should be the newest compatible one
        let preferred = formula.preferredBottle
        XCTAssertNotNil(preferred)

        // It should pick the newest compatible version
        let currentMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if currentMajor >= 15 {
            XCTAssertEqual(preferred?.platform, .arm64_sequoia)
        } else if currentMajor >= 14 {
            XCTAssertEqual(preferred?.platform, .arm64_sonoma)
        } else if currentMajor >= 13 {
            XCTAssertEqual(preferred?.platform, .arm64_ventura)
        } else {
            XCTAssertEqual(preferred?.platform, .arm64_monterey)
        }
    }

    func testBottleURL() {
        let bottle = Formula.Bottle(
            sha256: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
            platform: .arm64_sonoma
        )

        let formula = Formula(
            name: "wget",
            description: "Test",
            homepage: "https://test.com",
            url: "https://test.com/test.tar.gz",
            sha256: "source_sha",
            version: "1.0",
            dependencies: [],
            bottles: [bottle]
        )

        let bottleURL = formula.bottleURL(for: bottle)
        XCTAssertEqual(
            bottleURL,
            "https://ghcr.io/v2/homebrew/core/wget/blobs/sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        )
    }

    func testHasCompatibleBottle() {
        // Formula with no bottles
        let noBottles = Formula(
            name: "test",
            description: "Test",
            homepage: "https://test.com",
            url: "https://test.com/test.tar.gz",
            sha256: "sha",
            version: "1.0",
            dependencies: [],
            bottles: []
        )
        XCTAssertFalse(noBottles.hasCompatibleBottle)

        // Formula with compatible bottle
        let withBottles = Formula(
            name: "test",
            description: "Test",
            homepage: "https://test.com",
            url: "https://test.com/test.tar.gz",
            sha256: "sha",
            version: "1.0",
            dependencies: [],
            bottles: [Formula.Bottle(sha256: "sha", platform: .arm64_sonoma)]
        )

        // This depends on the current OS version
        let currentMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if currentMajor >= 14 {
            XCTAssertTrue(withBottles.hasCompatibleBottle)
        }
    }

    func testDependencyTypes() {
        let deps = [
            Formula.Dependency(name: "dep1"),
            Formula.Dependency(name: "dep2", type: .build),
            Formula.Dependency(name: "dep3", type: .optional),
            Formula.Dependency(name: "dep4", type: .recommended)
        ]

        XCTAssertEqual(deps[0].type, .required)
        XCTAssertEqual(deps[1].type, .build)
        XCTAssertEqual(deps[2].type, .optional)
        XCTAssertEqual(deps[3].type, .recommended)
    }

    func testFormulaCodable() throws {
        let original = Formula(
            name: "test",
            description: "Test package",
            homepage: "https://test.com",
            url: "https://test.com/test-1.0.tar.gz",
            sha256: "abc123",
            version: "1.0",
            dependencies: [Formula.Dependency(name: "dep1")],
            bottles: [Formula.Bottle(sha256: "def456", platform: .arm64_sonoma)]
        )

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Formula.self, from: data)

        // Verify
        XCTAssertEqual(original, decoded)
    }
}
