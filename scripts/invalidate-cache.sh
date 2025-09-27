#!/bin/bash

# CloudFront Cache Invalidation Script
# This script provides easy cache management for the CloudFront distribution

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
    echo "  -p, --paths PATHS    Paths to invalidate (default: '/*' for all)"
    echo "  -s, --status ID      Check status of invalidation by ID"
    echo "  -l, --list           List recent invalidations"
    echo "  -w, --wait           Wait for invalidation to complete (default: true)"
    echo "  --no-wait            Don't wait for invalidation to complete"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Invalidate all cached content and wait"
    echo "  $0 --no-wait                 # Invalidate and return immediately"
    echo "  $0 -p '/index.html'          # Invalidate specific file"
    echo "  $0 -p '/css/* /js/*'         # Invalidate multiple paths"
    echo "  $0 -s I1234567890ABCDEF      # Check invalidation status"
    echo "  $0 -l                        # List recent invalidations"
    echo ""
    echo "Makefile shortcuts:"
    echo "  make invalidate-cache        # Invalidate all and wait for completion"
    echo "  make invalidate-cache-quick  # Invalidate all without waiting"
    echo "  make check-cache-headers     # Check current cache headers"
    exit 0
}

# Function to get distribution ID from Terraform
get_distribution_id() {
    local DIST_ID=""

    # Try to get from Terraform output first
    if command -v terraform &> /dev/null; then
        # Check if we can access terraform state
        if terraform -chdir=terraform output cloudfront_distribution_id &>/dev/null; then
            DIST_ID=$(terraform -chdir=terraform output -raw cloudfront_distribution_id 2>/dev/null || true)
        fi
    fi

    # If not found in Terraform, try to get from AWS CLI by looking for distributions with DigitalOcean origins
    if [ -z "$DIST_ID" ]; then
        >&2 echo -e "${YELLOW}Getting CloudFront distribution ID from AWS...${NC}"

        # Look for distributions that have DigitalOcean Spaces or App Platform origins
        for dist_id in $(aws cloudfront list-distributions --query "DistributionList.Items[*].Id" --output text 2>/dev/null); do
            # Check if this distribution has DigitalOcean origins
            origins=$(aws cloudfront get-distribution --id "$dist_id" --query "Distribution.DistributionConfig.Origins.Items[*].DomainName" --output text 2>/dev/null || true)
            if echo "$origins" | grep -q "digitaloceanspaces.com\|ondigitalocean.app"; then
                DIST_ID="$dist_id"
                break
            fi
        done
    fi

    if [ -z "$DIST_ID" ]; then
        >&2 echo -e "${RED}Error: Could not determine CloudFront distribution ID${NC}"
        >&2 echo "Please ensure:"
        >&2 echo "1. Terraform outputs are available, or"
        >&2 echo "2. AWS CLI is configured and you have access to CloudFront"
        >&2 echo "3. A CloudFront distribution exists with DigitalOcean origins"
        exit 1
    fi

    echo "$DIST_ID"
}

# Function to wait for invalidation completion
wait_for_completion() {
    local invalidation_id="$1"
    local distribution_id="$2"
    local start_time=$(date +%s)

    echo ""
    print_color "$YELLOW" "Waiting for invalidation to complete..."
    echo "Invalidation ID: $invalidation_id"
    echo "Checking every 5 seconds..."
    echo ""

    while true; do
        # Get current status
        local status=$(aws cloudfront get-invalidation \
            --distribution-id "$distribution_id" \
            --id "$invalidation_id" \
            --query 'Invalidation.Status' \
            --output text 2>/dev/null)

        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ "$status" = "Completed" ]; then
            print_color "$GREEN" "✓ Invalidation completed successfully!"
            echo "Total time: ${elapsed} seconds"
            echo ""
            # Show final status
            aws cloudfront get-invalidation \
                --distribution-id "$distribution_id" \
                --id "$invalidation_id" \
                --query 'Invalidation.{Status:Status,CreateTime:CreateTime}' \
                --output table
            break
        elif [ "$status" = "InProgress" ]; then
            echo "Status: InProgress (${elapsed}s elapsed)"
        else
            print_color "$RED" "Unexpected status: $status"
            break
        fi

        # Wait 5 seconds before next check
        sleep 5
    done
}

# Parse command line arguments
PATHS="/*"
CHECK_STATUS=""
LIST_INVALIDATIONS=false
WAIT_FOR_COMPLETION=true

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--paths)
            PATHS="$2"
            shift 2
            ;;
        -s|--status)
            CHECK_STATUS="$2"
            shift 2
            ;;
        -l|--list)
            LIST_INVALIDATIONS=true
            shift
            ;;
        -w|--wait)
            WAIT_FOR_COMPLETION=true
            shift
            ;;
        --no-wait)
            WAIT_FOR_COMPLETION=false
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

# Get distribution ID
DISTRIBUTION_ID=$(get_distribution_id)
echo ""
print_color "$GREEN" "Using CloudFront Distribution ID: $DISTRIBUTION_ID"

# Check invalidation status
if [ -n "$CHECK_STATUS" ]; then
    print_color "$YELLOW" "Checking invalidation status for ID: $CHECK_STATUS"
    aws cloudfront get-invalidation \
        --distribution-id "$DISTRIBUTION_ID" \
        --id "$CHECK_STATUS" \
        --query 'Invalidation.{Id:Id,Status:Status,CreateTime:CreateTime}' \
        --output table
    exit 0
fi

# List recent invalidations
if [ "$LIST_INVALIDATIONS" = true ]; then
    print_color "$YELLOW" "Recent invalidations:"
    aws cloudfront list-invalidations \
        --distribution-id "$DISTRIBUTION_ID" \
        --query 'InvalidationList.Items[*].{Id:Id,Status:Status,CreateTime:CreateTime}' \
        --output table
    exit 0
fi

# Create invalidation
print_color "$YELLOW" "Creating cache invalidation for paths: $PATHS"

# Convert space-separated paths to JSON array
IFS=' ' read -ra PATH_ARRAY <<< "$PATHS"

# Create a unique caller reference
CALLER_REF="cache-invalidation-$(date +%s)-$$"

# Create the invalidation batch JSON
INVALIDATION_BATCH=$(cat <<EOF
{
  "Paths": {
    "Quantity": ${#PATH_ARRAY[@]},
    "Items": $(printf '%s\n' "${PATH_ARRAY[@]}" | jq -R . | jq -s .)
  },
  "CallerReference": "$CALLER_REF"
}
EOF
)

# Create the invalidation
INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --invalidation-batch "$INVALIDATION_BATCH" \
    --query 'Invalidation.Id' \
    --output text)

if [ -n "$INVALIDATION_ID" ]; then
    print_color "$GREEN" "✓ Invalidation created successfully!"
    echo "Invalidation ID: $INVALIDATION_ID"

    if [ "$WAIT_FOR_COMPLETION" = true ]; then
        # Wait for completion
        wait_for_completion "$INVALIDATION_ID" "$DISTRIBUTION_ID"
    else
        echo ""
        echo "To check status, run:"
        echo "  $0 -s $INVALIDATION_ID"

        # Show initial status
        echo ""
        print_color "$YELLOW" "Current status:"
        aws cloudfront get-invalidation \
            --distribution-id "$DISTRIBUTION_ID" \
            --id "$INVALIDATION_ID" \
            --query 'Invalidation.{Status:Status,CreateTime:CreateTime}' \
            --output table
    fi
else
    print_color "$RED" "Error: Failed to create invalidation"
    exit 1
fi