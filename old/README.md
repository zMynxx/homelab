# Legacy Configurations

This directory contains previous infrastructure automation that is not currently in use but kept for reference during migration.

## Contents

### Terraform Modules
- **terraform-mgmt/** - Management infrastructure
- **terraform-opnsense/** - OPNsense firewall/router
- **terraform-truenas/** - TrueNAS storage appliance
- **terraform-ubuntu/** - Ubuntu VM provisioning

### Ansible Playbooks
- **Ansible/00-Init/** - Initial hardware/VM setup
- **Ansible/01-Passthrough/** - PCIe passthrough configuration

### Scripts
- **proxmox-configurator.sh** - Proxmox hypervisor setup script
- **OPNsense.opnsense.internal_zMynx_apikey.secret** - OPNsense API key

## Migration Status

These configurations are being replaced with:
- **Network**: Modern OPNsense automation (to be implemented in `../network/`)
- **Infrastructure**: Talos-native cluster configuration (`../infra/talos/`)
- **GitOps**: ArgoCD-managed services (`../gitops/`)

## Retention

Kept for historical reference and to aid in understanding previous architecture decisions. May be removed once migration is complete and validated.
