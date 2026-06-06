#!/bin/bash
#
# Ubuntu Prerequisites Setup for Microsoft Tunnel Gateway
# For Ubuntu Server 22.04 LTS / 24.04 LTS
# Installs system utilities, Docker Engine, and enables IPv4 packet forwarding
#
# Note: This script is Ubuntu-specific (uses apt and Docker)
# Usage: curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/master/Setup%20scripts/setup-prerequisites-ubuntu.sh | sudo bash
#

set -e

echo "=========================================="
echo "Microsoft Tunnel Gateway Prerequisites"
echo "Ubuntu Server Setup"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

echo "[1/6] Updating system packages..."
apt update && apt upgrade -y

echo "[2/6] Installing required utilities..."
# jq is required by mst-readiness, others are for convenience
apt install -y curl wget git nano jq net-tools ca-certificates

echo "[3/6] Installing Docker Engine..."
if command -v docker &> /dev/null; then
    echo "  Docker is already installed: $(docker --version)"
    echo "  Skipping Docker installation"
else
    echo "  Adding Docker's official GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "  Adding Docker repository to Apt sources..."
    tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    echo "  Updating package lists..."
    apt update

    echo "  Installing Docker packages..."
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

echo "[4/6] Enabling IPv4 packet forwarding..."
# Check if already enabled
CURRENT_FORWARD=$(sysctl -n net.ipv4.ip_forward)
if [ "$CURRENT_FORWARD" -eq 1 ]; then
    echo "  IPv4 forwarding is already enabled"
else
    echo "  Enabling IPv4 forwarding in /etc/sysctl.conf"
    # Uncomment or add the line
    if grep -q "^#net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    elif grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "  Already configured in sysctl.conf"
    else
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -p > /dev/null
    echo "  IPv4 forwarding enabled"
fi

echo "[5/6] Verifying Docker installation..."
docker --version

echo "[6/6] Setup verification..."
echo ""
echo "=========================================="
echo "Prerequisites Setup Complete"
echo "=========================================="
echo ""
echo "Docker: $(docker --version 2>/dev/null || echo 'NOT INSTALLED')"
echo "IPv4 forwarding: $(sysctl -n net.ipv4.ip_forward)"
echo ""
