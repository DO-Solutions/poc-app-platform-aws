#!/bin/bash

# CloudFront Cache Testing Script
# Tests cache behavior and TTL settings for different content types

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    color=$1
    message=$2
    echo -e "${color}${message}${NC}"
}

# Function to show usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --domain DOMAIN  Custom domain to test (default: from terraform output)"
    echo "  -p, --path PATH      Specific path to test (default: tests multiple paths)"
    echo "  -v, --verbose        Show verbose curl output"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Test default paths"
    echo "  $0 -d example.com                     # Test specific domain"
    echo "  $0 -p /styles.css                     # Test specific path"
    echo "  $0 -v                                 # Show verbose output"
    exit 0
}

# Function to get domain from Terraform or use default
get_domain() {
    if [ -n "$CUSTOM_DOMAIN" ]; then
        echo "$CUSTOM_DOMAIN"
        return
    fi

    # Try to get from Terraform output
    if command -v terraform &> /dev/null; then
        DOMAIN=$(terraform -chdir=terraform output -raw custom_domain_url 2>/dev/null | sed 's|https://||' || true)
    fi

    # Default fallback
    if [ -z "$DOMAIN" ]; then
        DOMAIN="poc-app-platform-aws.digitalocean.solutions"
    fi

    echo "$DOMAIN"
}

# Function to test cache headers for a URL
test_cache_headers() {
    local url="$1"
    local description="$2"

    print_color "$BLUE" "=== Testing: $description ==="
    echo "URL: $url"
    echo ""

    if [ "$VERBOSE" = true ]; then
        # Show full curl output
        curl -I "$url" 2>/dev/null
    else
        # Show only cache-related headers
        local headers=$(curl -s -I "$url" 2>/dev/null | grep -iE "(cache-control|expires|etag|last-modified|age|x-cache|x-amz-)" || true)

        if [ -n "$headers" ]; then
            echo "$headers"
        else
            print_color "$YELLOW" "No cache headers found"
        fi
    fi

    echo ""

    # Make a second request to check if it's cached
    print_color "$YELLOW" "Second request (should show cache hit):"
    local cache_status=$(curl -s -I "$url" 2>/dev/null | grep -i "x-cache" || echo "X-Cache: Not shown")
    echo "$cache_status"
    echo ""
}

# Function to test cache behavior over time
test_cache_ttl() {
    local url="$1"
    local description="$2"

    print_color "$BLUE" "=== Testing Cache TTL: $description ==="
    echo "URL: $url"
    echo "Making multiple requests to observe Age header progression..."
    echo ""

    for i in {1..5}; do
        local age=$(curl -s -I "$url" 2>/dev/null | grep -i "age:" | awk '{print $2}' | tr -d '\r' || echo "0")
        local cache=$(curl -s -I "$url" 2>/dev/null | grep -i "x-cache:" | awk '{$1=""; print $0}' | sed 's/^ *//' | tr -d '\r' || echo "Unknown")

        echo "Request $i: Age=${age}s, Cache-Status=${cache}"
        sleep 2
    done
    echo ""
}

# Parse command line arguments
CUSTOM_DOMAIN=""
SPECIFIC_PATH=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            CUSTOM_DOMAIN="$2"
            shift 2
            ;;
        -p|--path)
            SPECIFIC_PATH="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Get domain to test
DOMAIN=$(get_domain)
print_color "$GREEN" "Testing cache behavior for domain: $DOMAIN"
echo ""

# Test specific path if provided
if [ -n "$SPECIFIC_PATH" ]; then
    test_cache_headers "https://$DOMAIN$SPECIFIC_PATH" "Custom path: $SPECIFIC_PATH"
    test_cache_ttl "https://$DOMAIN$SPECIFIC_PATH" "Custom path: $SPECIFIC_PATH"
    exit 0
fi

# Test multiple paths
print_color "$GREEN" "Testing different content types..."
echo ""

# Test frontend (HTML)
test_cache_headers "https://$DOMAIN/" "Frontend - Index Page"

# Test static assets (if they exist)
test_cache_headers "https://$DOMAIN/styles.css" "Static Asset - CSS"
test_cache_headers "https://$DOMAIN/script.js" "Static Asset - JavaScript"
test_cache_headers "https://$DOMAIN/favicon.ico" "Static Asset - Favicon"

# Test API endpoints (should not be cached)
test_cache_headers "https://$DOMAIN/api/status" "API Endpoint - Status"
test_cache_headers "https://$DOMAIN/healthz" "Health Check"

# Test cache TTL behavior
print_color "$GREEN" "Testing cache TTL behavior..."
echo ""
test_cache_ttl "https://$DOMAIN/" "Frontend caching over time"

print_color "$GREEN" "Cache testing complete!"
echo ""
print_color "$YELLOW" "Remember:"
echo "- Static assets should cache for 1 hour (3600s) by default"
echo "- API endpoints should not cache (TTL = 0)"
echo "- Maximum cache time is 24 hours (86400s)"
echo "- Use './scripts/invalidate-cache.sh' to clear cache manually"