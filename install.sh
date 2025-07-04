#!/bin/bash
set -euo pipefail

echo "🚀 Installing Velocity (velo)..."
echo ""

# Check if we're on Apple Silicon
if [[ "$(uname -m)" != "arm64" ]]; then
    echo "❌ Error: Velocity requires Apple Silicon (arm64) architecture"
    echo "   Current architecture: $(uname -m)"
    exit 1
fi

# Check if Swift is available
if ! command -v swift &> /dev/null; then
    echo "❌ Error: Swift is required but not found"
    echo "   Please install Xcode or Swift toolchain"
    exit 1
fi

# Check if build script exists
if [[ ! -f "Scripts/build.sh" ]]; then
    echo "❌ Error: Build script not found (Scripts/build.sh)"
    echo "   Please ensure you're in the Velo project directory"
    exit 1
fi

# Build the project using our build script
echo "🔨 Building Velocity for release..."
if ! ./Scripts/build.sh --release; then
    echo "❌ Error: Build failed"
    exit 1
fi

# Run install-self to complete installation
echo "📦 Installing to ~/.velo/bin..."
.build/release/velo install-self

# Clean up build artifacts
echo "🧹 Cleaning up build artifacts..."
rm -rf .build

echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. Check installation: velo doctor"
echo "  3. Install your first package: velo install wget"