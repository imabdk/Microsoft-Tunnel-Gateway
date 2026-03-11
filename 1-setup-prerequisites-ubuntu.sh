#!/bin/bash
#
# Ubuntu Prerequisites Setup for Microsoft Tunnel Gateway
# For Ubuntu Server 22.04 LTS / 24.04 LTS
# Installs system utilities, Docker Engine, and enables IPv4 packet forwarding
#
# Note: This script is Ubuntu/Debian-specific (uses apt and Docker)
# Usage: curl -fsSL https://imab.dk/tunnel/1-setup-prerequisites-ubuntu.sh | sudo bash
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

echo "[1/11] Updating system packages..."
apt update && apt upgrade -y

echo "[2/11] Installing required utilities..."
apt install -y curl wget git nano jq net-tools ca-certificates

echo "[3/11] Adding Docker's official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "[4/11] Adding Docker repository to Apt sources..."
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

echo "[5/11] Updating package lists with Docker repository..."
apt update

echo "[6/11] Installing Docker packages..."
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[7/11] Enabling IPv4 packet forwarding..."
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

echo "[8/11] Verifying Docker installation..."
docker --version
echo ""

echo "[9/11] Testing Docker with hello-world container..."
docker run hello-world
echo "[10/11] Checking system status..."
echo "" 

echo "[11/11] Setup verification..."
echo ""
echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""
echo "System packages: Updated to latest versions"
echo ""
echo "Installed utilities:"
echo "  - jq (JSON processor for mst-readiness tool)"
echo "  - curl, wget (download tools)"
echo "  - git, nano (development tools)"
echo "  - net-tools (network diagnostics)"
echo ""
echo "Docker version installed:"
docker --version
echo ""
echo "Docker service status:"
systemctl status docker --no-pager | head -3
echo ""
echo "IPv4 forwarding status:"
sysctl net.ipv4.ip_forward
echo ""
echo "Optional: Add your user to docker group to run without sudo:"
echo "  sudo usermod -aG docker \$USER"
echo "  (then logout and login again)"
echo ""
echo "Next steps:"
echo "  1. Run mst-readiness tool to verify environment"
echo "  2. Configure firewall (optional but recommended)"
echo "  3. Install system auditing (optional)"
echo ""
