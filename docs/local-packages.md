---
title: Local Package Management
description: Project-local dependency management with velo.json
category: Core Concepts
order: 3
---

# Local Package Management

Velo supports project-local package management similar to npm's node_modules, enabling reproducible builds and CI caching.

## Project Structure

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

## Lock File (velo.lock)

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

## Local Package Commands

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

## Version Resolution Priority

When running commands, Velo resolves binaries in this order:

1. **Local packages**: `./.velo/bin/` (project-specific)
2. **Parent directories**: `../.velo/bin/` (if enabled)
3. **Global packages**: `~/.velo/bin/` (user-wide)
4. **System commands**: `/usr/local/bin`, `/usr/bin` (fallback)

## CI/CD Integration

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

## Benefits

- **Reproducible Builds**: `velo.lock` ensures exact versions and integrity
- **CI Caching**: Cache `.velo` directory based on lock file hash
- **Project Isolation**: No global pollution between projects
- **Familiar Workflow**: Similar to npm/yarn ecosystem
- **Security**: SHA256 verification of all downloaded packages
- **Version Conflicts**: Different projects can use different tool versions