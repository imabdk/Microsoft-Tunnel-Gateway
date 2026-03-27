#!/bin/bash

################################################################################
# mst-mindcore-health - Microsoft Tunnel Gateway Health Check Tool
# 
# Developed by: Mindcore (https://mindcore.dk)
# Purpose: Post-installation health validation for Microsoft Tunnel Gateway
#          Validates service status, configuration, certificates, and logs
# 
# Scope: Installed tunnel server health monitoring
#        (For pre-installation network diagnostics, use mst-mindcore-net-diag.sh)
# 
# Checks performed:
#   1. Service & container status (mst-cli health, Docker/Podman)
#   2. Configuration files (admin-settings.json, certs, keys)
#   3. Certificate expiration (warns if < 30 days)
#   4. Recent errors in logs (last 30 minutes)
#   5. Server configuration (routes, DNS, ports)
#   6. Listening ports (VPN port accessibility)
#   7. DNS resolution (tests DNS servers from Tunnel configuration)
#
# Usage: sudo ./mst-mindcore-health.sh [--dns <hostname>]
#        --dns (optional): test DNS resolution for this host against Tunnel DNS servers
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DNS_TEST_HOST=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dns) DNS_TEST_HOST="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: Run as root${NC}"
    exit 1
fi

echo "================================================================================"
echo "mst-mindcore-health - Microsoft Tunnel Gateway Health Check"
echo "Developed by Mindcore | https://mindcore.dk"
echo "================================================================================"
echo ""

ISSUES=0

# Service & container status
echo -e "${BLUE}[1] Service & Container Status${NC}"

if command -v mst-cli &> /dev/null; then
    SERVER_STATUS=$(mst-cli server status 2>/dev/null)
    AGENT_STATUS=$(mst-cli agent status 2>/dev/null)
    
    echo "Server:"
    echo "$SERVER_STATUS" | sed 's/^/  /'
    echo ""
    echo "Agent:"
    echo "$AGENT_STATUS" | sed 's/^/  /'
    
    if echo "$SERVER_STATUS" | grep -q "Health: healthy" && echo "$AGENT_STATUS" | grep -q "Health: healthy"; then
        echo ""
        echo -e "${GREEN}[OK] Server and agent healthy${NC}"
    else
        echo ""
        echo -e "${RED}[FAIL] Service not healthy${NC}"
        ((ISSUES++))
    fi
else
    echo -e "${RED}[FAIL] mst-cli not found${NC}"
    ((ISSUES++))
fi

echo ""
echo "Containers:"
CONTAINER_CMD=""
if command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
elif command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
fi

if [ -n "$CONTAINER_CMD" ]; then
    CONTAINERS=$($CONTAINER_CMD ps --filter "name=mstunnel" --format "{{.Names}} - {{.Status}}")
    if [ -n "$CONTAINERS" ]; then
        echo "$CONTAINERS" | sed 's/^/  /'
        CONTAINER_COUNT=$(echo "$CONTAINERS" | wc -l)
        echo -e "${GREEN}[OK] $CONTAINER_COUNT container(s) running ($CONTAINER_CMD)${NC}"
    else
        echo -e "${RED}[FAIL] No containers running${NC}"
        ((ISSUES++))
    fi
else
    echo -e "${RED}[FAIL] Docker/Podman not found${NC}"
    ((ISSUES++))
fi

echo ""
echo "Configuration sync status (from logs):"
CONFIG_APPLIED=$(journalctl -t mstunnel-agent --since "4 hours ago" 2>/dev/null | grep -i "Writing new configuration for Server" | tail -1)

if [ -n "$CONFIG_APPLIED" ]; then
    echo -e "${GREEN}Configuration successfully applied:${NC}"
    echo "$CONFIG_APPLIED" | sed 's/^/  /'
else
    echo "No configuration sync messages in last 4 hours"
fi

echo ""
echo "Active VPN Connections:"
if command -v mst-cli &> /dev/null; then
    ACTIVE_CONNECTIONS=$(mst-cli server sessions list 2>/dev/null | grep -c "User:" || echo "0")
    ACTIVE_CONNECTIONS=${ACTIVE_CONNECTIONS:-0}
    if [[ "$ACTIVE_CONNECTIONS" =~ ^[0-9]+$ ]] && [ "$ACTIVE_CONNECTIONS" -gt 0 ]; then
        echo -e "${GREEN}Currently connected clients: $ACTIVE_CONNECTIONS${NC}"
    else
        echo "Currently connected clients: 0"
    fi
fi
echo ""

# Configuration files
echo -e "${BLUE}[2] Configuration Files${NC}"

CONFIG_FILES=(
    "/etc/mstunnel/admin-settings.json"
    "/etc/mstunnel/agent-info.json"
    "/etc/mstunnel/ocserv.conf"
    "/etc/mstunnel/env.sh"
    "/etc/mstunnel/certs/site.crt"
    "/etc/mstunnel/private/site.key"
)

for file in "${CONFIG_FILES[@]}"; do
    if [ -f "$file" ]; then
        SIZE=$(ls -lh "$file" | awk '{print $5}')
        MODIFIED=$(stat -c %y "$file" | cut -d' ' -f1,2 | cut -d'.' -f1)
        echo -e "${GREEN}[OK]${NC} $file ($SIZE, $MODIFIED)"
    else
        echo -e "${RED}[MISSING]${NC} $file"
        ((ISSUES++))
    fi
done

echo ""
echo "Recent configuration changes:"
RECENT_CONFIG_CHANGE=$(find /etc/mstunnel -name "*.json" -mmin -1440 2>/dev/null)
if [ -n "$RECENT_CONFIG_CHANGE" ]; then
    echo -e "${YELLOW}[INFO] Configuration files modified in last 24h:${NC}"
    echo "$RECENT_CONFIG_CHANGE" | while read file; do
        MODIFIED=$(stat -c %y "$file" | cut -d'.' -f1)
        echo "  - $(basename $file) ($MODIFIED)"
    done
else
    echo "No configuration changes in last 24 hours"
fi
echo ""

# Certificate expiration
echo -e "${BLUE}[3] Certificate${NC}"

if [ -f "/etc/mstunnel/certs/site.crt" ]; then
    CERT_EXPIRY=$(openssl x509 -enddate -noout -in /etc/mstunnel/certs/site.crt | cut -d= -f2)
    CERT_EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s)
    CURRENT_EPOCH=$(date +%s)
    DAYS_REMAINING=$(( ($CERT_EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))
    
    if [ $DAYS_REMAINING -gt 30 ]; then
        echo -e "${GREEN}[OK] Valid for $DAYS_REMAINING days (expires: $CERT_EXPIRY)${NC}"
    elif [ $DAYS_REMAINING -gt 0 ]; then
        echo -e "${YELLOW}[WARN] Expires in $DAYS_REMAINING days ($CERT_EXPIRY)${NC}"
    else
        echo -e "${RED}[EXPIRED] ${DAYS_REMAINING#-} days ago ($CERT_EXPIRY)${NC}"
        ((ISSUES++))
    fi
    
    # Show SANs if present
    openssl x509 -noout -ext subjectAltName -in /etc/mstunnel/certs/site.crt 2>/dev/null | grep -v "Subject Alternative Name" | sed 's/^[[:space:]]*//'
else
    echo -e "${RED}[FAIL] Certificate not found${NC}"
    ((ISSUES++))
fi
echo ""

# Recent logs
echo -e "${BLUE}[4] Recent Logs (30 min)${NC}"
echo "Sources: mstunnel-agent, mstunnel_monitor, ocserv"

ERROR_COUNT=$(journalctl -t mstunnel-agent -t mstunnel_monitor -t ocserv --since "30 minutes ago" 2>/dev/null | grep -i "error\|fail\|critical" | grep -v "CheckRevocationOnFullChain" | wc -l)

if [ $ERROR_COUNT -eq 0 ]; then
    echo -e "${GREEN}[OK] No errors${NC}"
else
    echo -e "${RED}[FAIL] $ERROR_COUNT error(s) found (showing last 5)${NC}"
    ((ISSUES++))
    echo ""
    
    # Get last 5 errors and format them cleanly
    journalctl -t mstunnel-agent -t mstunnel_monitor -t ocserv --since "30 minutes ago" 2>/dev/null | \
        grep -i "error\|fail\|critical" | \
        grep -v "CheckRevocationOnFullChain" | \
        tail -5 | \
        while IFS= read -r line; do
            echo -e "${RED}●${NC} $line"
        done
    
    echo ""
    echo -e "${RED}Investigate further with these commands:${NC}"
    echo ""
    echo -e "  ${RED}# View full monitor logs (reconfiguration errors, squid issues):${NC}"
    echo -e "  ${YELLOW}sudo journalctl -t mstunnel_monitor --since \"1 hour ago\"${NC}"
    echo ""
    echo -e "  ${RED}# View full agent logs (configuration sync, Intune communication):${NC}"
    echo -e "  ${YELLOW}sudo journalctl -t mstunnel-agent --since \"1 hour ago\"${NC}"
    echo ""
    echo -e "  ${RED}# Check for specific error patterns:${NC}"
    echo -e "  ${YELLOW}sudo journalctl -t mstunnel_monitor --since \"1 hour ago\" | grep -i \"squid\\|illegal\\|reconfigure\"${NC}"
    echo ""
    echo -e "  ${RED}# Check Docker service status (if container errors):${NC}"
    echo -e "  ${YELLOW}sudo systemctl status docker${NC}"
fi
echo ""

# Configuration summary
echo -e "${BLUE}[5] Configuration${NC}"

LISTEN_PORT="443"
if [ -f "/etc/mstunnel/admin-settings.json" ]; then
    CONFIG=$(cat /etc/mstunnel/admin-settings.json 2>/dev/null)
    echo "Name: $(echo "$CONFIG" | jq -r '.DisplayName // "N/A"')"
    echo "IP Range: $(echo "$CONFIG" | jq -r '.Network // "N/A"')"
    echo "DNS: $(echo "$CONFIG" | jq -r '.DNSServers | join(", ") // "N/A"')"
    LISTEN_PORT=$(echo "$CONFIG" | jq -r '.ListenPort // "443"')
    echo "Port: $LISTEN_PORT"
    echo "Routes Include: $(echo "$CONFIG" | jq -r '.RoutesInclude | join(", ") // "[]"')"
    echo "Routes Exclude: $(echo "$CONFIG" | jq -r '.RoutesExclude | join(", ") // "[]"')"
else
    echo -e "${RED}[FAIL] Config not found${NC}"
    ((ISSUES++))
fi
echo ""

# Listening ports
echo -e "${BLUE}[6] Listening Ports${NC}"

if netstat -tuln 2>/dev/null | grep -q ":${LISTEN_PORT} " || ss -tuln 2>/dev/null | grep -q ":${LISTEN_PORT} "; then
    echo -e "${GREEN}[OK] Listening on port $LISTEN_PORT${NC}"
else
    echo -e "${RED}[FAIL] Not listening on port $LISTEN_PORT${NC}"
    ((ISSUES++))
fi
echo ""

# DNS resolution
echo -e "${BLUE}[7] DNS Resolution${NC}"
echo "Testing DNS servers from Tunnel configuration..."

if [ -f "/etc/mstunnel/admin-settings.json" ]; then
    DNS_SERVERS=$(cat /etc/mstunnel/admin-settings.json 2>/dev/null | jq -r '.DNSServers[]? // empty' 2>/dev/null)
    if [ -n "$DNS_SERVERS" ]; then
        DNS_FAIL=0
        while IFS= read -r DNS_SERVER; do
            echo ""
            echo "  $DNS_SERVER:"
            # Test reachability with a simple query
            DIG_RESULT=$(dig @"$DNS_SERVER" +time=3 +tries=1 +short version.bind chaos txt 2>&1)
            DIG_EXIT=$?
            if [ $DIG_EXIT -eq 0 ] && ! echo "$DIG_RESULT" | grep -qi "timed out\|no servers\|connection refused"; then
                echo -e "    ${GREEN}[OK] Reachable${NC}"
            else
                echo -e "    ${RED}[FAIL] Not responding${NC}"
                ((DNS_FAIL++))
                ((ISSUES++))
            fi
            # If test hostname provided, resolve it
            if [ -n "$DNS_TEST_HOST" ]; then
                RESOLVE=$(dig @"$DNS_SERVER" "$DNS_TEST_HOST" +time=3 +tries=1 +short 2>&1)
                if [ -n "$RESOLVE" ] && ! echo "$RESOLVE" | grep -qi "timed out\|no servers\|connection refused"; then
                    echo -e "    $DNS_TEST_HOST → $RESOLVE"
                else
                    echo -e "    ${YELLOW}$DNS_TEST_HOST → no answer${NC}"
                fi
            fi
        done <<< "$DNS_SERVERS"
        echo ""
        DNS_TOTAL=$(echo "$DNS_SERVERS" | wc -l)
        if [ $DNS_FAIL -eq 0 ]; then
            echo -e "${GREEN}[OK] All $DNS_TOTAL DNS server(s) reachable${NC}"
        else
            echo -e "${RED}[FAIL] $DNS_FAIL of $DNS_TOTAL DNS server(s) not reachable${NC}"
        fi
        if [ -z "$DNS_TEST_HOST" ]; then
            echo ""
            echo "Tip: pass a hostname to test resolution: sudo ./mst-mindcore-health.sh --dns intranet.contoso.com"
        fi
    else
        echo -e "${YELLOW}[WARN] No DNS servers configured${NC}"
    fi
else
    echo -e "${RED}[FAIL] Config not found${NC}"
fi
echo ""

echo "================================================================================"
if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}Health check passed${NC}"
else
    echo -e "${YELLOW}Found $ISSUES issue(s)${NC}"
fi
echo ""
echo "Test inbound connectivity from an external network:"
echo "  openssl s_client -connect <tunnel-fqdn>:$LISTEN_PORT"
echo "================================================================================"

exit $ISSUES
