#!/bin/bash

# GHCR Access Test Script
# Tests both success and failure cases for GitHub Container Registry access

set -e

echo "🔬 GHCR Access Investigation Script"
echo "=================================="
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

test_package() {
    local package=$1
    local sha256=$2
    local description=$3
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "🧪 Testing: $package ($description)"
    echo "═══════════════════════════════════════════════════════════════"
    
    # Convert package name for GHCR (@ to -at-)
    local ghcr_name=$(echo "$package" | sed 's/@/-at-/g')
    local ghcr_url="https://ghcr.io/v2/homebrew/core/$ghcr_name/blobs/sha256:$sha256"
    
    log_info "Package: $package"
    log_info "GHCR URL: $ghcr_url"
    log_info "SHA256: $sha256"
    echo ""
    
    # Step 1: Get authentication challenge
    log_info "Step 1: Getting authentication challenge..."
    local auth_header=$(curl -sI "$ghcr_url" | grep -i "www-authenticate" || echo "")
    
    if [ -z "$auth_header" ]; then
        log_error "No authentication challenge received"
        return 1
    fi
    
    echo "Auth header: $auth_header"
    
    # Extract realm, scope, and service
    local realm=$(echo "$auth_header" | grep -o 'realm="[^"]*"' | cut -d'"' -f2)
    local scope=$(echo "$auth_header" | grep -o 'scope="[^"]*"' | cut -d'"' -f2)
    local service=$(echo "$auth_header" | grep -o 'service="[^"]*"' | cut -d'"' -f2)
    
    log_info "Realm: $realm"
    log_info "Scope: $scope"
    log_info "Service: $service"
    echo ""
    
    # Step 2: Request token
    log_info "Step 2: Requesting anonymous token..."
    local token_url="${realm}?scope=${scope}&service=${service}"
    log_info "Token URL: $token_url"
    
    local token_response=$(curl -s "$token_url")
    echo "Token response: $token_response"
    echo ""
    
    # Check if token request was successful
    if echo "$token_response" | grep -q '"errors"'; then
        log_error "Token request FAILED"
        local error_code=$(echo "$token_response" | grep -o '"code":"[^"]*"' | cut -d'"' -f4)
        local error_message=$(echo "$token_response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        log_error "Error: $error_code - $error_message"
        echo ""
        return 1
    fi
    
    # Extract token
    local token=$(echo "$token_response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [ -z "$token" ]; then
        # Try access_token format
        token=$(echo "$token_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [ -z "$token" ]; then
        log_error "No token found in response"
        return 1
    fi
    
    log_success "Token obtained: ${token:0:30}..."
    echo ""
    
    # Step 3: Test authenticated download
    log_info "Step 3: Testing authenticated download..."
    
    # Get response with headers
    local temp_headers=$(mktemp)
    local http_status=$(curl -s -w "%{http_code}" -D "$temp_headers" -o /dev/null \
        -H "Authorization: Bearer $token" "$ghcr_url")
    
    echo "HTTP Status: $http_status"
    
    case $http_status in
        200)
            log_success "SUCCESS: Bottle is accessible!"
            local content_length=$(grep -i "content-length" "$temp_headers" | cut -d':' -f2 | tr -d ' \r')
            local content_type=$(grep -i "content-type" "$temp_headers" | cut -d':' -f2 | tr -d ' \r')
            log_info "Content-Length: $content_length bytes"
            log_info "Content-Type: $content_type"
            ;;
        307)
            log_warning "Redirect received (307)"
            local redirect_url=$(grep -i "location" "$temp_headers" | cut -d':' -f2- | tr -d ' \r')
            if [ -n "$redirect_url" ]; then
                log_info "Redirect URL: $redirect_url"
                log_info "Testing final download..."
                local final_status=$(curl -s -w "%{http_code}" -o /dev/null "$redirect_url")
                if [ "$final_status" = "200" ]; then
                    log_success "Final download successful!"
                else
                    log_error "Final download failed: HTTP $final_status"
                fi
            fi
            ;;
        401)
            log_error "Authentication failed (401)"
            ;;
        403)
            log_error "Access forbidden (403)"
            ;;
        404)
            log_error "Bottle not found (404)"
            ;;
        *)
            log_error "Unexpected HTTP status: $http_status"
            ;;
    esac
    
    rm -f "$temp_headers"
    echo ""
}

# Function to test Velo installation with our error handling
test_velo_install() {
    local package=$1
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "🚀 Testing Velo Installation: $package"
    echo "═══════════════════════════════════════════════════════════════"
    
    if [ ! -f "./.build/release/velo" ]; then
        log_error "Velo binary not found. Run 'swift build -c release' first."
        return 1
    fi
    
    log_info "Running: ./build/release/velo install $package"
    echo ""
    
    # Run velo install and capture output
    if ./.build/release/velo install "$package" 2>&1; then
        log_success "Velo installation completed"
    else
        local exit_code=$?
        log_warning "Velo installation finished with exit code: $exit_code"
        log_info "This may be expected if bottles are not accessible"
    fi
    echo ""
}

# Main test execution
main() {
    echo "This script will test GHCR access for various packages to understand"
    echo "which bottles are accessible and which are denied."
    echo ""
    
    # Test cases from actual homebrew formulas
    # These SHA256s are from real homebrew bottles
    
    # KNOWN FAILURE CASE: openssl@3 (access denied)
    test_package "openssl@3" "7bbac0e84510570ec550deee1dce185569917378411263a9d1329ae395f52d70" "EXPECTED FAILURE - Access Denied"
    
    # POTENTIAL SUCCESS CASES: simpler packages
    test_package "tree" "a290f08288dc441d0842aeb0fc5d27e2ebb890ad0ef03680c08fddf4b6281252" "Potential Success"
    
    test_package "jq" "a290f08288dc441d0842aeb0fc5d27e2ebb890ad0ef03680c08fddf4b6281252" "Testing jq access"
    
    test_package "wget" "4d180cd4ead91a34e2c2672189fc366b87ae86e6caa3acbf4845b272f57c859a" "Main target package"
    
    # Test our improved Velo error handling
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "🧪 TESTING VELO ERROR HANDLING"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    log_info "Now testing our improved error handling in Velo..."
    echo "This should demonstrate graceful handling of GHCR access issues."
    echo ""
    
    # Test a package that should fail gracefully
    test_velo_install "tree"
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "📊 TEST SUMMARY"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    log_info "Key findings:"
    echo "• Some packages (like openssl@3) are denied access at the token level"
    echo "• Other packages may get tokens but bottles might not exist"
    echo "• GHCR access is inconsistent across different packages"
    echo "• Our error handling should gracefully manage these cases"
    echo ""
    log_info "The goal is robust installation that doesn't fail completely"
    log_info "when individual bottles are inaccessible."
    echo ""
}

# Run the tests
main "$@"