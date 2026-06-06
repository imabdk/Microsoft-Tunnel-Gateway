#!/bin/bash
#
# Ubuntu UFW Firewall Configuration for Microsoft Tunnel Gateway
# For Ubuntu Server 22.04 LTS / 24.04 LTS
# Configures required inbound ports and enables firewall
#
# Note: This script is Ubuntu-specific (uses UFW)
# Usage: curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/master/setup-firewall-ubuntu.sh | sudo bash
# Custom port: curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/master/setup-firewall-ubuntu.sh | sudo bash -s -- 8443
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

echo "[1/7] Checking UFW installation..."
if ! command -v ufw &> /dev/null; then
    echo "UFW not found. Installing..."
    apt update
    apt install -y ufw
else
    echo "UFW is already installed"
fi

echo "[2/7] Detecting SSH port..."
SSH_PORT=$(grep -E "^Port\s+[0-9]+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
SSH_PORT=${SSH_PORT:-22}
echo "  SSH port: $SSH_PORT"

# Tunnel port: use argument if provided, otherwise default to 443
TUNNEL_PORT=${1:-443}

echo "[3/7] Configuring explicit firewall rules (safety net)..."
echo "  - Allowing TCP $TUNNEL_PORT (Tunnel inbound)"
ufw allow $TUNNEL_PORT/tcp comment 'Microsoft Tunnel TCP' 2>/dev/null || echo "    Rule already exists"

echo "  - Allowing UDP $TUNNEL_PORT (Tunnel inbound)"
ufw allow $TUNNEL_PORT/udp comment 'Microsoft Tunnel UDP' 2>/dev/null || echo "    Rule already exists"

echo "  - Allowing TCP $SSH_PORT (SSH access - always allowed)"
ufw allow $SSH_PORT/tcp comment 'SSH access' 2>/dev/null || echo "    Rule already exists"

echo "[4/7] Discovering mstunnel-server container ports..."
if command -v docker &> /dev/null && docker inspect mstunnel-server &> /dev/null; then
    docker inspect mstunnel-server \
        --format='{{range $port, $bindings := .NetworkSettings.Ports}}{{if $bindings}}{{$port}} {{range $bindings}}{{.HostPort}}{{end}}{{println}}{{end}}{{end}}' \
        | while read -r port_proto host_port; do
            [ -z "$host_port" ] && continue
            proto="${port_proto##*/}"
            echo "  - Allowing $proto $host_port (mstunnel-server)"
            ufw allow "$host_port/$proto" comment 'mstunnel-server (auto)' 2>/dev/null || echo "    Rule already exists"
        done
else
    echo "  Docker not installed or mstunnel-server container not found - skipping"
fi

echo "[5/7] Discovering other externally-listening services..."
# Collect all local IPv4 addresses for matching
LOCAL_IPS=$(hostname --all-ip-addresses 2>/dev/null)

ss --listening --tcp --udp --no-header --numeric --processes 2>/dev/null | while read -r line; do
    proto=$(echo "$line" | awk '{print $1}')
    local_addr=$(echo "$line" | awk '{print $5}')
    proc_info=$(echo "$line" | awk '{print $NF}')

    # Extract port (after last colon) and address (before last colon)
    port="${local_addr##*:}"
    addr="${local_addr%:*}"

    # Only proceed for ports that are externally accessible
    is_external=0
    case "$addr" in
        "0.0.0.0"|"*"|"[::]"|"::") is_external=1 ;;
        *)
            for ip in $LOCAL_IPS; do
                if [ "$addr" = "$ip" ]; then
                    is_external=1
                    break
                fi
            done
            ;;
    esac
    [ "$is_external" -eq 1 ] || continue

    # Map ss protocol to ufw protocol
    case "$proto" in
        tcp) ufw_proto=tcp ;;
        udp) ufw_proto=udp ;;
        *) continue ;;
    esac

    # Skip ports already covered by explicit rules
    if [ "$port" = "$TUNNEL_PORT" ] || [ "$port" = "$SSH_PORT" ]; then
        continue
    fi

    # Extract process name from users:(("name",pid=...,fd=...))
    proc=$(echo "$proc_info" | sed -n 's/.*"\([^"]*\)".*/\1/p')
    # Sanitize: allow only alphanumerics, dash, underscore, dot
    proc=$(echo "$proc" | tr -cd '[:alnum:]._-')
    proc="${proc:-unknown}"

    echo "  - Allowing $ufw_proto $port ($proc)"
    ufw allow "$port/$ufw_proto" comment "auto: $proc" 2>/dev/null || echo "    Rule already exists"
done

echo "[6/7] Setting default policies and enabling firewall..."
ufw default deny incoming
ufw default allow outgoing

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

echo "[7/7] Verifying configuration..."
echo ""
echo "=========================================="
echo "Firewall Configuration Complete"
echo "=========================================="
echo ""
echo "Tunnel port: $TUNNEL_PORT (TCP+UDP)"
echo "SSH port: $SSH_PORT (TCP)"
echo ""
ufw status numbered
echo ""
