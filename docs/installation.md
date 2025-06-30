---
title: Installation Guide
description: How to install and set up Velocity package manager
order: 1
category: Getting Started
---

# Installation Guide

This guide covers installing Velocity on your macOS system and getting it set up for daily use.

## Requirements

- **Apple Silicon Mac** (M1, M2, M3, or later)
- **macOS 12+** (Monterey or later)

## Installation Methods

### Quick Install (Recommended)

Clone the repository and run the install script:

```bash
# Clone and install
git clone https://github.com/dimaosipa/velocity.git
cd velocity
./install.sh
```

**What this does:**
- Builds Velocity in release mode for optimal performance
- Installs `velo` binary to `~/.velo/bin/`
- Adds `~/.velo/bin` to your shell PATH automatically
- Cleans up build artifacts to save space
- Sets up basic directory structure

### Manual Installation

If you prefer more control over the installation process:

```bash
# Clone the repository
git clone https://github.com/dimaosipa/velocity.git
cd velocity

# Build in release mode
swift build -c release

# Install manually
mkdir -p ~/.velo/bin
cp .build/release/velo ~/.velo/bin/

# Add to PATH (choose your shell)
echo 'export PATH="$HOME/.velo/bin:$PATH"' >> ~/.zshrc  # For zsh
echo 'export PATH="$HOME/.velo/bin:$PATH"' >> ~/.bashrc # For bash
```

### Development Installation

For contributors who want to work on Velocity:

```bash
git clone https://github.com/dimaosipa/velocity.git
cd velocity

# Install as symlink for development
velo install-self --symlink

# This creates a symlink that auto-updates when you rebuild
```

## Shell Setup

### Adding to PATH

The install script should automatically add `~/.velo/bin` to your PATH. If it doesn't work, add it manually:

**For Zsh (default on macOS):**
```bash
echo 'export PATH="$HOME/.velo/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**For Bash:**
```bash
echo 'export PATH="$HOME/.velo/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Verify Installation

Test that Velocity is installed correctly:

```bash
# Check if velo is in PATH
which velo

# Verify system compatibility
velo doctor

# Show version information
velo --version
```

## Initial Setup

### First Steps

After installation, initialize Velocity:

```bash
# Check system health and compatibility
velo doctor

# Update package repositories
velo update

# Install your first package globally
velo install wget --global
```

### File Layout

Velocity creates this directory structure in your home folder:

```
~/.velo/
├── bin/          # Binary symlinks (add to PATH)
├── opt/          # Homebrew-compatible package symlinks
├── Cellar/       # Installed package files
├── cache/        # Download and formula cache
├── taps/         # Package repositories
├── logs/         # Operation logs
└── tmp/          # Temporary build files
```

## Self-Management

Velocity can manage its own installation:

### Install Commands

```bash
# Install velo to ~/.velo/bin and add to PATH
velo install-self

# Install as symlink for development
velo install-self --symlink

# Uninstall velo binary only (keep packages)
velo uninstall-self --binary-only

# Uninstall everything (interactive confirmation)
velo uninstall-self
```

### Auto-Updates

Keep Velocity up to date:

```bash
# Check for updates
velo update-self --check

# Update to latest stable release
velo update-self

# Update to pre-release version
velo update-self --pre-release

# Force update even if on latest version
velo update-self --force
```

## Troubleshooting

### Common Issues

**"velo: command not found"**
- Ensure `~/.velo/bin` is in your PATH
- Restart your terminal or run `source ~/.zshrc`

**Permission denied errors**
- Velocity should never require `sudo`
- Check that `~/.velo` directory has correct permissions

**Installation fails on older macOS**
- Velocity requires macOS 12+ (Monterey)
- Apple Silicon Macs only (Intel not supported)

### Getting Help

```bash
# Check system health
velo doctor

# View recent logs
ls ~/.velo/logs/

# Get help for any command
velo --help
velo install --help
```

### Clean Installation

If you need to start fresh:

```bash
# Remove all packages and cache
velo clean --all

# Or completely uninstall
velo uninstall-self
rm -rf ~/.velo  # Removes all Velocity data
```