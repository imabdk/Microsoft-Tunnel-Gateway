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
#   1. Service status (mst-cli server/agent health)
#   2. Container status (Docker/Podman mstunnel containers)
#   3. Configuration files (admin-settings.json, certs, keys)
#   4. Certificate expiration (warns if < 30 days)
#   5. Recent errors in logs (last 10 minutes)
#   6. Server configuration (routes, DNS, ports)
#   7. Listening ports (VPN port accessibility)
#   8. External connectivity testing
#
# Usage: sudo ./mst-mindcore-health.sh
# Download: curl -fsSL https://imab.dk/tunnel/mst-mindcore-health.sh | sudo bash
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Service status
echo -e "${BLUE}[1] Service Status${NC}"

if command -v mst-cli &> /dev/null; then
    SERVER_STATUS=$(mst-cli server status 2>/dev/null)
    AGENT_STATUS=$(mst-cli agent status 2>/dev/null)
    
    echo "$SERVER_STATUS"
    echo "$AGENT_STATUS"
    
    if echo "$SERVER_STATUS" | grep -q "Health: healthy" && echo "$AGENT_STATUS" | grep -q "Health: healthy"; then
        echo -e "${GREEN}[OK] Server and agent healthy${NC}"
    else
        echo -e "${RED}[FAIL] Service not healthy${NC}"
        ((ISSUES++))
    fi
    
    echo ""
    echo "Configuration sync status (from logs):"
    # Check for configuration-related messages in agent logs
    CONFIG_APPLIED=$(journalctl -t mstunnel-agent --since "4 hours ago" 2>/dev/null | grep -i "Writing new configuration for Server" | tail -1)
    
    if [ -n "$CONFIG_APPLIED" ]; then
        echo -e "${GREEN}Configuration successfully applied:${NC}"
        echo "$CONFIG_APPLIED" | sed 's/^/  /'
    else
        echo "No configuration sync messages in last 4 hours"
    fi
else
    echo -e "${RED}[FAIL] mst-cli not found${NC}"
    ((ISSUES++))
fi
echo ""

# Container status
echo -e "${BLUE}[2] Containers${NC}"

if command -v docker &> /dev/null; then
    CONTAINERS=$(docker ps --filter "name=mstunnel" --format "{{.Names}} - {{.Status}}")
    if [ -n "$CONTAINERS" ]; then
        echo "$CONTAINERS"
        CONTAINER_COUNT=$(echo "$CONTAINERS" | wc -l)
        echo -e "${GREEN}[OK] $CONTAINER_COUNT container(s) running${NC}"
    else
        echo -e "${RED}[FAIL] No containers running${NC}"
        ((ISSUES++))
    fi
elif command -v podman &> /dev/null; then
    CONTAINERS=$(podman ps --filter "name=mstunnel" --format "{{.Names}} - {{.Status}}")
    if [ -n "$CONTAINERS" ]; then
        echo "$CONTAINERS"
        CONTAINER_COUNT=$(echo "$CONTAINERS" | wc -l)
        echo -e "${GREEN}[OK] $CONTAINER_COUNT container(s) running${NC}"
    else
        echo -e "${RED}[FAIL] No containers running${NC}"
        ((ISSUES++))
    fi
else
    echo -e "${RED}[FAIL] Docker/Podman not found${NC}"
    ((ISSUES++))
fi
echo ""

# Configuration files
echo -e "${BLUE}[3] Configuration Files${NC}"

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

# Certificate expiration
echo -e "${BLUE}[4] Certificate${NC}"

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
else
    echo -e "${RED}[FAIL] Certificate not found${NC}"
    ((ISSUES++))
fi
echo ""

# Recent logs
echo -e "${BLUE}[5] Recent Logs (30 min)${NC}"
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
echo -e "${BLUE}[6] Configuration${NC}"

if [ -f "/etc/mstunnel/admin-settings.json" ]; then
    echo "Name: $(jq -r '.DisplayName' /etc/mstunnel/admin-settings.json 2>/dev/null || echo "N/A")"
    echo "IP Range: $(jq -r '.Network' /etc/mstunnel/admin-settings.json 2>/dev/null || echo "N/A")"
    echo "DNS: $(jq -r '.DNSServers | join(", ")' /etc/mstunnel/admin-settings.json 2>/dev/null || echo "N/A")"
    echo "Port: $(jq -r '.ListenPort' /etc/mstunnel/admin-settings.json 2>/dev/null || echo "N/A")"
    echo "Routes Include: $(jq -r '.RoutesInclude | join(", ")' /etc/mstunnel/admin-settings.json 2>/dev/null || echo "[]")"
    echo "Routes Exclude: $(jq -r '.RoutesExclude | join(", ")' /etc/mstunnel/admin-settings.json 2>/dev/null || echo "[]")"
else
    echo -e "${RED}[FAIL] Config not found${NC}"
    ((ISSUES++))
fi
echo ""

# Listening ports
echo -e "${BLUE}[7] Listening Ports${NC}"

LISTEN_PORT=$(jq -r '.ListenPort' /etc/mstunnel/admin-settings.json 2>/dev/null || echo "443")

if netstat -tuln 2>/dev/null | grep -q ":${LISTEN_PORT} " || ss -tuln 2>/dev/null | grep -q ":${LISTEN_PORT} "; then
    echo -e "${GREEN}[OK] Listening on port $LISTEN_PORT${NC}"
else
    echo -e "${RED}[FAIL] Not listening on port $LISTEN_PORT${NC}"
    ((ISSUES++))
fi
echo ""

# External connectivity testing info
echo -e "${BLUE}[8] External Connectivity Testing${NC}"

FQDN=""
# Extract FQDN from certificate CN (primary source per MS docs)
if [ -f "/etc/mstunnel/certs/site.crt" ]; then
    FQDN=$(openssl x509 -noout -subject -in /etc/mstunnel/certs/site.crt 2>/dev/null | sed -n 's/.*CN = \([^,]*\).*/\1/p')
fi

if [ -n "$FQDN" ] && [ "$FQDN" != "null" ]; then
    echo "Configured endpoint: $FQDN:$LISTEN_PORT (from certificate CN)"
    echo ""
    echo "Test inbound connectivity from external network:"
    echo "  1. From external machine: openssl s_client -connect $FQDN:$LISTEN_PORT"
    echo "  2. Online TLS checker: https://www.ssllabs.com/ssltest/analyze.html?d=$FQDN"
else
    echo "FQDN not found in certificate"
fi
echo ""
echo "================================================================================"
if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}Health check passed${NC}"
else
    echo -e "${YELLOW}Found $ISSUES issue(s)${NC}"
fi
echo "================================================================================"

exit $ISSUES
