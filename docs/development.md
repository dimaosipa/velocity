---
title: Development Guide
description: Building, testing, and developing Velocity
order: 5
category: Development
---

# Development Guide

This guide covers building Velocity from source, running tests, and contributing to development.

## Prerequisites

- **Xcode 15+** with Swift 5.9+
- **Apple Silicon Mac** (M1, M2, M3, or later)
- **macOS 12+** (Monterey or later)
- **Git** for source control

## Building from Source

### Quick Build

```bash
# Clone the repository
git clone https://github.com/dimaosipa/velocity.git
cd velocity

# Debug build (faster compilation)
swift build

# Release build (optimized for performance)
swift build -c release

# Run the binary
.build/debug/velo --help
.build/release/velo --help
```

### Development Installation

For active development, install as a symlink:

```bash
# Build and install as symlink
swift build -c release
velo install-self --symlink

# Now velo automatically uses your latest build
swift build -c release  # Rebuild
velo --version           # Uses new version immediately
```

## Project Structure

```
Sources/
├── Velo/           # Main executable entry point
├── VeloCLI/        # Command-line interface
│   ├── Commands/   # Individual CLI commands
│   ├── Shared/     # Shared CLI utilities
│   └── Velo.swift  # Main CLI coordinator
├── VeloCore/       # Core functionality
│   ├── BottleDownloader.swift
│   ├── Installer.swift
│   ├── FormulaCache.swift
│   └── ...
├── VeloFormula/    # Formula parsing
│   ├── Formula.swift
│   └── FormulaParser.swift
└── VeloSystem/     # System utilities
    ├── Logger.swift
    ├── PathHelper.swift
    └── VeloError.swift

Tests/
├── VeloCLITests/           # CLI command tests
├── VeloCoreTests/          # Core functionality tests
├── VeloFormulaTests/       # Formula parsing tests
├── VeloSystemTests/        # System utility tests
├── VeloIntegrationTests/   # End-to-end tests
│   ├── CLIIntegrationTests.swift
│   ├── PerformanceBenchmarks.swift
│   └── RealCLITests.swift
└── Fixtures/               # Test data
    └── Formulae/
        ├── simple.rb
        ├── complex.rb
        └── wget.rb
```

## Testing

Velocity includes comprehensive testing at multiple levels:

### Unit Tests

Test individual components:

```bash
# Run all unit tests
swift test

# Run specific test target
swift test --filter VeloCoreTests
swift test --filter VeloFormulaTests

# Run specific test case
swift test --filter FormulaParserTests.testSimpleFormula

# Run with verbose output
swift test --verbose
```

### Integration Tests

Test complete workflows:

```bash
# Run integration tests
swift test --filter VeloIntegrationTests

# Run CLI integration tests
swift test --filter CLIIntegrationTests

# Run real CLI tests (requires network)
swift test --filter RealCLITests
```

### Performance Benchmarks

Monitor performance regressions:

```bash
# Run performance benchmarks
swift test --filter PerformanceBenchmarks

# Run specific benchmark
swift test --filter PerformanceBenchmarks.testFormulaParsingPerformance
```

### Memory Leak Detection

```bash
# Run tests with leak detection
swift test --enable-code-coverage --sanitize address
```

### Test Coverage

```bash
# Generate coverage report
swift test --enable-code-coverage

# View coverage
open .build/debug/codecov/*.html
```

## Development Workflow

### Code Style

Velocity follows Swift best practices:

- **Swift 5.9+ features** encouraged
- **Comprehensive error handling** required
- **Performance-first mindset**
- **Tests required** for all new features
- **Documentation** for public APIs

### Adding New Commands

1. **Create command file** in `Sources/VeloCLI/Commands/`
2. **Implement ParsableCommand** protocol
3. **Add to main CLI** in `Velo.swift`
4. **Add tests** in `Tests/VeloCLITests/`
5. **Update documentation**

Example command structure:

```swift
import ArgumentParser
import VeloCore

struct MyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "my-command",
        abstract: "Description of what this command does"
    )
    
    @Flag(help: "Enable verbose output")
    var verbose: Bool = false
    
    @Argument(help: "Package name")
    var packageName: String
    
    func run() async throws {
        let logger = Logger.shared
        // Implementation here
    }
}
```

### Adding New Core Features

1. **Design the API** - Consider performance and usability
2. **Implement the feature** - Follow existing patterns
3. **Add comprehensive tests** - Unit and integration
4. **Update performance benchmarks** - If relevant
5. **Document the feature** - Code comments and user docs

### Performance Considerations

Always consider performance when making changes:

- **Async/await** for I/O operations
- **Lazy loading** for expensive resources
- **Caching** for repeated operations
- **Memory efficiency** - avoid unnecessary allocations
- **Concurrent operations** where safe

## Testing Strategy

### Test Categories

1. **Unit Tests** - Fast, isolated, comprehensive coverage
2. **Integration Tests** - Real workflows, moderate speed
3. **Performance Tests** - Benchmark critical paths
4. **End-to-End Tests** - Full CLI testing with real packages

### Test Data

- **Fixtures** - Sample formula files for testing
- **Mock objects** - Isolate components under test
- **Real data** - Some tests use actual Homebrew formulas

### CI Integration

Tests run automatically on:
- Pull requests
- Main branch commits
- Release tags

## Debugging

### Common Issues

**Build failures:**
```bash
# Clean build artifacts
swift package clean

# Reset package cache
swift package reset

# Update dependencies
swift package update
```

**Test failures:**
```bash
# Run specific failing test
swift test --filter TestName.testMethod

# Debug with lldb
swift test --filter TestName.testMethod --debug
```

**Performance issues:**
```bash
# Profile with Instruments
swift build -c release
# Use Xcode Instruments on the binary
```

### Logging

Enable debug logging:

```bash
# Set environment variable
export VELO_LOG_LEVEL=debug

# Or use --verbose flag
velo install wget --verbose
```

## Code Organization

### Module Dependencies

- **VeloCLI** - Command-line interface, depends on all others
- **VeloCore** - Core functionality, depends on VeloFormula and VeloSystem
- **VeloFormula** - Formula parsing, depends on VeloSystem
- **VeloSystem** - System utilities, no dependencies

### Error Handling

Use structured errors:

```swift
enum MyFeatureError: Error, LocalizedError {
    case invalidInput(String)
    case networkFailure(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let input):
            return "Invalid input: \(input)"
        case .networkFailure(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
```

### Async Patterns

Use async/await consistently:

```swift
func downloadPackage(_ name: String) async throws -> Package {
    let metadata = try await fetchMetadata(name)
    let data = try await downloadData(metadata.url)
    return try await processPackage(data)
}
```

## Release Process

### Version Management

Velocity uses semantic versioning:
- **Major** - Breaking changes
- **Minor** - New features, backward compatible
- **Patch** - Bug fixes, backward compatible

### Creating Releases

1. **Update version** in appropriate files
2. **Run full test suite** including benchmarks
3. **Update documentation** if needed
4. **Create release tag** with release notes
5. **Build release binaries** for distribution

### Performance Regression Testing

Before releases, run performance benchmarks:

```bash
# Baseline performance
git checkout previous-release
swift test --filter PerformanceBenchmarks > baseline.txt

# Current performance
git checkout main
swift test --filter PerformanceBenchmarks > current.txt

# Compare results
diff baseline.txt current.txt
```

## Profiling and Optimization

### Instruments Integration

Use Xcode Instruments for profiling:

1. **Build release binary** - `swift build -c release`
2. **Open in Instruments** - Profile for CPU, memory, or I/O
3. **Analyze bottlenecks** - Focus on hot paths
4. **Optimize and measure** - Verify improvements

### Memory Profiling

Common memory issues to watch for:
- **Retain cycles** - Use weak references appropriately
- **Large allocations** - Use streaming for large data
- **Cache bloat** - Implement proper eviction policies

### Performance Testing

Add benchmarks for critical operations:

```swift
func testFormulaParsingPerformance() throws {
    measure {
        // Performance-critical operation
        let parser = FormulaParser()
        _ = try! parser.parse(formulaContent)
    }
}
```

## Getting Help

- **Documentation** - Check existing docs first
- **Tests** - Look at test examples for usage patterns
- **Issues** - Search existing GitHub issues
- **Discussions** - Ask questions in GitHub discussions