---
title: Local Package Management
description: Project-local packages with velo.json manifests and CI/CD integration
order: 3
category: Usage
---

# Local Package Management

Velocity supports project-local package management similar to npm's node_modules, enabling reproducible builds and CI caching.

## Overview

Local package management allows each project to have its own isolated set of packages, preventing version conflicts and ensuring reproducible builds across different environments.

## Project Structure

When you initialize a project with `velo init`, Velocity creates this structure:

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

## Package Manifest (velo.json)

The `velo.json` file defines your project's dependencies and configuration:

```json
{
  "name": "my-project",
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

### Fields

- **name** (optional) - Project name for identification
- **dependencies** - Packages required by this project
- **taps** - Additional repositories needed for dependencies

### Version Specifications

Velocity supports semantic versioning patterns:

- `"^7.1.0"` - Compatible with 7.1.0, allows 7.1.x and 7.x.x
- `"~7.1.0"` - Compatible with 7.1.0, allows 7.1.x only
- `"7.1.0"` - Exact version 7.1.0
- `">=7.1.0"` - Version 7.1.0 or higher
- `"latest"` - Always use the latest available version

## Lock File (velo.lock)

Velocity automatically generates a `velo.lock` file to ensure reproducible builds:

```json
{
  "lockfileVersion": 1,
  "dependencies": {
    "imagemagick": {
      "version": "7.1.1-40",
      "resolved": "https://ghcr.io/v2/homebrew/core/imagemagick/blobs/sha256:abc123...",
      "sha256": "abc123def456...",
      "tap": "homebrew/core",
      "dependencies": {
        "libpng": "1.6.40",
        "jpeg-turbo": "3.0.1"
      }
    },
    "ffmpeg": {
      "version": "7.1.0",
      "resolved": "https://ghcr.io/v2/homebrew/core/ffmpeg/blobs/sha256:def456...",
      "sha256": "def456ghi789...",
      "tap": "homebrew/core",
      "dependencies": {
        "x264": "r3095",
        "x265": "3.5"
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

### Lock File Features

- **Exact versions** - Locks down specific package versions
- **Integrity hashes** - SHA256 verification for security
- **Dependency resolution** - Tracks exact resolved dependency versions
- **Tap tracking** - Records source taps and commit hashes
- **Human readable** - JSON format for easy inspection

## Working with Local Packages

### Initialize a Project

```bash
# Create velo.json in current directory
velo init

# Initialize with project name
velo init --name "my-project"

# Initialize with dependencies
velo init --with imagemagick,ffmpeg
```

### Install Dependencies

```bash
# Install packages locally (adds to velo.json)
velo install imagemagick ffmpeg

# Install all dependencies from velo.json
velo install

# Install exactly from velo.lock (CI mode)
velo install --frozen

# Verify packages before installing
velo install --check
```

### Use Local Packages

```bash
# Execute commands using local packages
velo exec convert image.jpg output.png   # Uses local imagemagick
velo exec ffmpeg -i video.mp4 output.gif # Uses local ffmpeg

# Run interactive shell with local packages
velo exec bash

# Show which version will be used
velo which convert                        # Shows resolution order
```

## Version Resolution Priority

When running commands, Velocity resolves binaries in this order:

1. **Local packages** - `./.velo/bin/` (project-specific)
2. **Parent directories** - `../.velo/bin/` (if enabled)
3. **Global packages** - `~/.velo/bin/` (user-wide)
4. **System commands** - `/usr/local/bin`, `/usr/bin` (fallback)

This ensures project-specific packages always take precedence over global ones.

## Tap Management

### Adding Taps to Projects

```bash
# Add tap to current project (updates velo.json)
velo tap add user/homebrew-tools

# Add tap globally (doesn't update velo.json)
velo tap add user/homebrew-tools --global
```

### Automatic Tap Resolution

The `taps` field in `velo.json` ensures required repositories are automatically available:

```json
{
  "dependencies": {
    "custom-tool": "^1.0.0"
  },
  "taps": [
    "user/homebrew-tools"
  ]
}
```

When someone runs `velo install`, Velocity automatically:
1. Clones the required taps
2. Installs dependencies from those taps
3. Updates the lock file with tap commit hashes

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build
on: [push, pull_request]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Cache Velo packages
        uses: actions/cache@v3
        with:
          path: .velo
          key: ${{ runner.os }}-velo-${{ hashFiles('velo.lock') }}
          restore-keys: |
            ${{ runner.os }}-velo-
      
      - name: Install Velocity
        run: |
          git clone https://github.com/dimaosipa/velocity.git
          cd velocity && ./install.sh
      
      - name: Install dependencies
        run: velo install --frozen  # Uses exact versions from lock file
      
      - name: Run tests
        run: velo exec bash -c "your-test-command"
```

### Enhanced CI Reliability

- **Required taps** are automatically cloned from the `taps` field in velo.json
- **No manual tap setup** needed in CI environments
- **Consistent package resolution** across all environments
- **Lock file verification** ensures integrity: `velo verify`

## Advanced Features

### Verification

```bash
# Verify installed packages match velo.lock
velo verify

# Show detailed differences
velo verify --verbose

# Verify specific package
velo verify imagemagick
```

### Cleaning

```bash
# Clean local packages only
velo clean --packages

# Clean local cache
velo clean --cache

# Clean everything locally
velo clean --all
```

### Global vs Local Commands

```bash
# Install locally (default in project directory)
velo install wget

# Install globally (accessible everywhere)
velo install wget --global

# List local packages
velo list --local

# List global packages
velo list --global
```

## Best Practices

### Version Management

- **Use semantic versioning** patterns in velo.json (`^7.1.0`)
- **Commit velo.lock** to version control for reproducible builds
- **Don't commit .velo/** directory (add to .gitignore)
- **Use `--frozen` flag** in CI to install exact versions

### Project Setup

```bash
# Add .velo to .gitignore
echo ".velo/" >> .gitignore

# Initialize project with common tools
velo init --with imagemagick,ffmpeg,shellcheck
```

### Performance Optimization

- **Cache .velo directory** in CI using lock file hash
- **Use local packages** for project-specific tools
- **Install build tools globally** for general use
- **Clean cache periodically** to save disk space

## Benefits

- **Reproducible Builds** - `velo.lock` ensures exact versions and integrity
- **CI Caching** - Cache `.velo` directory based on lock file hash
- **Project Isolation** - No global pollution between projects
- **Familiar Workflow** - Similar to npm/yarn ecosystem
- **Security** - SHA256 verification of all downloaded packages
- **Version Conflicts** - Different projects can use different tool versions

## Migration from Global Packages

If you have global packages and want to use local management:

```bash
# Initialize project
velo init

# Add currently installed global packages
velo install imagemagick ffmpeg --local

# Verify everything works
velo exec convert --version
velo exec ffmpeg -version
```

This creates a local installation with the same packages, isolating your project from global changes.