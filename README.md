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
| `update-self` | Update velo to latest version | `velo update-self` |
| `verify` | Check if installed packages match velo.lock | `velo verify` |
| `doctor` | Check system health | `velo doctor` |
| `clean` | Clean packages or cache | `velo clean --packages` |
| `tap` | Manage package repositories | `velo tap list` |
| `install-self` | Install velo to ~/.velo/bin | `velo install-self` |
| `uninstall-self` | Remove velo and optionally all data | `velo uninstall-self` |

### Self-Management

Velo can manage its own installation and data:

**Installation Management:**
```bash
# Install velo to ~/.velo/bin and add to PATH
velo install-self

# Install as symlink for development (auto-updates when you rebuild)
velo install-self --symlink

# Uninstall velo binary only (keep packages)
velo uninstall-self --binary-only

# Uninstall everything (interactive confirmation)
velo uninstall-self
```

**Auto-Updates:**
```bash
# Check for updates without installing
velo update-self --check

# Update to latest stable release
velo update-self

# Update to latest pre-release (beta versions)
velo update-self --pre-release

# Force update even if on latest version
velo update-self --force

# Update without creating backup (faster but less safe)
velo update-self --skip-backup
```

**Data Management:**
```bash
# Clean all packages (like Homebrew reset)
velo clean --packages

# Clear download cache
velo clean --cache

# Clean everything (packages + cache)
velo clean --all
```

### Tap Management

Velo supports multiple package repositories (taps) for accessing different software collections:

**Managing Taps:**
```bash
# List all installed taps
velo tap list

# Add a custom tap (automatically updates velo.json in project context)
velo tap add user/homebrew-tools

# Add tap with full URL
velo tap add https://github.com/user/homebrew-tools.git

# Remove a tap (automatically updates velo.json in project context)
velo tap remove user/homebrew-tools

# Update all taps
velo tap update

# Update specific tap
velo tap update homebrew/core

# Force global tap operations (skip velo.json updates)
velo tap add user/tools --global
velo tap list --global
```

**Tap Priority:**
- `homebrew/core` - Highest priority (default packages)
- Other homebrew taps - Medium priority
- Third-party taps - Lower priority

When multiple taps contain the same package, Velo uses the highest priority version.

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
  "dependencies": {
    "imagemagick": "^7.1.0",
    "ffmpeg": "^7.0.0",
    "shellcheck": "^0.10.0"
  },
  "taps": [
    "wix/brew",
    "user/custom-tools"
  ]
}
```

The `taps` field ensures required repositories are automatically available when installing dependencies. This is particularly useful for CI/CD environments where taps aren't pre-configured.

### Lock File (velo.lock)

Velo automatically generates a `velo.lock` file to ensure reproducible builds:

```json
{
  "lockfileVersion": 1,
  "dependencies": {
    "wget": {
      "version": "1.25.0",
      "resolved": "https://ghcr.io/v2/homebrew/core/wget/blobs/sha256:abc123...",
      "sha256": "abc123...",
      "tap": "homebrew/core",
      "dependencies": {
        "openssl@3": "3.5.0"
      }
    }
  },
  "taps": {
    "homebrew/core": {
      "commit": "abc123def456"
    }
  }
}
```

**Lock File Features:**
- **Exact versions**: Locks down specific package versions
- **Integrity hashes**: SHA256 verification for security
- **Dependency resolution**: Tracks exact resolved dependency versions
- **Tap tracking**: Records source taps and commit hashes
- **Human readable**: JSON format for easy inspection

### Local Package Commands

```bash
# Initialize a new project
velo init

# Install packages locally
velo install imagemagick                 # Automatically adds to dependencies

# Install all dependencies from velo.json
velo install

# Install exactly from velo.lock (CI mode)
velo install --frozen

# Verify before installing
velo install --check

# Execute commands using local packages
velo exec convert image.jpg output.png   # Uses local imagemagick
velo exec shellcheck script.sh           # Uses local shellcheck

# Show which version will be used
velo which convert                        # Shows resolution order

# Verify installed packages match velo.lock
velo verify

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

Perfect for continuous integration with automatic tap resolution and caching:

```yaml
# GitHub Actions example
- name: Cache Velo packages
  uses: actions/cache@v3
  with:
    path: .velo
    key: ${{ runner.os }}-velo-${{ hashFiles('velo.lock') }}

- name: Install dependencies
  run: velo install  # Automatically adds required taps from velo.json
```

**Enhanced CI Reliability:**
- Required taps are automatically cloned from the `taps` field in velo.json
- No manual tap setup needed in CI environments
- Consistent package resolution across all environments
- Lock file verification ensures integrity: `velo verify`

### Benefits

- **Reproducible Builds**: `velo.lock` ensures exact versions and integrity
- **CI Caching**: Cache `.velo` directory based on lock file hash
- **Project Isolation**: No global pollution between projects
- **Familiar Workflow**: Similar to npm/yarn ecosystem
- **Security**: SHA256 verification of all downloaded packages
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
