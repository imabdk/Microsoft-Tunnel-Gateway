#!/bin/bash
#
# setup-auditing-ubuntu.sh
# Microsoft Tunnel Gateway | Lab & Reference Scripts
# Author: Martin Bengtsson | https://www.imab.dk
#
# Purpose: Installs auditd and Microsoft Tunnel audit rules
# Supported: Ubuntu Server 22.04 LTS / 24.04 LTS
# Note: Ubuntu-specific (uses apt)
# Usage: curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/master/Setup-Scripts/setup-auditing-ubuntu.sh | sudo bash
#

# Exit immediately if any command returns a non-zero exit code
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

echo "[1/5] Checking if auditd is already configured..."
if [ -f "/etc/audit/rules.d/mst.rules" ]; then
    echo "  Microsoft Tunnel audit rules already installed"
    echo "  Skipping installation (run manually if you need to reinstall)"
    exit 0
fi

echo "[2/5] Installing auditd and plugins..."
apt update
apt install -y auditd audispd-plugins

echo "[3/5] Downloading Microsoft Tunnel audit rules..."
# aka.ms/TunnelAuditdRules redirects to the official Microsoft Tunnel auditd rules on GitHub
curl -fsSL https://aka.ms/TunnelAuditdRules -o /tmp/mst.rules
if [ ! -s /tmp/mst.rules ]; then
    echo "ERROR: Failed to download audit rules"
    exit 1
fi

echo "[4/5] Installing audit rules..."
cp /tmp/mst.rules /etc/audit/rules.d/mst.rules
rm /tmp/mst.rules

echo "[5/5] Loading audit rules..."
# augenrules compiles all files in /etc/audit/rules.d/ and loads them into the kernel
# This is persistent across reboots, unlike auditctl which only applies rules for the current session
augenrules --load
systemctl restart auditd

echo ""
echo "=========================================="
echo "System Auditing Setup Complete"
echo "=========================================="
echo ""
echo "Audit rules: /etc/audit/rules.d/mst.rules"
echo "Service status: $(systemctl is-active auditd)"
echo ""
