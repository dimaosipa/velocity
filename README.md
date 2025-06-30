# Velocity 🚀

A lightning-fast, modern package manager for macOS - built for Apple Silicon.

**⚠️ Experimental Software**: Velo is in active development and is not recommended for production use. Performance claims are aspirational and based on design goals rather than comprehensive benchmarking. Please test thoroughly and provide feedback!


## ✨ Key Features

- **🏎️ Performance Focused**: Designed for speed with parallel downloads and smart caching
- **🔋 Apple Silicon Native**: Built exclusively for M1/M2/M3 Macs
- **🛡️ User-Space Only**: Never requires `sudo` - everything in `~/.velo/`
- **🔄 Drop-in Compatible**: Uses existing `.rb` formulae from core tap
- **⚡ Modern Architecture**: Async/await, concurrent operations, optimized I/O
- **🧪 Test Infrastructure**: Comprehensive test suite with performance monitoring

## 🚀 Quick Start

### Requirements

- **Apple Silicon Mac**
- **macOS 12+** (Monterey or later)

### Installation

```bash
# Clone and install
git clone https://github.com/dimaosipa/velocity.git
cd velocity
./install.sh
```

**What this does:**
- Builds Velocity in release mode
- Installs `velo` binary to `~/.velo/bin/`
- Adds `~/.velo/bin` to your shell PATH
- Cleans up build artifacts automatically

### First Steps

**Global Package Management:**
```bash
# Check system compatibility
velo doctor

# Install packages globally
velo install wget --global

# Add to PATH (if needed)
echo 'export PATH="$HOME/.velo/bin:$PATH"' >> ~/.zshrc
```

**Local Package Management:**
```bash
# Initialize a project
velo init

# Install packages locally for this project
velo install imagemagick

# Install all dependencies from velo.json
velo install

# Run commands using local packages
velo exec convert image.jpg output.png
```

## 🎯 Performance Goals

Velo is designed with performance in mind, targeting improvements in:

- **Formula Parsing**: Swift-native parsing vs Ruby interpretation
- **Package Installation**: Parallel downloads and optimized extraction
- **Search Operations**: In-memory indexing with smart caching
- **Memory Efficiency**: Lazy loading and memory-mapped files

_Note: Actual performance will vary based on system configuration and network conditions._


## 🏗️ Architecture

See [Architecture](docs/architecture.md) for module structure and key components.

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


See [Usage](docs/usage.md) for command reference and multi-version package support.



See [Installation Management](docs/installation-management.md) for details on self-installation, updates, and data management.



See [Tap Management](docs/tap-management.md) for details on managing taps, tap priority, and related commands.


See [Usage](docs/usage.md) for multi-version package support details.


See [Local Package Management](docs/local-packages.md) for project-local workflows, lock file, CI/CD, and advanced usage.


See [Testing](docs/testing.md) for details on test coverage and methodology.


See [Security](docs/security.md) for security features and best practices.


See [File Layout](docs/file-layout.md) for details on the Velo directory structure.

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
- [x] **Multi-version support** - Install and manage multiple versions of packages simultaneously
- [x] **Local package management** - Project-local .velo directories with velo.json manifests
- [x] **Enhanced tap management** - Context-aware tap operations with automatic velo.json integration for CI/CD reliability
- [x] **Auto-updates for Velo itself** - Self-updating mechanism with GitHub releases integration

### 🚧 In Progress

- [x] **Performance optimizations** - Eliminated redundant operations, smart caching
- [x] **Complex package support** - Successfully handles packages like gcc, libtiff, imagemagick

### 📅 Planned Features

- [ ] **Source builds fallback** - Compile from source when bottles unavailable
- [ ] **Enhanced bottle sources** - Alternative download mirrors and CDN support
- [ ] **Shell completion scripts** - bash/zsh/fish completions
- [ ] **GUI application** - Native macOS app interface

## ⚡ Why Velo?

**Velo** means "speed" in multiple languages, reflecting our core mission: making package management on macOS as fast as possible while maintaining full compatibility with the existing ecosystem.

Built by developers who were tired of waiting for package operations, Velo leverages Apple Silicon's performance to deliver a package manager that feels instant.

---
