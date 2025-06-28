// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "velo",
    platforms: [
        .macOS(.v12) // Monterey minimum for Apple Silicon
    ],
    products: [
        .executable(
            name: "velo",
            targets: ["Velo"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        // Main executable
        .executableTarget(
            name: "Velo",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "VeloCLI",
                "VeloCore",
                "VeloFormula",
                "VeloSystem"
            ],
            swiftSettings: [
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release)),
                .define("ARCH_ARM64", .when(platforms: [.macOS])),
            ]
        ),
        
        // CLI module
        .target(
            name: "VeloCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "VeloCore",
                "VeloFormula",
                "VeloSystem"
            ]
        ),
        
        // Formula parsing
        .target(
            name: "VeloFormula",
            dependencies: ["VeloSystem"]
        ),
        
        // Core functionality
        .target(
            name: "VeloCore",
            dependencies: ["VeloSystem", "VeloFormula"]
        ),
        
        // System utilities
        .target(
            name: "VeloSystem",
            dependencies: []
        ),
        
        // Tests
        .testTarget(
            name: "VeloCLITests",
            dependencies: ["VeloCLI"]
        ),
        .testTarget(
            name: "VeloCoreTests",
            dependencies: ["VeloCore"]
        ),
        .testTarget(
            name: "VeloFormulaTests",
            dependencies: ["VeloFormula"]
        ),
        .testTarget(
            name: "VeloSystemTests",
            dependencies: ["VeloSystem"]
        ),
        .testTarget(
            name: "VeloIntegrationTests",
            dependencies: ["Velo"]
        ),
    ]
)