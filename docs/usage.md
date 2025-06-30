# Usage

## Multi-Version Package Support

Velo supports installing and managing multiple versions of the same package simultaneously.

### Installing Specific Versions

```bash
# Install latest version
velo install wget

# Install specific version (when available)
velo install wget --version 1.21.3
```

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

### Binary Access

- **Default symlinks**: `~/.velo/bin/wget` (points to default version)
- **Versioned symlinks**: `~/.velo/bin/wget@1.21.3` (specific version access)
- **Library compatibility**: Each version maintains independent library paths
