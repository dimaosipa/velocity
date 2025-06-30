---
title: Installation Guide
description: Complete installation guide for Velocity package manager
category: Getting Started
order: 1
---

# Installation Guide

## Requirements

- **Apple Silicon Mac** (M1, M2, or M3)
- **macOS 12+** (Monterey or later)

## Quick Install

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

## Manual Installation

If you prefer to install manually:

```bash
# Build from source
swift build -c release

# Copy binary
mkdir -p ~/.velo/bin
cp .build/release/velo ~/.velo/bin/

# Add to PATH
echo 'export PATH="$HOME/.velo/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Verify Installation

```bash
# Check installation
velo doctor

# Verify version
velo --version
```

## Self-Management

Velo can manage its own installation:

### Installation Management
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

### Auto-Updates
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

## Troubleshooting

If you encounter issues:

1. **Permission Denied**: Ensure you're not using `sudo`
2. **Command Not Found**: Check if `~/.velo/bin` is in your PATH
3. **Build Failures**: Make sure you have Xcode Command Line Tools installed

For more help, run `velo doctor` or check our [GitHub Issues](https://github.com/dimaosipa/velocity/issues).