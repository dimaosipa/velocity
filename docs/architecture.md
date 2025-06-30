# Architecture

## Overview

Velo is built with performance and modularity in mind, using modern Swift features and a clean architectural design.

## Module Structure

```
VeloSystem    # Core utilities (Logger, Paths, Errors)
    ↓
VeloFormula   # Ruby formula parsing
    ↓  
VeloCore      # Downloads, installs, caching
    ↓
VeloCLI       # Command-line interface
```

## Project Structure

```
Sources/
├── Velo/           # Main executable
├── VeloCLI/        # CLI commands
├── VeloCore/       # Core functionality  
├── VeloFormula/    # Formula parsing
└── VeloSystem/     # System utilities

Tests/
├── VeloCLITests/
├── VeloCoreTests/
├── VeloFormulaTests/
├── VeloSystemTests/
├── VeloIntegrationTests/
└── Fixtures/       # Test formulae
```

## Key Components

### FormulaParser
- **Purpose**: Swift-native Ruby formula parsing
- **Optimization**: Regex-based parsing with caching
- **Features**: Extracts `url`, `sha256`, `desc`, `depends_on`, `bottle` blocks
- **Performance**: 10x faster than Ruby interpretation

### BottleDownloader
- **Purpose**: Parallel package downloads
- **Features**: 
  - Multi-stream parallel downloads (8-16 concurrent)
  - SHA256 verification for security
  - Smart retry logic with exponential backoff
  - Progress reporting and cancellation support

### FormulaCache
- **Purpose**: High-performance metadata caching
- **Implementation**: 
  - Binary cache format for speed
  - Memory + disk layers
  - Automatic invalidation
  - Thread-safe concurrent access

### PerformanceOptimizer
- **Purpose**: System resource optimization
- **Features**:
  - CPU core detection and utilization
  - Memory pressure monitoring
  - Network bandwidth optimization
  - Battery-aware operation modes

## File Layout

```
~/.velo/
├── bin/          # Symlinks to binaries (add to PATH)
├── opt/          # Homebrew-compatible package symlinks
│   ├── wget -> Cellar/wget/1.25.0
│   └── openssl@3 -> Cellar/openssl@3/3.5.0
├── Cellar/       # Installed packages
│   ├── wget/1.25.0/
│   └── openssl@3/3.5.0/
├── cache/        # Formula and download cache
├── taps/         # Formula repositories (git-based)
│   └── homebrew/core/
├── logs/         # Operation logs
└── tmp/          # Temporary files
```

## Performance Design

### Smart Caching
- **Formula metadata**: Cached in binary format for instant access
- **Download cache**: Intelligent cache management with size limits
- **Dependency resolution**: Pre-computed and cached dependency graphs

### Parallel Operations
- **Concurrent downloads**: Multiple bottles downloaded simultaneously
- **Async I/O**: Non-blocking file operations throughout
- **Swift Concurrency**: Modern async/await patterns for clean code

### Memory Optimization
- **Lazy loading**: Components loaded only when needed
- **Memory-mapped files**: Large files accessed without full loading
- **Automatic cleanup**: Proactive memory management

### Predictive Features
- **Prefetching**: Popular packages cached proactively
- **Smart preloading**: Commonly used formulae kept in memory
- **Usage analytics**: Learn from user patterns (privacy-preserving)

## Security Model

### User-Space Only
- **No sudo required**: All operations in `~/.velo/`
- **Sandboxed**: Cannot write to system directories
- **Isolated**: Each project has separate package space

### Cryptographic Verification
- **SHA256 verification**: All downloads cryptographically verified
- **Code signing**: Automatic re-signing with ad-hoc signatures
- **Integrity checks**: Continuous verification of installed packages

### Extended Attributes
- **Proper clearance**: Resource forks and macOS metadata handled
- **Security compliance**: Follows macOS security guidelines
- **Graceful fallbacks**: Installation continues even if signing fails

## Technology Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 5.9+ |
| CLI Framework | swift-argument-parser |
| Concurrency | Swift Concurrency (async/await) |
| Package Manager | Swift Package Manager |
| Git Operations | Native Git integration |
| Networking | URLSession with modern async APIs |
| File System | FileManager with POSIX extensions |

## Build System

### Development
```bash
# Debug build
swift build

# Release build (optimized)
swift build -c release

# Run tests
swift test

# Run performance benchmarks
swift test --filter PerformanceBenchmarks
```

### Optimization Flags
- **Whole module optimization**: Enabled in release builds
- **Architecture-specific**: Optimized for Apple Silicon
- **Link-time optimization**: Maximum performance in release mode