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
velo install imagemagick --save
velo install shellcheck --save-dev

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
| `init` | Initialize project with velo.json | `velo init` |
| `install` | Install a package | `velo install wget` |
| `uninstall` | Remove a package | `velo uninstall wget` |
| `switch` | Change default version | `velo switch wget 1.21.3` |
| `exec` | Execute command with local packages | `velo exec convert image.jpg` |
| `which` | Show which binary will be used | `velo which convert` |
| `info` | Show package details | `velo info wget` |
| `list` | List installed packages | `velo list --versions` |
| `search` | Search for packages | `velo search http` |
| `update` | Update repositories | `velo update` |
| `doctor` | Check system health | `velo doctor` |

### Multi-Version Package Support

Velo supports installing and managing multiple versions of the same package simultaneously:

**Installing Specific Versions:**
```bash
# Install latest version
velo install wget

# Install specific version (when available)
velo install wget --version 1.21.3
```

**Managing Multiple Versions:**
```bash
# List all installed versions
velo list --versions

# Switch default version
velo switch wget 1.21.3

# Remove specific version only
velo uninstall wget --version 1.21.3

# Remove all versions
velo uninstall wget
```

**Binary Access:**

- **Default symlinks**: `~/.velo/bin/wget` (points to default version)
- **Versioned symlinks**: `~/.velo/bin/wget@1.21.3` (specific version access)
- **Library compatibility**: Each version maintains independent library paths

## 📦 Local Package Management

Velo supports project-local package management similar to npm's node_modules, enabling reproducible builds and CI caching.

### Project Structure

```text
~/my-project/
├── .velo/                    # Local package directory (like node_modules)
│   ├── Cellar/              # Locally installed packages
│   │   ├── imagemagick/7.1.1-40/
│   │   └── ffmpeg/7.1.0/
│   ├── bin/                 # Local binary symlinks
│   ├── opt/                 # Local opt symlinks
│   └── cache/               # Local download cache
├── velo.json                # Package manifest (like package.json)
├── velo.lock                # Lock file with exact versions
└── your-project-files/
```

### Package Manifest (velo.json)

```json
{
  "name": "my-project",
  "version": "1.0.0",
  "dependencies": {
    "imagemagick": "^7.1.0",
    "ffmpeg": "^7.0.0"
  },
  "devDependencies": {
    "shellcheck": "^0.10.0"
  },
  "scripts": {
    "convert": "convert input.jpg output.png",
    "test": "shellcheck *.sh"
  }
}
```

### Local Package Commands

```bash
# Initialize a new project
velo init

# Install packages locally
velo install imagemagick --save          # Add to dependencies
velo install shellcheck --save-dev       # Add to devDependencies

# Install all dependencies from velo.json
velo install

# Execute commands using local packages
velo exec convert image.jpg output.png   # Uses local imagemagick
velo exec shellcheck script.sh           # Uses local shellcheck

# Show which version will be used
velo which convert                        # Shows resolution order

# Install globally (traditional mode)
velo install wget --global
```

### Version Resolution Priority

When running commands, Velo resolves binaries in this order:

1. **Local packages**: `./.velo/bin/` (project-specific)
2. **Parent directories**: `../.velo/bin/` (if enabled)
3. **Global packages**: `~/.velo/bin/` (user-wide)
4. **System commands**: `/usr/local/bin`, `/usr/bin` (fallback)

### CI/CD Integration

Perfect for continuous integration with caching:

```yaml
# GitHub Actions example
- name: Cache Velo packages
  uses: actions/cache@v3
  with:
    path: .velo
    key: ${{ runner.os }}-velo-${{ hashFiles('velo.lock') }}

- name: Install dependencies
  run: velo install
```

### Benefits

- **Reproducible Builds**: `velo.lock` ensures exact versions
- **CI Caching**: Cache `.velo` directory based on lock file hash
- **Project Isolation**: No global pollution between projects
- **Familiar Workflow**: Similar to npm/yarn ecosystem
- **Version Conflicts**: Different projects can use different tool versions

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
- [x] **Multi-version support** - Install and manage multiple versions of packages simultaneously
- [x] **Local package management** - Project-local .velo directories with velo.json manifests

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