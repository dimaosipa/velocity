# Velocity 🚀

A lightning-fast, modern package manager for macOS — built for Apple Silicon.

Velocity treats Homebrew formulas as declarative files, installs only from pre-built bottles (never compiles from source), and runs entirely in user space — no `PATH` pollution, no system writes, and no risk.

## ✨ Key Features

- **🏎️ Performance-Focused**  
  Parallel downloads with smart caching
- **🔋 Apple Silicon Native**  
  Written in Swift, built exclusively for Apple Silicon
- **🛡️ User-Space Only**  
  No `sudo`, no system-level changes — everything stays in `~/.velo/`
- **🤖 CI-Ready**  
  Project-specific tool versions via `velo.json` — like npm, but for system packages
- **🔄 Drop-in Compatible**  
  Supports existing Homebrew `.rb` formulae
- **💼 Project-Local Packages**  
  Keep dependencies isolated per project with `velo.json`
- **🧠 Safe for Automation & AI Agents**  
  No scripts, no side effects, no surprises — safe to run in CI, containers, and autonomous workflows


## 🤔 Why Not Just Use Homebrew?

Homebrew formulas are **executable Ruby scripts** — not just static package definitions. Installing a package with Homebrew means running third-party code with full system access. This allows:

- Arbitrary shell commands during install/upgrade
- Silent modifications outside the install directory
- Potential use of `sudo`
- Unexpected compilation from source

**Velocity flips this model.**  
It treats formulas as **declarative**, like JSON or YAML — not scripts. Packages are installed only from trusted prebuilt binaries (bottles), with no custom install logic.

- No shell execution  
- No filesystem writes outside `~/.velo/`  
- No elevated permissions  
- Fully predictable installs

This makes Velocity uniquely suited for **automation**, **CI environments**, and even **AI agents** — where **determinism, safety, and reproducibility** are critical.

> 🔒 Safe-by-default: Unlike Homebrew, Velocity can be run by autonomous tools without risk of arbitrary code execution.


## 🚀 Quick Start

### Requirements

- **Apple Silicon Mac**
- **macOS 12+** (Monterey or later)

### Installation

Directly:

```bash
# Clone and install
git clone https://github.com/dimaosipa/velocity.git
cd velocity
./install.sh
```

This builds Velocity, installs `velo` to `~/.velo/bin/`, and adds it to your PATH.

Via homebrew:
```
# Install via Homebrew tap
brew tap dimaosipa/brew
brew install dimaosipa/brew/velo
```

### First Steps

**Global Package Management:**
```bash
# Check system compatibility
velo doctor

# Install packages globally
velo install wget

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

---

> ⚠️ **Experimental Software**  
> Velocity is in early development:
> - Many popular formulas (e.g., `imagemagick`, `wget`, `ffmpeg`) work well  
> - Some do not, or haven't been tested  
> - Velocity treats formulas as declarations, not scripts — so install-time scripts in Homebrew formulas won’t run

---

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](docs/contributing.md) for:

- Bug reports and feature requests
- Code contributions
- Development setup
- Testing guidelines

## 📄 License

BSD-2-Clause License - see [LICENSE](LICENSE) for details.

## ⚡ Why Velo?

**Velo** means "speed" in multiple languages, reflecting our core mission: making package management on macOS as fast as possible while maintaining compatibility with the Homebrew ecosystem.

Built by developers who were tired of waiting for package operations, Velo leverages Apple Silicon's performance to deliver a package manager that feels instant.

---

**Get Started:** [Installation Guide](docs/installation.md) | **Questions?** [GitHub Discussions](https://github.com/dimaosipa/velocity/discussions)
