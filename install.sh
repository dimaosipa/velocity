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

# Generate version information
echo "📋 Generating version information..."
if [[ -f "Scripts/generate-version.sh" ]]; then
    # Make sure the script is executable
    chmod +x Scripts/generate-version.sh
    
    # Run version generation
    if ! ./Scripts/generate-version.sh; then
        echo "⚠️  Warning: Version generation failed, using fallback version"
    fi
else
    echo "⚠️  Warning: Version generation script not found, using fallback version"
fi

# Build the project
echo "🔨 Building Velocity..."
swift build -c release

# Check if build succeeded
if [[ ! -f ".build/release/velo" ]]; then
    echo "❌ Error: Build failed - velo binary not found"
    exit 1
fi

# Display built version
echo "✅ Build successful!"
BUILT_VERSION=$(.build/release/velo --version 2>/dev/null || echo "unknown")
echo "📦 Built version: $BUILT_VERSION"

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