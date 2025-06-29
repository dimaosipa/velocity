#!/bin/bash

# GHCR URL Pattern Investigation Script
# Tests multiple URL patterns for @-versioned packages to find the correct format

set -e

echo "🔬 GHCR URL Pattern Investigation"
echo "================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Extract version from formula URL
extract_version_from_url() {
    local formula_file=$1
    local url=$(grep "url.*tar.gz" "$formula_file" | head -1)
    echo "$url" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+[a-z]*' | head -1
}

# Test a specific GHCR URL pattern
test_ghcr_pattern() {
    local package_name=$1
    local pattern_url=$2
    local description=$3
    local sha256=$4
    
    echo "──────────────────────────────────────────────────────────────"
    log_info "Testing: $description"
    log_info "URL: $pattern_url"
    
    # Step 1: Get authentication challenge
    local auth_header=$(curl -sI "$pattern_url" | grep -i "www-authenticate" || echo "")
    
    if [ -z "$auth_header" ]; then
        log_error "No authentication challenge - URL might be invalid"
        return 1
    fi
    
    # Extract token details
    local realm=$(echo "$auth_header" | grep -o 'realm="[^"]*"' | cut -d'"' -f2)
    local scope=$(echo "$auth_header" | grep -o 'scope="[^"]*"' | cut -d'"' -f2)
    local service=$(echo "$auth_header" | grep -o 'service="[^"]*"' | cut -d'"' -f2)
    
    log_info "Scope: $scope"
    
    # Step 2: Request token
    local token_url="${realm}?scope=${scope}&service=${service}"
    local token_response=$(curl -s "$token_url")
    
    # Check for errors
    if echo "$token_response" | grep -q '"errors"'; then
        local error_code=$(echo "$token_response" | grep -o '"code":"[^"]*"' | cut -d'"' -f4)
        local error_message=$(echo "$token_response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        log_error "Token request failed: $error_code - $error_message"
        return 1
    fi
    
    # Extract token
    local token=$(echo "$token_response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$token" ]; then
        token=$(echo "$token_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [ -z "$token" ]; then
        log_error "No token found in response"
        return 1
    fi
    
    log_success "Token obtained: ${token:0:30}..."
    
    # Step 3: Test download
    local http_status=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "Authorization: Bearer $token" "$pattern_url")
    
    case $http_status in
        200)
            log_success "SUCCESS: Bottle is accessible!"
            return 0
            ;;
        307)
            log_warning "Redirect (307) - might still work"
            return 0
            ;;
        404)
            log_error "Not found (404)"
            return 1
            ;;
        *)
            log_error "HTTP $http_status"
            return 1
            ;;
    esac
}

# Main testing function
test_openssl_patterns() {
    local package_name="openssl@3"
    local base_name="openssl"
    local version_slot="3"
    local actual_version="3.5.0"  # From formula analysis
    local sha256="3bb3709fe0c67077cb54af5436442e81288804647ba513b34413c5163b43f9b8"
    
    echo "🧪 Testing GHCR URL patterns for $package_name"
    echo "Version slot: @$version_slot"
    echo "Actual version: $actual_version"
    echo "Bottle SHA256: $sha256"
    echo ""
    
    # Array of patterns to test
    local patterns=(
        # Current Velo approach
        "https://ghcr.io/v2/homebrew/core/openssl-at-3/blobs/sha256:$sha256|Current (-at- conversion)"
        
        # Hierarchical by version
        "https://ghcr.io/v2/homebrew/core/openssl/$actual_version/blobs/sha256:$sha256|Hierarchical by version"
        "https://ghcr.io/v2/homebrew/core/openssl/$version_slot/blobs/sha256:$sha256|Hierarchical by slot"
        
        # Tagged approaches
        "https://ghcr.io/v2/homebrew/core/openssl:$actual_version/blobs/sha256:$sha256|Tagged by version"
        "https://ghcr.io/v2/homebrew/core/openssl:$version_slot/blobs/sha256:$sha256|Tagged by slot"
        
        # Alternative separators
        "https://ghcr.io/v2/homebrew/core/openssl_$version_slot/blobs/sha256:$sha256|Underscore separator"
        "https://ghcr.io/v2/homebrew/core/openssl.$version_slot/blobs/sha256:$sha256|Dot separator"
        "https://ghcr.io/v2/homebrew/core/openssl-$version_slot/blobs/sha256:$sha256|Dash separator"
        "https://ghcr.io/v2/homebrew/core/openssl-$actual_version/blobs/sha256:$sha256|Dash with version"
        
        # URL encoding
        "https://ghcr.io/v2/homebrew/core/openssl%403/blobs/sha256:$sha256|URL encoded @"
        
        # Keep original @
        "https://ghcr.io/v2/homebrew/core/openssl@3/blobs/sha256:$sha256|Original @ symbol"
    )
    
    local successful_patterns=()
    
    for pattern_entry in "${patterns[@]}"; do
        local pattern_url=$(echo "$pattern_entry" | cut -d'|' -f1)
        local description=$(echo "$pattern_entry" | cut -d'|' -f2)
        
        if test_ghcr_pattern "$package_name" "$pattern_url" "$description" "$sha256"; then
            successful_patterns+=("$description: $pattern_url")
        fi
        echo ""
    done
    
    # Summary
    echo "══════════════════════════════════════════════════════════════"
    echo "📊 SUMMARY"
    echo "══════════════════════════════════════════════════════════════"
    
    if [ ${#successful_patterns[@]} -eq 0 ]; then
        log_error "No successful patterns found!"
        log_info "This suggests either:"
        log_info "• openssl@3 bottles are genuinely access-restricted"
        log_info "• GHCR uses a different organization scheme"
        log_info "• The bottle SHA256 or version is incorrect"
    else
        log_success "Found ${#successful_patterns[@]} working pattern(s):"
        for pattern in "${successful_patterns[@]}"; do
            echo "  ✅ $pattern"
        done
    fi
    
    echo ""
}

# Test with a working package for comparison
test_working_package() {
    echo "🔬 Testing with a known working package (tree) for comparison"
    echo "════════════════════════════════════════════════════════════"
    
    local sha256="a290f08288dc441d0842aeb0fc5d27e2ebb890ad0ef03680c08fddf4b6281252"
    local url="https://ghcr.io/v2/homebrew/core/tree/blobs/sha256:$sha256"
    
    if test_ghcr_pattern "tree" "$url" "Standard package (tree)" "$sha256"; then
        log_success "tree package access works - confirms GHCR connectivity"
    else
        log_warning "tree package also fails - might be broader GHCR issue"
    fi
    echo ""
}

# Main execution
main() {
    echo "This script systematically tests different GHCR URL patterns"
    echo "to discover the correct format for @-versioned packages."
    echo ""
    
    # Test working package first
    test_working_package
    
    # Test openssl@3 patterns
    test_openssl_patterns
    
    echo "🔍 Investigation complete!"
    echo ""
    echo "Next steps based on findings:"
    echo "• If patterns found: Update Formula.swift bottleURL() method"
    echo "• If none found: Investigate alternative bottle sources"
    echo "• If tree also fails: Check GHCR connectivity/auth issues"
}

# Run the investigation
main "$@"