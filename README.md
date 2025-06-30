# Velocity 🚀

A lightning-fast, modern package manager for macOS - built for Apple Silicon.

**⚠️ Experimental Software**: Velo is in active development and is not recommended for production use. Please test thoroughly and provide feedback!

## ✨ Key Features

- **🏎️ Performance Focused**: Parallel downloads and smart caching
- **🔋 Apple Silicon Native**: Built exclusively for M1/M2/M3 Macs  
- **🛡️ User-Space Only**: Never requires `sudo` - everything in `~/.velo/`
- **🔄 Drop-in Compatible**: Uses existing `.rb` formulae from Homebrew
- **💼 Project-local packages**: Like npm for system packages with `velo.json`

## 🚀 Quick Start

### Requirements

- **Apple Silicon Mac** (M1, M2, M3, or later)
- **macOS 12+** (Monterey or later)

### Installation

```bash
# Clone and install
git clone https://github.com/dimaosipa/velocity.git
cd velocity
./install.sh
```

This builds Velocity, installs `velo` to `~/.velo/bin/`, and adds it to your PATH.

### First Steps

**Global Package Management:**
```bash
# Check system compatibility
velo doctor

# Install packages globally
velo install wget --global

# Verify installation
velo which wget
```

**Project-local Package Management:**
```bash
# Initialize a project
velo init

# Install packages locally for this project
velo install imagemagick ffmpeg

# Use local packages
velo exec convert image.jpg output.png
velo exec ffmpeg -i video.mp4 output.gif
```

## 📚 Documentation

For complete documentation, visit our website or see the docs folder:

🌐 **[Full Documentation Website](https://dimaosipa.github.io/velocity)**

📖 **Quick Reference:**
- [Installation Guide](docs/installation.md) - Detailed setup instructions
- [Command Reference](docs/commands.md) - Complete command documentation  
- [Local Package Management](docs/local-packages.md) - Project-specific packages
- [Architecture Overview](docs/architecture.md) - Technical details
- [Development Guide](docs/development.md) - Building and testing
- [Contributing Guide](docs/contributing.md) - How to contribute

## 🏗️ File Layout

```
~/.velo/
├── bin/          # Binary symlinks (add to PATH)
├── opt/          # Homebrew-compatible package symlinks  
├── Cellar/       # Installed packages
├── cache/        # Download and formula cache
└── taps/         # Package repositories
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](docs/contributing.md) for:

- Bug reports and feature requests
- Code contributions
- Development setup
- Testing guidelines

## 📄 License

BSD-2-Clause License - see [LICENSE](LICENSE) for details.

## ⚡ Why Velo?

**Velo** means "speed" in multiple languages, reflecting our core mission: making package management on macOS as fast as possible while maintaining full compatibility with the Homebrew ecosystem.

Built by developers who were tired of waiting for package operations, Velo leverages Apple Silicon's performance to deliver a package manager that feels instant.

---

**Get Started:** [Installation Guide](docs/installation.md) | **Questions?** [GitHub Discussions](https://github.com/dimaosipa/velocity/discussions)