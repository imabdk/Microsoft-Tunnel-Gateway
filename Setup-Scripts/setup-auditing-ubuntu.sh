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

echo "[1/5] Checking current auditd state..."
if [ -f "/etc/audit/rules.d/mst.rules" ]; then
    echo "  Microsoft Tunnel audit rules already present - will re-download and re-apply"
else
    echo "  No existing audit rules found - proceeding with fresh install"
fi

echo "[2/5] Installing auditd and plugins..."
apt update
apt install -y auditd audispd-plugins

echo "[3/5] Downloading Microsoft Tunnel audit rules..."
# aka.ms/TunnelAuditdRules is the official Microsoft short link for the Tunnel auditd rules
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
# NOTE: The Tunnel audit rules reference paths under /etc/mstunnel which only exist after mstunnel-setup
# has been run. If loading fails here, run: sudo augenrules --load && sudo systemctl restart auditd
# after the Tunnel installation is complete.
if [ -d "/etc/mstunnel" ]; then
    augenrules --load
    systemctl restart auditd
else
    echo "  WARNING: /etc/mstunnel does not exist - Microsoft Tunnel is not yet installed"
    echo "  Audit rules have been installed to /etc/audit/rules.d/mst.rules but not loaded"
    echo "  After running mstunnel-setup, load the rules with:"
    echo "    sudo augenrules --load && sudo systemctl restart auditd"
fi

echo ""
echo "=========================================="
echo "System Auditing Setup Complete"
echo "=========================================="
echo ""
echo "Audit rules: /etc/audit/rules.d/mst.rules"
echo "Service status: $(systemctl is-active auditd)"
echo ""
