---
title: Command Reference
description: Complete reference for all Velocity commands
order: 2
category: Reference
---

# Command Reference

Complete guide to all Velocity commands with examples and options.

## Package Management

### install

Install packages locally or globally.

```bash
# Install package 
# in velo.json exists in current folder, it will install into local .velo folder, just like npm
# if velo.json doesnt exist in current folder, will install into ~/.velo
# supports multiple packages
velo install imagemagick

# Install package globally (into ~/.velo) even if velo.json exists in current directory
velo install wget --global

# Install specific version
velo install wget@1.25.0

# Install all dependencies from velo.json
velo install

# Force reinstall even if already installed
velo install wget --force
```

**Options:**
- `--global` - Forces installation globally instead of locally
- `--version <version>` - Install specific version if available
- `--force` - Force reinstall even if already installed (useful for fixing broken packages)

### uninstall

Remove installed packages.

```bash
# Remove package (all versions)
# in velo.json exists in current folder, it will remove from local .velo folder, just like npm
# supports multiple packages
velo uninstall wget

# Remove specific version only
velo uninstall wget@1.21.3

# Remove from global installation (~/.velo)
velo uninstall wget --global
```

**Options:**
- `--global` - Remove from global installation
- `--version <version>` - Remove specific version only

### list

List installed packages and versions.

```bash
# List all installed packages
velo list

# Show all versions of each package
velo list --versions
```

### info

Show detailed information about packages.

```bash
# Show package information
velo info wget
```

### search

Search for packages in repositories.

```bash
# Search for packages containing "http"
velo search http

# Search in specific tap
velo search nginx --tap homebrew/nginx
```

**Options:**
- `--tap <tap>` - Search in specific repository only

## Project Management

### init

Initialize a new project with velo.json manifest.

```bash
# Create new project
velo init
```

### exec

Execute commands using local packages.

```bash
# Run command with local packages in PATH
velo exec convert image.jpg output.png

# Run complex commands
velo exec bash -c "convert *.jpg -resize 50% smaller/"

# Run interactive shell with local packages
velo exec bash
```

### which

Show which binary will be used for a command.

```bash
# Show resolution order
velo which convert

# Show all available versions
velo which --all convert 
```

**Options:**
- `--all` - Show all available versions

## Repository Management

### tap

Manage package repositories.

```bash
# List all taps
velo tap list

# List global taps only
velo tap list --global

# Add a new tap
velo tap add user/homebrew-tools

# Add tap with full URL
velo tap add https://github.com/user/homebrew-tools.git

# Remove a tap
velo tap remove user/homebrew-tools

# Force global tap operations (skip velo.json)
velo tap add user/tools --global
```

**Options:**
- `--global` - Operate on global taps only
- `list` - Show installed taps
- `add <tap>` - Add new tap
- `remove <tap>` - Remove tap  

### update

Update package repositories.

```bash
# Update all repositories
velo update

# Update specific tap only
velo update homebrew/core
```

**Options:**
- `--verbose` - Show detailed update information
- `<tap>` - Update specific tap only

## System Management

### doctor

Check system health and configuration.

```bash
# Run all health checks
velo doctor

# Fix found problems
velo doctor --fix
```

### repair

Repair existing package installations by fixing library path issues.

```bash
# Check all packages for repair issues (dry run)
velo repair --dry-run

# Repair all packages with issues
velo repair

# Repair specific package
velo repair ffmpeg

# Force repair even if no issues detected
velo repair --force
```

**Options:**
- `--dry-run` - Show what would be repaired without making changes
- `--force` - Force repair even if no issues are detected
- `<package>` - Repair specific package only

**When to use repair:**
- When packages fail with dyld symbol loading errors
- If binary or library dependencies are broken
- When `@@HOMEBREW_PREFIX@@` placeholders weren't replaced during installation

**Alternative to repair:**
For simpler cases, you can also use `velo install --force <package>` to completely reinstall a single broken package.

### clean

Clean packages, cache, or temporary files.

```bash
# Clean download cache
velo clean --cache

# Clean all packages (like Homebrew reset)
velo clean --packages

# Clean everything (packages + cache)
velo clean --all

# Clean specific package
velo clean wget

# Dry run (show what would be cleaned)
velo clean --cache --dry-run
```

**Options:**
- `--cache` - Clean download cache
- `--packages` - Remove all packages
- `--all` - Clean everything
- `<package>` - Clean specific package

## Self Management

### install-self

Install Velocity to system.

```bash
# Install velo to ~/.velo/bin and add to PATH
velo install-self

# Install as symlink for development
velo install-self --symlink

# Force reinstall even if already installed
velo install-self --force
```

**Options:**
- `--symlink` - Create symlink for development
- `--force` - Force reinstall

### uninstall-self

Remove Velocity from system.

```bash
# Uninstall velo binary only (keep packages)
velo uninstall-self --binary-only

# Uninstall everything (interactive confirmation)
velo uninstall-self

# Force uninstall without confirmation
velo uninstall-self --force
```

**Options:**
- `--binary-only` - Remove binary only, keep packages
- `--force` - Skip confirmation prompts  

### update-self

Update Velocity to latest version.

```bash
# Check for updates without installing
velo update-self --check

# Update to latest stable release
velo update-self

# Force update even if on latest version
velo update-self --force

# Update without creating backup
velo update-self --skip-backup
```

**Options:**
- `--check` - Check for updates only
- `--pre-release` - Include beta versions
- `--force` - Force update
- `--skip-backup` - Skip backup creation

## Multi-Version Support

Velocity supports installing and managing multiple versions of packages:

### Version-Specific Installation

```bash
# Install latest version
velo install wget

# Install specific version (when available)  
velo install wget --version 1.21.3

# List all available versions
velo info wget
```

### Binary Access

- **Default symlinks**: `~/.velo/bin/wget` (points to default version)
- **Versioned symlinks**: `~/.velo/bin/wget@1.21.3` (specific version access)
- **Library compatibility**: Each version maintains independent library paths

### Managing Multiple Versions

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

## Global Options

These options work with most commands:

- `--help, -h` - Show help information

## Examples

### Common Workflows

**Set up a new project:**
```bash
cd my-project
velo init
velo install imagemagick ffmpeg shellcheck
velo exec convert --version  # Uses local imagemagick
```

**Install development tools globally:**
```bash
velo install wget curl jq --global
velo install node@18 --global  # Specific version
```

**Update everything:**
```bash
velo update          # Update repositories
velo update-self     # Update Velocity itself
```

**Clean up system:**
```bash
velo clean --cache   # Free up disk space
velo doctor          # Check system health
```

**Fix broken packages:**
```bash
velo repair --dry-run   # Check what needs repair
velo repair             # Fix all issues
velo doctor             # Verify system health
```