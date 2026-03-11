#!/bin/bash

################################################################################
# mst-mindcore-net-diag - Microsoft Tunnel Gateway Network Diagnostic Tool
# 
# Developed by: Mindcore (https://mindcore.dk)
# Purpose: Pre-installation network diagnostics for Microsoft Tunnel Gateway
#          Diagnoses mst-readiness failures caused by redirect target blocking
#          Replicates Microsoft's exact validation logic to identify firewall issues
# 
# Scope: Network connectivity and firewall validation ONLY
#        (For post-installation health checks, use mst-mindcore-health.sh)
# 
# Usage: ./mst-mindcore-net-diag.sh [hostname]
#        ./mst-mindcore-net-diag.sh login.windows.net
#        ./mst-mindcore-net-diag.sh login.microsoftonline.com
# Download: curl -fsSL https://imab.dk/tunnel/mst-mindcore-net-diag.sh | bash -s -- [hostname]
################################################################################

set +e  # Don't exit on errors, we want to see all results

# Get target host from parameter or use default
TARGET_HOST="${1:-login.windows.net}"

echo "=========================================================================="
echo "mst-mindcore-net-diag - Tunnel Gateway Network Diagnostic"
echo "Developed by Mindcore | https://mindcore.dk"
echo "Testing: $TARGET_HOST"
echo "=========================================================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counter for results
REDIRECT_PASS=0
REDIRECT_FAIL=0

echo "=========================================================================="
echo "STEP 1: REDIRECT DETECTION"
echo "=========================================================================="
echo "Checking if $TARGET_HOST uses redirects (testing without -L flag)"
echo ""

OUTPUT=$(curl -v https://$TARGET_HOST -m 20 -s -S -o /dev/null 2>&1)
HTTP_STATUS=$(echo "$OUTPUT" | awk '/^< HTTP/{print $3; exit}')

if [ "$HTTP_STATUS" = "302" ] || [ "$HTTP_STATUS" = "301" ]; then
    REDIRECT_TO=$(echo "$OUTPUT" | awk -F': ' '/^< [Ll]ocation:/{print $2; exit}' | tr -d '\r')
    REDIRECT_HOST=$(echo "$REDIRECT_TO" | awk -F'/' '{print $3}')
    echo -e "${GREEN}[+] PASS${NC} - $TARGET_HOST returns HTTP $HTTP_STATUS (redirect)"
    echo -e "  Redirects to: ${BLUE}$REDIRECT_TO${NC}"
    echo ""
elif [ "$HTTP_STATUS" = "200" ]; then
    echo -e "${GREEN}[+] PASS${NC} - $TARGET_HOST returns HTTP 200 (no redirect)"
    echo -e "  ${YELLOW}This endpoint does not redirect - unlikely to cause mst-readiness issues${NC}"
    echo ""
    echo "No redirect detected. Skipping redirect chain tests."
    exit 0
else
    echo -e "${RED}[X] FAIL${NC} - Unexpected response from $TARGET_HOST"
    echo -e "  HTTP Status: $HTTP_STATUS"
    exit 1
fi

echo "=========================================================================="
echo "STEP 2: REDIRECT TARGET ACCESSIBILITY"
echo "=========================================================================="
echo "Testing if redirect destination ($REDIRECT_HOST) is reachable"
echo ""
echo "Testing: $REDIRECT_HOST"
echo ""

OUTPUT=$(curl -v https://$REDIRECT_HOST -m 20 -s -S -o /dev/null 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}[+] PASS${NC} - $REDIRECT_HOST is accessible"
    echo -e "  Redirect destination is reachable"
else
    echo -e "${RED}[X] FAIL${NC} - $REDIRECT_HOST is NOT accessible"
    echo -e "  curl exit code: $EXIT_CODE"
    
    if [ $EXIT_CODE -eq 28 ]; then
        echo -e "  ${YELLOW}Error: Connection timed out${NC}"
        echo -e "  ${YELLOW}This domain is likely blocked by your firewall${NC}"
    elif [ $EXIT_CODE -eq 7 ]; then
        echo -e "  ${YELLOW}Error: Failed to connect to host${NC}"
    elif [ $EXIT_CODE -eq 60 ]; then
        echo -e "  ${YELLOW}Error: SSL certificate problem${NC}"
    fi
fi

echo ""

echo "=========================================================================="
echo "STEP 3: REDIRECT CHAIN TEST (WITH -L FLAG)"
echo "=========================================================================="
echo "Now following redirects like Microsoft's mst-readiness script does"
echo ""

# Resolve target host to get actual backend IPs
echo "Resolving $TARGET_HOST to backend IPs..."
if command -v host &> /dev/null; then
    BACKEND_IPS=$(host $TARGET_HOST 2> /dev/null | awk '/has address/ {print $4}')
elif command -v dig &> /dev/null; then
    BACKEND_IPS=$(dig +short $TARGET_HOST | awk '/^([0-9.]{1,3}){4}/ {print}')
elif command -v getent &> /dev/null; then
    BACKEND_IPS=$(getent hosts $TARGET_HOST | awk '{print $1}')
else
    echo -e "${RED}Error: No DNS resolution tool available (host, dig, or getent)${NC}"
    exit 1
fi

if [ -z "$BACKEND_IPS" ]; then
    echo -e "${RED}[X] FAIL${NC} - Could not resolve $TARGET_HOST"
    exit 1
fi

BACKEND_COUNT=$(echo "$BACKEND_IPS" | wc -l)
echo -e "Found ${GREEN}$BACKEND_COUNT${NC} backend IP(s)"
echo ""

echo "${BLUE}Testing each backend IP (replicating mst-readiness behavior):${NC}"
echo "curl https://$TARGET_HOST --resolve $TARGET_HOST:443:<IP> -v -L -S -s -m 20"
echo ""

# Use process substitution to avoid subshell (which loses variable increments)
while read IP; do
    echo "Testing IP: $IP"
    echo "  Command: curl https://$TARGET_HOST --resolve $TARGET_HOST:443:$IP -v -L -S -s -m 20"
    
    # Run Microsoft's exact command
    OUTPUT=$(curl https://$TARGET_HOST --resolve $TARGET_HOST:443:$IP -v -L -S -s -m 20 2>&1)
    EXIT_CODE=$?
    
    # Check for curl errors
    if [ $EXIT_CODE -ne 0 ]; then
        CURL_ERROR=$(echo "$OUTPUT" | awk '/^curl:/ {print}')
        
        if [ $EXIT_CODE -eq 28 ]; then
            echo -e "  ${RED}[X] FAIL${NC} - Connection timed out (exit code 28)"
            echo -e "  ${YELLOW}Cause: Redirect target ($REDIRECT_HOST) is blocked${NC}"
            ((REDIRECT_FAIL++))
        elif [ $EXIT_CODE -eq 60 ]; then
            echo -e "  ${RED}[X] FAIL${NC} - SSL certificate error (exit code 60)"
            echo -e "  ${YELLOW}Cause: Certificate validation failed${NC}"
            ((REDIRECT_FAIL++))
        elif [ $EXIT_CODE -eq 7 ]; then
            echo -e "  ${RED}[X] FAIL${NC} - Failed to connect (exit code 7)"
            echo -e "  ${YELLOW}Cause: Connection refused or firewall block${NC}"
            ((REDIRECT_FAIL++))
        else
            echo -e "  ${RED}[X] FAIL${NC} - curl error (exit code $EXIT_CODE)"
            echo "$CURL_ERROR"
            ((REDIRECT_FAIL++))
        fi
    else
        FINAL_HTTP=$(echo "$OUTPUT" | awk '/^< HTTP/{status=$3} END{print status}')
        echo -e "  ${GREEN}[+] PASS${NC} - Completed successfully (HTTP $FINAL_HTTP)"
        ((REDIRECT_PASS++))
    fi
    echo ""
done < <(echo "$BACKEND_IPS")

echo "=========================================================================="
echo "SUMMARY AND ROOT CAUSE ANALYSIS"
echo "=========================================================================="
echo ""

if [ $REDIRECT_FAIL -gt 0 ]; then
    echo -e "${RED}+======================================================================+${NC}"
    echo -e "${RED}|  ROOT CAUSE IDENTIFIED: REDIRECT TARGET BLOCKED BY FIREWALL         |${NC}"
    echo -e "${RED}+======================================================================+${NC}"
    echo ""
    echo -e "${YELLOW}What happens:${NC}"
    echo "  1. $TARGET_HOST returns HTTP 302 redirect -> [+] Works"
    echo "  2. Redirect points to: $REDIRECT_TO"
    echo "  3. Microsoft's mst-readiness uses -L flag (auto-follows redirects)"
    echo "  4. Curl tries to access $REDIRECT_HOST -> [X] BLOCKED/TIMEOUT"
    echo "  5. curl returns error code 28 (timeout)"
    echo "  6. mst-readiness shows: 'Error: not expected'"
    echo ""
    echo -e "${YELLOW}Why this fails on restricted networks:${NC}"
    echo "  • $TARGET_HOST is whitelisted in firewall"
    echo "  • $REDIRECT_HOST is NOT whitelisted"
    echo "  • mst-readiness uses -L flag (auto-follows redirects)"
    echo "  • Connection times out on blocked domain"
    echo ""
    echo -e "${YELLOW}Why this works on open networks:${NC}"
    echo "  • No firewall restrictions on $REDIRECT_HOST"
    echo "  • Redirect completes successfully"
    echo ""
    echo -e "${GREEN}SOLUTION:${NC}"
    echo ""
    echo "Ask your network administrator to whitelist these domains:"
    echo ""
    echo "  [+] $REDIRECT_HOST"
    echo "  [+] *.office.com (wildcard to cover all Office endpoints)"
    echo ""
    echo "Additionally, if you see certificate errors, also whitelist:"
    echo "  [+] *.msidentity.com"
    echo "  [+] *.akadns.net"
    echo ""
    echo -e "${BLUE}After firewall update, verify with:${NC}"
    echo "  curl -v https://$REDIRECT_HOST"
    echo ""
    echo -e "${YELLOW}Can you proceed with Microsoft Tunnel installation?${NC}"
    echo "  • Installation may work if other auth endpoints are accessible"
    echo "  • However, $TARGET_HOST failures could cause runtime issues"
    echo "  • RECOMMENDED: Whitelist $REDIRECT_HOST before proceeding"
    echo ""
else
    echo -e "${GREEN}+======================================================================+${NC}"
    echo -e "${GREEN}|  ALL CONNECTIVITY CHECKS PASSED                                      |${NC}"
    echo -e "${GREEN}+======================================================================+${NC}"
    echo ""
    echo "  • $TARGET_HOST: Returns HTTP 302"
    echo "  • $REDIRECT_HOST: Reachable"
    echo "  • All backend IPs: Tested successfully"
    echo "  • Redirect chain: Complete"
    echo ""
    echo -e "${GREEN}[+] No firewall blocking detected. Ready for Tunnel installation.${NC}"
    echo ""
fi

echo "=========================================================================="
echo "Script completed: $(date)"
echo "=========================================================================="
