#!/bin/bash

# Velo Build Script
# Generates version information before building

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

# Detect script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

log_info "Building Velo with version generation..."

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
if ! swift build "$@"; then
    log_error "Build failed"
    exit 1
fi

log_info "Build completed successfully!"

# Show current version
VERSION=$(.build/debug/velo --version 2>/dev/null || echo "Unable to get version")
log_info "Built version: $VERSION"