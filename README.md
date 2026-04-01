# Microsoft Tunnel Gateway Scripts

Automation scripts for deploying and managing Microsoft Tunnel Gateway.

## Scripts

### Health Check

- `mst-health.sh` - Post-installation health validation (service status, containers, certificates, logs, configuration, ports, connectivity)

### Setup

- `setup-prerequisites-ubuntu.sh` - System prerequisites and package installation (Ubuntu)
- `setup-auditing-ubuntu.sh` - Configure audit logging (Ubuntu)
- `setup-firewall-ubuntu.sh` - Firewall configuration (Ubuntu)

## Compatibility

**Ubuntu:** Setup scripts are designed for Ubuntu Server 22.04 LTS / 24.04 LTS  
**RHEL:** Scripts for RHEL coming soon

## Usage

### Health check (run on tunnel server)

```bash
curl -fsSL https://raw.githubusercontent.com/imabdk/Microsoft-Tunnel-Gateway/main/mst-health.sh | sudo bash
```

Or download and run locally:

```bash
sudo bash ./mst-health.sh
```

### Setup scripts

```bash
sudo bash ./setup-prerequisites-ubuntu.sh
sudo bash ./setup-auditing-ubuntu.sh
sudo bash ./setup-firewall-ubuntu.sh
```

## More Information

Read the blog post: [10 days and 10 tips for Microsoft Tunnel Gateway - Day 3](https://www.imab.dk/10-days-and-10-tips-for-microsoft-tunnel-gateway-day-3/)

## Author

Martin Bengtsson - Mindcore
