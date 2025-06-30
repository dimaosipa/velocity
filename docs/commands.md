---
title: Command Reference
description: Complete reference for all Velocity commands
category: Getting Started
order: 2
---

# Command Reference

Complete reference for all Velo commands.

## Core Commands

| Command | Description | Example |
|---------|-------------|---------|
| `init` | Initialize project with velo.json | `velo init` |
| `install` | Install a package | `velo install wget` |
| `uninstall` | Remove a package | `velo uninstall wget` |
| `list` | List installed packages | `velo list --versions` |
| `info` | Show package details | `velo info wget` |
| `search` | Search for packages | `velo search http` |

## Package Management

### Installing Packages

```bash
# Install latest version
velo install wget

# Install specific version (when available)
velo install wget --version 1.21.3

# Install globally (traditional mode)
velo install wget --global

# Install locally for current project
velo install imagemagick
```

### Managing Versions

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

## Execution Commands

| Command | Description | Example |
|---------|-------------|---------|
| `exec` | Execute command with local packages | `velo exec convert image.jpg` |
| `which` | Show which binary will be used | `velo which convert` |

## Repository Management

| Command | Description | Example |
|---------|-------------|---------|
| `tap` | Manage package repositories | `velo tap list` |
| `update` | Update repositories | `velo update` |

### Tap Commands

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

## System Commands

| Command | Description | Example |
|---------|-------------|---------|
| `doctor` | Check system health | `velo doctor` |
| `clean` | Clean packages or cache | `velo clean --packages` |
| `verify` | Check if installed packages match velo.lock | `velo verify` |

### Cleaning

```bash
# Clean all packages (like Homebrew reset)
velo clean --packages

# Clear download cache
velo clean --cache

# Clean everything (packages + cache)
velo clean --all
```

## Self-Management

| Command | Description | Example |
|---------|-------------|---------|
| `update-self` | Update velo to latest version | `velo update-self` |
| `install-self` | Install velo to ~/.velo/bin | `velo install-self` |
| `uninstall-self` | Remove velo and optionally all data | `velo uninstall-self` |

## Global Flags

| Flag | Description |
|------|-------------|
| `-v, --verbose` | Enable verbose output |
| `--no-color` | Disable colored output |
| `--quiet` | Enable quiet mode (minimal output) |

## Exit Codes

- `0` - Success
- `1` - General error
- `2` - Invalid usage
- `3` - Package not found
- `4` - Network error
- `5` - Permission error