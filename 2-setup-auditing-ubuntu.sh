#!/bin/bash
#
# Ubuntu System Auditing Setup for Microsoft Tunnel Gateway
# For Ubuntu Server 22.04 LTS / 24.04 LTS
# Installs auditd and Microsoft Tunnel audit rules
#
# Note: This script is Ubuntu/Debian-specific (uses apt)
# Usage: curl -fsSL https://imab.dk/tunnel/2-setup-auditing-ubuntu.sh | sudo bash
#

set -e

echo "=========================================="
echo "Linux System Auditing Setup"
echo "Microsoft Tunnel Gateway"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo "[1/4] Installing auditd and plugins..."
apt update
apt install -y auditd audispd-plugins

echo "[2/4] Downloading Microsoft Tunnel audit rules..."
wget https://aka.ms/TunnelAuditdRules -O mst.rules

echo "[3/4] Installing audit rules..."
cp mst.rules /etc/audit/rules.d/
rm mst.rules

echo "[4/4] Loading audit rules..."
augenrules --load

echo ""
echo "=========================================="
echo "✅ System Auditing Setup Complete!"
echo "=========================================="
echo ""
echo "Audit rules loaded from: /etc/audit/rules.d/mst.rules"
echo ""
echo "Check audit status:"
echo "  sudo systemctl status auditd"
echo ""
echo "View audit logs:"
echo "  sudo ausearch -ts recent"
echo ""
