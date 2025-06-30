---
title: Architecture Overview
description: Technical architecture, performance goals, and system design
order: 4
category: Technical
---

# Architecture Overview

Velocity is designed with performance and modularity in mind. This document covers the technical architecture, module structure, and performance goals.

## Design Philosophy

### Performance First

Velocity is built around these core performance principles:

- **Native Swift** - No Ruby runtime overhead
- **Async/Await** - Modern concurrency for I/O operations
- **Parallel Operations** - Multi-stream downloads and concurrent processing
- **Smart Caching** - Memory + disk layers with predictive prefetching
- **Memory Efficiency** - Lazy loading and memory-mapped files

### User-Space Only

- **No sudo required** - Everything operates in `~/.velo/`
- **Safe by design** - Never writes to system directories
- **Isolated environment** - Complete separation from system packages

## Module Structure

Velocity follows a layered architecture with clear separation of concerns:

```
VeloSystem    # Core utilities (Logger, Paths, Errors)
    ↓
VeloFormula   # Ruby formula parsing
    ↓  
VeloCore      # Downloads, installs, caching
    ↓
VeloCLI       # Command-line interface
```

### Dependency Flow

- **VeloCLI** depends on all lower layers
- **VeloCore** depends on VeloFormula and VeloSystem
- **VeloFormula** depends on VeloSystem
- **VeloSystem** has no internal dependencies

## Core Components

### VeloSystem

Foundation layer providing system utilities:

**Logger**
- Structured logging with levels (debug, info, warn, error)
- File and console output
- Performance timing and memory tracking

**PathHelper**
- Centralized path management
- Platform-specific path resolution
- Safe path operations with validation

**VeloError**
- Comprehensive error handling
- Structured error types
- User-friendly error messages

### VeloFormula

Ruby formula parsing and management:

**FormulaParser**
- Swift-native Ruby formula parsing with regex optimization
- Extracts: `url`, `sha256`, `desc`, `depends_on`, `bottle` block
- Binary cache for parsed formulas
- Multi-threaded parsing for large tap updates

**Formula**
- Structured representation of Homebrew formulas
- Dependency resolution and version handling
- Platform-specific bottle selection

### VeloCore

Core functionality for package management:

**BottleDownloader**
- Multi-stream parallel downloads (8-16 concurrent streams)
- SHA256 verification for all downloads
- Intelligent retry logic with exponential backoff
- Progress reporting and cancellation support

**Installer**
- Package extraction and installation
- Library path rewriting (`@@HOMEBREW_PREFIX@@`, `@@HOMEBREW_CELLAR@@`)
- Advanced code signing with graceful fallbacks
- Symlink management for binaries and opt directories

**FormulaCache**
- Binary cache with memory + disk layers
- Automatic invalidation and cleanup
- Predictive prefetching for popular packages
- Thread-safe concurrent access

**PerformanceOptimizer**
- CPU, memory, and network optimization
- Battery awareness (reduced activity on battery)
- Memory pressure monitoring
- Adaptive behavior based on system resources

### VeloCLI

Command-line interface and user interaction:

**Commands**
- Structured command implementation using swift-argument-parser
- Consistent error handling and user feedback
- Progress indicators and verbose output options

**Shared Components**
- AsyncRunner for managing concurrent operations
- Common CLI utilities and helpers

## Performance Optimizations

### Formula Parsing

**Swift vs Ruby Performance:**
- 10x faster than Ruby interpretation
- Regex optimization for common patterns
- Binary caching eliminates re-parsing
- Parallel processing for bulk operations

### Download Performance

**Multi-Stream Downloads:**
- 8-16 concurrent streams per package
- Intelligent bandwidth utilization
- Automatic retry with circuit breaker pattern
- Progress aggregation across streams

### Memory Management

**Lazy Loading:**
- Formula metadata loaded on demand
- Memory-mapped files for large data sets
- Automatic cleanup of unused resources

**Smart Caching:**
- LRU eviction for memory cache
- Disk cache with configurable size limits
- Predictive prefetching based on usage patterns

### I/O Optimization

**Async Operations:**
- Non-blocking I/O throughout the stack
- Concurrent package installations
- Background cache warming

**File System:**
- Atomic operations for reliability
- Copy-on-write where possible
- Efficient directory traversal

## Security Architecture

### Isolation

- **User-space only** - Never requires elevated privileges
- **Sandboxed operations** - All changes contained in `~/.velo/`
- **Process isolation** - Separate processes for risky operations

### Verification

- **SHA256 verification** - All downloads cryptographically verified
- **Signature validation** - Package integrity checking
- **Dependency validation** - Ensures consistent dependency chains

### Code Signing

**Advanced Signing Support:**
- Handles complex pre-signed binaries
- Automatic re-signing using ad-hoc signatures
- Extended attribute handling for macOS metadata
- Graceful fallbacks when signing fails

## Data Structures

### File Layout

```
~/.velo/
├── bin/          # Binary symlinks (add to PATH)
├── opt/          # Homebrew-compatible package symlinks
│   ├── wget -> Cellar/wget/1.25.0
│   └── openssl@3 -> Cellar/openssl@3/3.5.0
├── Cellar/       # Installed packages
│   ├── wget/1.25.0/
│   └── openssl@3/3.5.0/
├── cache/        # Formula and download cache
│   ├── formula/  # Parsed formula cache
│   ├── bottles/  # Downloaded packages
│   └── metadata/ # Package metadata
├── taps/         # Formula repositories (git-based)
│   └── homebrew/core/
├── logs/         # Operation logs
└── tmp/          # Temporary build files
```

### Project Structure

```
.velo/            # Local packages (per-project)
├── Cellar/       # Local package installations
├── bin/          # Local binary symlinks
├── opt/          # Local opt symlinks
└── cache/        # Local download cache

velo.json         # Package manifest
velo.lock         # Exact version lock file
```

## Compatibility

### Homebrew Compatibility

**Formula Support:**
- Uses existing `.rb` formulae from Homebrew core tap
- Complete dependency resolution
- Support for complex packages (gcc, imagemagick, etc.)

**Structure Compatibility:**
- `/opt` symlinks for library resolution
- Cellar-style package organization
- Compatible bottle format and URLs

### Platform Support

**Apple Silicon Focus:**
- Optimized for M1/M2/M3 processors
- Native ARM64 bottle support
- Performance tuned for Apple Silicon architecture

**macOS Integration:**
- Native macOS APIs and conventions
- Proper handling of extended attributes
- Integration with system security features

## Future Architecture

### Source Compilation

Planned fallback for when bottles aren't available:

**Build System Integration:**
- Parse `def install` Ruby methods
- Extract configure flags and environment variables
- Handle build dependencies and patches
- Secure build sandboxing

**Compilation Workflow:**
1. Download source tarball from formula URL
2. Verify SHA256 checksum
3. Extract to temporary build directory
4. Apply patches if specified in formula
5. Install build dependencies
6. Execute configure/cmake with formula flags
7. Run make/ninja build
8. Install to `~/.velo/Cellar/<pkg>/<version>/`
9. Create symlinks and opt links
10. Clean up build directory

### Enhanced Performance

**Planned Optimizations:**
- JIT compilation for formula parsing
- Distributed caching with CDN support
- Machine learning for prefetching
- WebAssembly for portable build scripts

## Monitoring and Observability

### Performance Metrics

- Download speeds and completion times
- Formula parsing performance
- Memory usage patterns
- Cache hit ratios

### Error Tracking

- Structured error reporting
- Performance regression detection
- Crash reporting and analysis
- User experience metrics

### Logging

- Structured JSON logging
- Configurable log levels
- Rotation and cleanup
- Integration with system logging