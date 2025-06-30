# File Layout

```
~/.velo/
├── bin/          # Symlinks to binaries (add to PATH)
├── opt/          # Homebrew-compatible package symlinks
│   ├── wget -> Cellar/wget/1.25.0
│   └── openssl@3 -> Cellar/openssl@3/3.5.0
├── Cellar/       # Installed packages
│   ├── wget/1.25.0/
│   └── openssl@3/3.5.0/
├── cache/        # Formula and download cache
├── taps/         # Formula repositories (git-based)
│   └── homebrew/core/
├── logs/         # Operation logs
└── tmp/          # Temporary files
```
