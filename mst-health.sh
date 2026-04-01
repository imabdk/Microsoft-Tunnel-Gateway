#!/bin/bash

################################################################################
# mst-health - Microsoft Tunnel Gateway Health Check Tool
# Version: 1.0
#
# Developed by: Martin Bengtsson | https://imab.dk
# Blog series:  https://www.imab.dk/10-days-and-10-tips-for-microsoft-tunnel-gateway
# GitHub:       https://github.com/imabdk/Microsoft-Tunnel-Gateway
#
# Purpose: Post-installation health validation for Microsoft Tunnel Gateway
#          Validates service status, configuration, certificates, and logs
# 
# Checks performed:
#   1. Service & container status (mst-cli health, Docker/Podman)
#   2. Configuration files (admin-settings.json, certs, keys)
#   3. Certificate expiration (warns if < 30 days)
#   4. Recent errors in logs (last 30 minutes)
#   5. Server configuration (routes, DNS, ports)
#   6. Listening ports (VPN port accessibility)
#
# Usage: sudo ./mst-health.sh
#
# Download: curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/refs/heads/master/mst-health.sh | sudo bash
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
echo "mst-health - Microsoft Tunnel Gateway Health Check"
echo "Martin Bengtsson | imab.dk"
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
        
        # Check if all containers are healthy (not just running)
        UNHEALTHY_CONTAINERS=$(echo "$CONTAINERS" | grep -E "\(health: (starting|unhealthy)\)" || true)
        
        if [ -z "$UNHEALTHY_CONTAINERS" ]; then
            echo -e "${GREEN}[OK] $CONTAINER_COUNT container(s) running and healthy ($CONTAINER_CMD)${NC}"
        else
            echo -e "${YELLOW}[WARN] $CONTAINER_COUNT container(s) running but not all healthy${NC}"
            echo -e "${YELLOW}       Some containers are still starting or unhealthy${NC}"
            ((ISSUES++))
        fi
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
