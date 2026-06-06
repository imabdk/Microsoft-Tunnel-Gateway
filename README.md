# Microsoft Tunnel Gateway Scripts

Scripts I use for deploying and managing Microsoft Tunnel Gateway servers.

## Scripts

### Health Check

- `mst-health.sh` - Post-installation health validation with detailed issue reporting (service/container health, configuration sync, certificates, logs, ports)

### Setup

- `setup-prerequisites-ubuntu.sh` - System prerequisites and package installation (Ubuntu)
- `setup-auditing-ubuntu.sh` - Configure audit logging (Ubuntu)
- `setup-firewall-ubuntu.sh` - Firewall configuration (Ubuntu)

## Compatibility

**Ubuntu:** Setup scripts are designed for Ubuntu Server 22.04 LTS / 24.04 LTS  
**RHEL:** Scripts for RHEL coming soon

## Usage

### Health check

```bash
curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/main/mst-health.sh | sudo bash
```

Or download and run locally:

```bash
sudo bash ./mst-health.sh
```

### Setup scripts

```bash
curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/master/Setup-Scripts/setup-prerequisites-ubuntu.sh | sudo bash
curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/master/Setup-Scripts/setup-auditing-ubuntu.sh | sudo bash
curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/master/Setup-Scripts/setup-firewall-ubuntu.sh | sudo bash
```

Or download and run locally:

```bash
sudo bash ./Setup-Scripts/setup-prerequisites-ubuntu.sh
sudo bash ./Setup-Scripts/setup-auditing-ubuntu.sh
sudo bash ./Setup-Scripts/setup-firewall-ubuntu.sh
```

## More Information

Blog series: [10 days and 10 tips for Microsoft Tunnel Gateway](https://www.imab.dk/10-days-and-10-tips-for-microsoft-tunnel-gateway/)
