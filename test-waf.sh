#!/bin/bash

# WAF Rate Limiting Test Script
# This script tests the AWS WAF rate limiting by sending parallel requests
# Current WAF limit: 100 requests per 5-minute window per IP

URL="https://poc-app-platform-aws.digitalocean.solutions/healthz"
TOTAL_REQUESTS=120

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage function
usage() {
    echo "Usage: $0 [-n NUM_REQUESTS] [-h]"
    echo "  -n: Number of requests to send (default: 120)"
    echo "  -h: Show this help message"
    exit 1
}

# Parse command line options
while getopts "n:h" opt; do
    case $opt in
        n)
            TOTAL_REQUESTS=$OPTARG
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

echo -e "${YELLOW}WAF Rate Limiting Test${NC}"
echo "Testing URL: $URL"
echo "Total requests: $TOTAL_REQUESTS"
echo "Expected rate limit: 100 requests per 5-minute window"
echo ""

# Create temporary file for results
RESULTS_FILE=$(mktemp)

# Function to send a single request and check status
send_request() {
    local request_num=$1
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
    
    if [ "$status_code" = "200" ]; then
        echo -e "✓ Request $request_num: ${GREEN}SUCCESS${NC} ($status_code)"
        echo "SUCCESS:$request_num" >> "$RESULTS_FILE"
    elif [ "$status_code" = "403" ]; then
        echo -e "✗ Request $request_num: ${RED}BLOCKED${NC} ($status_code) - WAF Rate Limit"
        echo "BLOCKED:$request_num" >> "$RESULTS_FILE"
    else
        echo -e "? Request $request_num: ${YELLOW}OTHER${NC} ($status_code)"
        echo "OTHER:$request_num:$status_code" >> "$RESULTS_FILE"
    fi
}

# Send all requests in parallel as fast as possible
echo "Sending $TOTAL_REQUESTS requests in parallel..."
for ((i=1; i<=TOTAL_REQUESTS; i++)); do
    send_request $i &
done
wait

# Analyze results
successful_requests=$(grep -c "^SUCCESS:" "$RESULTS_FILE" 2>/dev/null || echo "0")
blocked_requests=$(grep -c "^BLOCKED:" "$RESULTS_FILE" 2>/dev/null || echo "0")
other_requests=$(grep -c "^OTHER:" "$RESULTS_FILE" 2>/dev/null || echo "0")

# Find first blocked request
first_block_line=$(grep "^BLOCKED:" "$RESULTS_FILE" | head -1)
if [ -n "$first_block_line" ]; then
    first_block_at=$(echo "$first_block_line" | cut -d: -f2)
else
    first_block_at="0"
fi

# Clean up
rm -f "$RESULTS_FILE"

echo ""
echo -e "${YELLOW}=== TEST RESULTS ===${NC}"
echo "Total requests sent: $TOTAL_REQUESTS"
echo -e "Successful requests: ${GREEN}$successful_requests${NC}"
echo -e "Blocked requests: ${RED}$blocked_requests${NC}"
if [ "$other_requests" != "0" ]; then
    echo -e "Other responses: ${YELLOW}$other_requests${NC}"
fi

if [ "$first_block_at" != "0" ]; then
    echo -e "WAF started blocking at request: ${YELLOW}#$first_block_at${NC}"
    echo -e "${GREEN}✓ WAF rate limiting is working correctly!${NC}"
else
    echo -e "${YELLOW}⚠ No requests were blocked - WAF may not be working or limit not reached${NC}"
fi

echo ""
echo "Note: WAF rate limiting operates on 5-minute windows per IP address."
echo "If you want to test again immediately, you may need to wait or use a different IP."