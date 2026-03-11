#!/bin/bash
#
# Ubuntu UFW Firewall Configuration for Microsoft Tunnel Gateway
# For Ubuntu Server 22.04 LTS / 24.04 LTS
# Configures required inbound ports and enables firewall
#
# Note: This script is Ubuntu/Debian-specific (uses UFW)
# Usage: curl -fsSL https://imab.dk/tunnel/3-setup-firewall-ubuntu.sh | sudo bash
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

echo "[1/5] Checking UFW installation..."
if ! command -v ufw &> /dev/null; then
    echo "UFW not found. Installing..."
    apt update
    apt install -y ufw
else
    echo "UFW is already installed"
fi

echo "[2/5] Configuring firewall rules..."
echo "  - Allowing TCP 443 (Tunnel inbound)"
ufw allow 443/tcp comment 'Microsoft Tunnel TCP'

echo "  - Allowing UDP 443 (Tunnel inbound)"
ufw allow 443/udp comment 'Microsoft Tunnel UDP'

echo "  - Allowing TCP 22 (SSH access)"
ufw allow 22/tcp comment 'SSH access'

echo "[3/5] Setting default policies..."
ufw default deny incoming
ufw default allow outgoing

echo "[4/5] Enabling firewall..."
echo "y" | ufw enable

echo "[5/5] Verifying configuration..."
ufw status verbose

echo ""
echo "=========================================="
echo "✅ Firewall Configuration Complete!"
echo "=========================================="
echo ""
echo "Active rules:"
ufw status numbered
echo ""
echo "Note: Outbound TCP 443 is allowed by default"
echo "(required for Intune services and Docker)"
echo ""
