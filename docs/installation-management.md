
# Installation Management

Velo can manage its own installation and data.

## Installation Management
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

## Auto-Updates
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

## Data Management
```bash
# Clean all packages (like Homebrew reset)
velo clean --packages

# Clear download cache
velo clean --cache

# Clean everything (packages + cache)
velo clean --all
```
