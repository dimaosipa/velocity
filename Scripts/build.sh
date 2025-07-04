#!/bin/bash

# Velo Build Script
# Generates version information and builds with optional release mode

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Show usage information
show_usage() {
    echo "Usage: $0 [--release] [swift build options...]"
    echo ""
    echo "Options:"
    echo "  --release    Build in release mode (optimized)"
    echo "  --help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Debug build"
    echo "  $0 --release          # Release build"
    echo "  $0 --verbose          # Debug build with verbose output"
    echo "  $0 --release --verbose # Release build with verbose output"
}

# Parse arguments
RELEASE_MODE=false
BUILD_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            RELEASE_MODE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            BUILD_ARGS+=("$1")
            shift
            ;;
    esac
done

# Detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Determine build configuration
if [[ "$RELEASE_MODE" == "true" ]]; then
    BUILD_CONFIG="release"
    # Prepend --configuration release to existing args
    if [[ ${#BUILD_ARGS[@]} -eq 0 ]]; then
        BUILD_ARGS=("--configuration" "release")
    else
        BUILD_ARGS=("--configuration" "release" "${BUILD_ARGS[@]}")
    fi
    log_info "Building Velo for release..."
else
    BUILD_CONFIG="debug"
    log_info "Building Velo for development..."
fi

# Change to project root
cd "$PROJECT_ROOT"

# Step 1: Generate version information
log_info "Step 1: Generating version information..."
if ! "$SCRIPT_DIR/generate-version.sh"; then
    log_error "Version generation failed"
    exit 1
fi

# Step 2: Build the project
log_info "Step 2: Building project..."
if [[ ${#BUILD_ARGS[@]} -eq 0 ]]; then
    if ! swift build; then
        log_error "Build failed"
        exit 1
    fi
else
    if ! swift build "${BUILD_ARGS[@]}"; then
        log_error "Build failed"
        exit 1
    fi
fi

log_info "Build completed successfully!"

# Show current version and build info
BINARY_PATH=".build/$BUILD_CONFIG/velo"
VERSION=$($BINARY_PATH --version 2>/dev/null || echo "Unable to get version")
log_info "Built version: $VERSION"

# Show binary size for release builds
if [[ "$RELEASE_MODE" == "true" && -f "$BINARY_PATH" ]]; then
    SIZE=$(du -h "$BINARY_PATH" | cut -f1)
    log_info "Binary size: $SIZE"
fi