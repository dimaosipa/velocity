# Velo 🚀

A lightning-fast, modern package manager for macOS - built for Apple Silicon.

## ✨ Key Features

- **🏎️ Performance Focused**: Designed for speed with parallel downloads and smart caching
- **🔋 Apple Silicon Native**: Built exclusively for M1/M2/M3 Macs
- **🛡️ User-Space Only**: Never requires `sudo` - everything in `~/.velo/`
- **🔄 Drop-in Compatible**: Uses existing `.rb` formulae from core tap
- **⚡ Modern Architecture**: Async/await, concurrent operations, optimized I/O
- **🧪 Test Infrastructure**: Comprehensive test suite with performance monitoring

## 🚀 Quick Start

### Requirements

- **Apple Silicon Mac** (M1/M2/M3)
- **macOS 12+** (Monterey or later)

### Installation

```bash
# Clone and build
git clone https://github.com/bomjkolyadun/velo.git
cd velo
swift build -c release

# Copy to local bin (optional)
cp .build/release/velo /usr/local/bin/
```

### First Steps

```bash
# Check system compatibility
velo doctor

# Search for packages
velo search wget

# Get package information
velo info wget

# Install a package
velo install wget

# List installed packages
velo list

# Add to PATH (if needed)
echo 'export PATH="$HOME/.velo/bin:$PATH"' >> ~/.zshrc
```

## 🎯 Performance Goals

Velo is designed with performance in mind, targeting improvements in:

- **Formula Parsing**: Swift-native parsing vs Ruby interpretation
- **Package Installation**: Parallel downloads and optimized extraction
- **Search Operations**: In-memory indexing with smart caching
- **Memory Efficiency**: Lazy loading and memory-mapped files

_Note: Actual performance will vary based on system configuration and network conditions._

## 🏗️ Architecture

### Module Structure

```
VeloSystem    # Core utilities (Logger, Paths, Errors)
    ↓
VeloFormula   # Ruby formula parsing
    ↓  
VeloCore      # Downloads, installs, caching
    ↓
VeloCLI       # Command-line interface
```

### Key Components

- **FormulaParser**: Swift-native Ruby formula parsing with regex optimization
- **BottleDownloader**: Multi-stream parallel downloads with SHA256 verification
- **FormulaCache**: Binary cache with memory + disk layers for fast lookups
- **PerformanceOptimizer**: CPU, memory, and network optimization framework

## 🛠️ Development

### Building

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

### Project Structure

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

### Commands Available

| Command | Description | Example |
|---------|-------------|---------|
| `install` | Install a package | `velo install wget` |
| `uninstall` | Remove a package | `velo uninstall wget` |
| `info` | Show package details | `velo info wget` |
| `list` | List installed packages | `velo list --versions` |
| `search` | Search for packages | `velo search http` |
| `update` | Update repositories | `velo update` |
| `doctor` | Check system health | `velo doctor` |

### Performance Features

- **Smart Caching**: Formula metadata cached in binary format
- **Parallel Downloads**: 8-16 concurrent streams per bottle
- **Memory Optimization**: Lazy loading, memory-mapped files
- **Predictive Prefetching**: Popular packages cached proactively
- **Battery Awareness**: Reduced activity on battery power

## 🧪 Testing

Velo includes comprehensive testing:

- **Unit Tests**: All core components tested
- **Integration Tests**: Full CLI workflow testing
- **Performance Benchmarks**: Regression detection
- **Memory Leak Detection**: Automated leak checking
- **Stress Tests**: High concurrency validation

## 🔒 Security

- **User-Space Only**: Never writes to system directories
- **No Sudo Required**: All operations in `~/.velo/`
- **SHA256 Verification**: All downloads cryptographically verified
- **Advanced Code Signing**: Handles complex pre-signed binaries with automatic re-signing using ad-hoc signatures
- **Extended Attribute Handling**: Proper clearance of resource forks and macOS metadata
- **Graceful Fallbacks**: Installation continues even when some binaries can't be signed

## 📁 File Layout

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

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Run the full test suite
5. Submit a pull request

### Code Style

- Swift 5.9+ features encouraged
- Comprehensive error handling required
- Performance-first mindset
- Tests required for all new features

## 📄 License

BSD-2-Clause License - see [LICENSE](LICENSE) for details.

## 🎯 Roadmap

### ✅ Completed Features

- [x] **Real tap integration** - Full git-based Homebrew core tap support
- [x] **Dependency resolution engine** - Complete dependency management with critical dependency tracking
- [x] **GHCR bottle downloads** - Hierarchical URL support for all package types including @-versioned packages
- [x] **Library path rewriting** - Automatic @@HOMEBREW_PREFIX@@ and @@HOMEBREW_CELLAR@@ placeholder resolution
- [x] **Code signing compatibility** - Enhanced signing for complex pre-signed binaries with graceful fallbacks
- [x] **Homebrew-compatible structure** - /opt symlinks and complete library resolution

### 🚧 In Progress

- [x] **Performance optimizations** - Eliminated redundant operations, smart caching
- [x] **Complex package support** - Successfully handles packages like gcc, libtiff, imagemagick

### 📅 Planned Features

- [ ] **Source builds fallback** - Compile from source when bottles unavailable
- [ ] **Enhanced bottle sources** - Alternative download mirrors and CDN support
- [ ] **Auto-updates for Velo itself** - Self-updating mechanism
- [ ] **Shell completion scripts** - bash/zsh/fish completions
- [ ] **GUI application** - Native macOS app interface

## ⚡ Why Velo?

**Velo** means "speed" in multiple languages, reflecting our core mission: making package management on macOS as fast as possible while maintaining full compatibility with the existing ecosystem.

Built by developers who were tired of waiting for package operations, Velo leverages Apple Silicon's performance to deliver a package manager that feels instant.

---

**⚠️ Experimental Software**: Velo is in active development and is not recommended for production use. Performance claims are aspirational and based on design goals rather than comprehensive benchmarking. Please test thoroughly and provide feedback!