---
title: Contributing Guide
description: How to contribute to Velocity development
order: 6
category: Development
---

# Contributing Guide

Thank you for your interest in contributing to Velocity! This guide will help you get started with contributing code, documentation, or bug reports.

## Getting Started

### Prerequisites

Before contributing, ensure you have:

- **Apple Silicon Mac** (M1, M2, M3, or later)
- **Xcode 15+** with Swift 5.9+
- **macOS 12+** (Monterey or later)
- **Git** and **GitHub account**
- **Basic Swift knowledge**

### Fork and Clone

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:

```bash
git clone https://github.com/yourusername/velocity.git
cd velocity
```

3. **Add upstream** remote:

```bash
git remote add upstream https://github.com/dimaosipa/velocity.git
```

4. **Verify** the build works:

```bash
swift build
swift test
```

## Types of Contributions

### Bug Reports

Help us improve by reporting bugs:

1. **Search existing issues** to avoid duplicates
2. **Use the bug report template** when creating issues
3. **Include system information**:
   - Velocity version (`velo --version`)
   - macOS version
   - Hardware (M1/M2/M3)
4. **Provide reproduction steps**
5. **Include relevant logs** from `~/.velo/logs/`

### Feature Requests

Suggest new features:

1. **Check existing feature requests** and roadmap
2. **Use the feature request template**
3. **Explain the use case** and motivation
4. **Consider performance implications**
5. **Discuss implementation approach** if you have ideas

### Code Contributions

We welcome code contributions for:

- **Bug fixes**
- **New features**
- **Performance improvements**
- **Test coverage improvements**
- **Documentation updates**

## Development Workflow

### Setting Up Development Environment

```bash
# Fork and clone (see above)
cd velocity

# Install as development symlink
swift build -c release
./build/release/velo install-self --symlink

# Now velo uses your development version
velo --version
```

### Making Changes

1. **Create a feature branch**:

```bash
git checkout -b feature/my-new-feature
# or
git checkout -b fix/bug-description
```

2. **Make your changes** following the code style guide

3. **Add tests** for new functionality:

```bash
# Add unit tests
# Add integration tests if needed
swift test
```

4. **Update documentation** if needed

5. **Commit your changes**:

```bash
git add .
git commit -m "feat: add new feature description"
# or
git commit -m "fix: resolve issue with X"
```

### Running Tests

Before submitting, ensure all tests pass:

```bash
# Run all tests
swift test

# Run specific test suites
swift test --filter VeloCoreTests
swift test --filter VeloIntegrationTests

# Run performance benchmarks
swift test --filter PerformanceBenchmarks

# Test with verbose output
swift test --verbose
```

### Code Style Guidelines

#### Swift Style

Follow these conventions:

- **Use Swift 5.9+ features** when appropriate
- **Prefer value types** over reference types
- **Use async/await** for asynchronous operations
- **Handle errors explicitly** with proper error types
- **Add documentation** for public APIs

#### Example Code Style

```swift
// Good: Clear, documented public API
/// Downloads and installs a package from the specified URL
/// - Parameters:
///   - packageName: The name of the package to install
///   - url: The download URL for the package
/// - Returns: The installed package information
/// - Throws: `InstallError` if installation fails
public func installPackage(_ packageName: String, from url: URL) async throws -> Package {
    let logger = Logger.shared
    logger.info("Installing package: \(packageName)")
    
    // Implementation with proper error handling
    do {
        let data = try await downloadData(from: url)
        return try await processPackage(data, name: packageName)
    } catch {
        logger.error("Failed to install \(packageName): \(error)")
        throw InstallError.downloadFailed(error)
    }
}
```

#### Error Handling

Use structured error types:

```swift
enum InstallError: Error, LocalizedError {
    case packageNotFound(String)
    case downloadFailed(Error)
    case verificationFailed
    
    var errorDescription: String? {
        switch self {
        case .packageNotFound(let name):
            return "Package '\(name)' not found"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .verificationFailed:
            return "Package verification failed"
        }
    }
}
```

#### Performance Guidelines

- **Use async/await** for I/O operations
- **Implement caching** for expensive operations
- **Prefer lazy loading** for large data structures
- **Measure performance** for critical paths
- **Add benchmarks** for performance-sensitive code

### Testing Guidelines

#### Unit Tests

Write comprehensive unit tests:

```swift
class FormulaParserTests: XCTestCase {
    func testParseSimpleFormula() throws {
        let formula = """
        class Wget < Formula
          desc "Internet file retriever"
          homepage "https://www.gnu.org/software/wget/"
          url "https://ftp.gnu.org/gnu/wget/wget-1.25.0.tar.gz"
          sha256 "fa2dc35bab5184ecbc46a9ef83def2aaaa3f4c9f3c97d4bd19dcb07d4da637de"
        end
        """
        
        let parser = FormulaParser()
        let result = try parser.parse(formula)
        
        XCTAssertEqual(result.name, "wget")
        XCTAssertEqual(result.desc, "Internet file retriever")
        XCTAssertNotNil(result.url)
        XCTAssertNotNil(result.sha256)
    }
}
```

#### Integration Tests

Test complete workflows:

```swift
class InstallIntegrationTests: XCTestCase {
    func testInstallSimplePackage() async throws {
        let tempDir = try createTempDirectory()
        let installer = Installer(rootPath: tempDir)
        
        let package = try await installer.install("wget")
        
        XCTAssertTrue(package.isInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.binaryPath))
    }
}
```

## Submitting Changes

### Pull Request Process

1. **Push your branch** to your fork:

```bash
git push origin feature/my-new-feature
```

2. **Create a pull request** on GitHub

3. **Fill out the PR template** with:
   - **Description** of changes
   - **Related issues** (if any)
   - **Testing done**
   - **Performance impact** (if applicable)

4. **Respond to feedback** and update as needed

### PR Requirements

Before merging, PRs must:

- **Pass all tests** (CI will verify)
- **Include tests** for new functionality
- **Have no merge conflicts**
- **Follow code style** guidelines
- **Include documentation** updates if needed
- **Have clear commit messages**

### Commit Message Format

Use conventional commit format:

```
type(scope): description

[optional body]

[optional footer]
```

**Types:**
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `test:` - Adding or updating tests
- `refactor:` - Code refactoring
- `perf:` - Performance improvements
- `ci:` - CI/CD changes

**Examples:**
```
feat(installer): add support for custom installation paths
fix(parser): handle malformed formula files gracefully
docs(readme): update installation instructions
test(core): add integration tests for download functionality
```

## Code Review Process

### What We Look For

- **Functionality** - Does the code work as intended?
- **Tests** - Are there adequate tests with good coverage?
- **Performance** - Will this impact performance?
- **Security** - Are there security implications?
- **Maintainability** - Is the code readable and well-structured?
- **Documentation** - Is public API documented?

### Review Timeline

- **Initial review** - Within 1-2 business days
- **Follow-up reviews** - Within 1 business day
- **Merge** - After approval and CI passes

## Community Guidelines

### Be Respectful

- **Be kind and respectful** in all interactions
- **Assume good intent** from contributors
- **Provide constructive feedback**
- **Help newcomers** get started

### Communication

- **Use GitHub issues** for bug reports and feature requests
- **Use GitHub discussions** for general questions
- **Use pull request comments** for code-specific discussions

## Getting Help

### Where to Ask Questions

- **GitHub Discussions** - General questions and help
- **GitHub Issues** - Bug reports and feature requests
- **Pull Request Comments** - Code-specific questions

### Documentation

- **README** - Quick start and overview
- **docs/** - Detailed documentation
- **Code comments** - Implementation details
- **Tests** - Usage examples

## Recognition

Contributors are recognized in:

- **Release notes** for significant contributions
- **Contributors list** in the repository
- **Special thanks** for major features or fixes

## License

By contributing to Velocity, you agree that your contributions will be licensed under the same BSD-2-Clause License that covers the project.

---

Thank you for contributing to Velocity! Your help makes the project better for everyone.