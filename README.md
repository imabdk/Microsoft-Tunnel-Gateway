# Microsoft Tunnel Gateway Scripts

Automation scripts for deploying and managing Microsoft Tunnel Gateway on Ubuntu.

## Scripts

- `setup-prerequisites-ubuntu.sh` - System prerequisites and package installation (Ubuntu)
- `setup-auditing-ubuntu.sh` - Configure audit logging (Ubuntu)
- `setup-firewall-ubuntu.sh` - Firewall configuration (Ubuntu)
- `mst-readiness.sh` - Pre-installation readiness checks
- `mst-mindcore-health.sh` - Health monitoring
- `mst-mindcore-net-diag.sh` - Network diagnostics

## Compatibility

**Ubuntu/Debian:** Setup scripts are designed for Ubuntu Server 22.04 LTS / 24.04 LTS
**RHEL/Rocky Linux:** Not supported by these scripts (uses different package manager and Podman)

## Usage

```bash
sudo bash ./scriptname.sh
```

## Documentation

Full deployment guides available at [imab.dk](https://www.imab.dk)

## Author

Martin Bengtsson - Mindcore
