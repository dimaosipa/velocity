# Velocity 🚀

> ⚠️ **Experimental Software**: Velo is in active development and is not recommended for production use. Please test thoroughly and provide feedback!

A lightning-fast, modern package manager for macOS - built for Apple Silicon.

## ✨ Key Features

- **🏎️ Performance Focused**: Designed for speed with parallel downloads and smart caching
- **🔋 Apple Silicon Native**: Built exclusively for Apple Silicon Macs
- **🛡️ User-Space Only**: Never requires `sudo` - everything in `~/.velo/`
- **🔄 Drop-in Compatible**: Uses existing `.rb` formulae from core tap
- **⚡ Modern Architecture**: Async/await, concurrent operations, optimized I/O
- **💼 Project-Local Dependencies**: Like npm, but for system packages

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

### First Steps

```bash
# Check system compatibility
velo doctor

# Install a package
velo install wget

# Initialize a project with local packages
velo init
velo install imagemagick
velo exec convert image.jpg output.png
```

## 🎯 Performance Goals

Velo targets significant improvements over traditional package managers:

- **Formula Parsing**: Swift-native parsing vs Ruby interpretation
- **Package Installation**: Parallel downloads and optimized extraction  
- **Search Operations**: In-memory indexing with smart caching
- **Memory Efficiency**: Lazy loading and memory-mapped files

*Note: Performance claims are based on design goals. Actual results may vary.*

## 📚 Documentation

- **[Installation Guide](docs/installation.md)** - Detailed setup instructions
- **[Command Reference](docs/commands.md)** - Complete command documentation
- **[Local Packages](docs/local-packages.md)** - Project-local dependency management
- **[Architecture](docs/architecture.md)** - Technical design and structure
- **[Contributing](docs/contributing.md)** - Development guide and contribution workflow

## 🔒 Security

- **User-Space Only**: Never writes to system directories
- **No Sudo Required**: All operations in `~/.velo/`
- **SHA256 Verification**: All downloads cryptographically verified
- **Code Signing**: Advanced handling of pre-signed binaries

## 📁 File Layout

```
~/.velo/
├── bin/          # Symlinks to binaries (add to PATH)
├── opt/          # Homebrew-compatible package symlinks
├── Cellar/       # Installed packages
├── cache/        # Formula and download cache
├── taps/         # Formula repositories
└── logs/         # Operation logs
```

## 🤝 Contributing

We welcome contributions! See our [Contributing Guide](docs/contributing.md) for details.

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Submit a pull request

## 📄 License

BSD-2-Clause License - see [LICENSE](LICENSE) for details.

## 🎯 Status & Roadmap

### ✅ Completed
- [x] Real tap integration with git-based Homebrew core
- [x] Complete dependency resolution engine
- [x] GHCR bottle downloads with library path rewriting
- [x] Multi-version package support
- [x] Local package management with velo.json
- [x] Auto-updates for Velo itself

### 🚧 In Progress
- [x] Performance optimizations and smart caching
- [x] Complex package support (gcc, imagemagick, etc.)

### 📅 Planned
- [ ] Source compilation fallback
- [ ] Enhanced bottle sources and mirrors
- [ ] Shell completion scripts
- [ ] Native macOS GUI application

---

**⚡ Why Velo?** Built by developers tired of waiting for package operations, Velo leverages Apple Silicon's performance to deliver a package manager that feels instant.

**Website**: [https://dimaosipa.github.io/velocity](https://dimaosipa.github.io/velocity)