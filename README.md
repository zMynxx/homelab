# Homelab Infrastructure

Declarative, reproducible homelab infrastructure - network, compute, and GitOps-managed services.

## Repository Structure

```
homelab/
├── network/          # Network infrastructure (OPNsense firewall/router)
├── infra/            # Physical infrastructure (TuringPi2 Talos cluster)
├── gitops/           # ArgoCD-managed Kubernetes applications
└── old/              # Legacy configurations (Terraform, Ansible, Proxmox)
```

### 📡 Network (`network/`)
- OPNsense firewall/router configuration (planned)
- Multi-VLAN segmentation
- HAProxy reverse proxy
- DNS, DHCP, firewall rules

### 🏗️ Infrastructure (`infra/`)
- **Kubernetes**: Talos Linux cluster on TuringPi2 (3x RK1 ARM64)
- **PKI**: Step-CA certificate authority (tinyca on Raspberry Pi)
- **Documentation**: Architecture and design decisions

### 🚀 GitOps (`gitops/`)
- ArgoCD-managed applications (planned)
- SOPS-encrypted secrets
- Declarative cluster state

### 📦 Old (`old/`)
- Legacy Terraform configurations (mgmt, truenas, ubuntu, opnsense)
- Ansible playbooks (hardware initialization, passthrough)
- Proxmox configurator script
- Kept for reference during migration

## Quick Start

See individual directory READMEs for detailed setup instructions:
- [Network Setup](network/README.md)
- [Infrastructure Setup](infra/README.md)
- [GitOps Workflow](gitops/README.md)

## Architecture

Refer to `infra/docs/ARCHITECTURE.md` for the complete design document.

## License

See [LICENSE](LICENSE)