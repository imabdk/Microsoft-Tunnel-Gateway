#!/bin/bash
#
# Ubuntu UFW Firewall Configuration for Microsoft Tunnel Gateway
# For Ubuntu Server 22.04 LTS / 24.04 LTS
# Configures required inbound ports and enables firewall
#
# Note: This script is Ubuntu-specific (uses UFW)
# Usage: curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/master/setup-firewall-ubuntu.sh | sudo bash
#

set -e

echo "=========================================="
echo "UFW Firewall Configuration"
echo "Microsoft Tunnel Gateway"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo "[1/6] Checking UFW installation..."
if ! command -v ufw &> /dev/null; then
    echo "UFW not found. Installing..."
    apt update
    apt install -y ufw
else
    echo "UFW is already installed"
fi

echo "[2/6] Detecting SSH port..."
SSH_PORT=$(grep -E "^Port\s+[0-9]+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
SSH_PORT=${SSH_PORT:-22}
echo "  SSH port: $SSH_PORT"

echo "[3/6] Configuring firewall rules..."
echo "  - Allowing TCP 443 (Tunnel inbound)"
ufw allow 443/tcp comment 'Microsoft Tunnel TCP' 2>/dev/null || echo "    Rule already exists"

echo "  - Allowing UDP 443 (Tunnel inbound)"
ufw allow 443/udp comment 'Microsoft Tunnel UDP' 2>/dev/null || echo "    Rule already exists"

echo "  - Allowing TCP $SSH_PORT (SSH access)"
ufw allow $SSH_PORT/tcp comment 'SSH access' 2>/dev/null || echo "    Rule already exists"

echo "[4/6] Setting default policies..."
ufw default deny incoming
ufw default allow outgoing

echo "[5/6] Enabling firewall..."
if [ -n "$SSH_CONNECTION" ]; then
    echo "  WARNING: You are connected via SSH"
    echo "  SSH port $SSH_PORT has been allowed"
    echo "  Enabling firewall in 5 seconds (Ctrl+C to cancel)..."
    sleep 5
fi

if ufw status | grep -q "Status: active"; then
    ufw reload
    echo "  Firewall reloaded"
else
    ufw --force enable
    echo "  Firewall enabled"
fi

echo "[6/6] Verifying configuration..."
ufw status verbose

echo ""
echo "=========================================="
echo "Firewall Configuration Complete"
echo "=========================================="
echo ""
ufw status numbered
echo ""
