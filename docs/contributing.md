# Contributing

We welcome contributions to Velo! This guide will help you get started.

## Development Setup

### Prerequisites
- macOS 12+ with Apple Silicon (M1/M2/M3)
- Xcode 14+ or Command Line Tools
- Swift 5.9+

### Getting Started

```bash
# Clone the repository
git clone https://github.com/dimaosipa/velocity.git
cd velocity

# Build in debug mode
swift build

# Run tests
swift test

# Install for development
./install.sh
```

## Code Style

- Swift 5.9+ features encouraged
- Comprehensive error handling required
- Performance-first mindset
- Tests required for all new features

### Code Guidelines

1. **Error Handling**: Use Result types and proper error propagation
2. **Async/Await**: Prefer modern concurrency over completion handlers
3. **Documentation**: All public APIs must be documented
4. **Testing**: Unit tests for core logic, integration tests for CLI
5. **Performance**: Consider performance implications of all changes

## Testing

Velo includes comprehensive testing:

- **Unit Tests**: All core components tested
- **Integration Tests**: Full CLI workflow testing
- **Performance Benchmarks**: Regression detection
- **Memory Leak Detection**: Automated leak checking
- **Stress Tests**: High concurrency validation

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter VeloCoreTests

# Run performance benchmarks
swift test --filter PerformanceBenchmarks

# Run with coverage
swift test --enable-code-coverage
```

## Architecture

Before contributing, familiarize yourself with our [architecture](architecture.md):

- **VeloSystem**: Core utilities and error handling
- **VeloFormula**: Ruby formula parsing logic
- **VeloCore**: Package management and installation
- **VeloCLI**: Command-line interface and argument parsing

## Making Changes

### 1. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Your Changes

- Write tests first (TDD approach recommended)
- Implement your feature
- Ensure all tests pass
- Update documentation if needed

### 3. Performance Considerations

If your change affects performance:

- Run benchmarks before and after
- Include performance test results in PR
- Consider memory usage implications
- Test with large package sets

### 4. Submit a Pull Request

1. **Test thoroughly**: All tests must pass
2. **Document changes**: Update relevant documentation
3. **Performance impact**: Note any performance implications
4. **Breaking changes**: Clearly mark any breaking changes

## Commit Guidelines

- Use clear, descriptive commit messages
- Follow conventional commit format when possible
- Keep commits atomic and focused
- Squash commits before merging if requested

Example:
```
feat: add parallel download support for bottles

- Implement concurrent download manager
- Add progress reporting and cancellation
- Include comprehensive error handling
- Performance improvement: 3x faster installs
```

## Areas for Contribution

### High Priority
- **Source compilation fallback**: Build packages from source when bottles unavailable
- **Enhanced bottle sources**: Alternative download mirrors and CDN support
- **Shell completion scripts**: bash/zsh/fish completions

### Medium Priority
- **GUI application**: Native macOS app interface
- **Performance optimizations**: Profile and optimize hot paths
- **Error handling improvements**: Better error messages and recovery

### Low Priority
- **Documentation improvements**: Always welcome
- **Test coverage**: Increase test coverage
- **Code cleanup**: Refactoring and code quality improvements

## Performance Benchmarks

When working on performance:

```bash
# Baseline benchmarks
swift test --filter PerformanceBenchmarks

# Profile with Instruments
swift build -c release
# Use Xcode Instruments for detailed profiling

# Memory usage testing
swift test --filter MemoryLeakTests
```

## Release Process

1. **Version bump**: Update version in appropriate files
2. **Changelog**: Update CHANGELOG.md with changes
3. **Testing**: Full test suite on clean environment
4. **Documentation**: Ensure all docs are current
5. **Performance**: Verify no performance regressions

## Getting Help

- **Discussions**: Use GitHub Discussions for questions
- **Issues**: Report bugs via GitHub Issues  
- **Discord**: Join our community Discord (link in README)
- **Email**: Contact maintainers directly for sensitive issues

## Code of Conduct

We are committed to providing a welcoming and inclusive environment. Please:

- Be respectful and constructive
- Focus on technical merit
- Help newcomers learn and contribute
- Report any concerning behavior to maintainers

## Legal

By contributing, you agree that your contributions will be licensed under the same BSD-2-Clause license that covers the project.