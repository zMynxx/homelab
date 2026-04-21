# Network Infrastructure

OPNsense firewall/router configuration and network automation for the homelab.

## Current Setup

**OPNsense** serves as the primary firewall/router with:
- **Network**: 192.168.1.1/16 (behind ISP router)
- **DNS**: AdGuard Home + Unbound with DNS over TLS
- **Security**: GeoBlocking (MaxMind), 2FA, firewall rules
- **Ad Blocking**: AdGuard Home with custom blocklists

See [NETWORK_SETUP.md](./NETWORK_SETUP.md) for complete network architecture documentation.

## VLAN Architecture

| VLAN | Purpose | Subnet | DHCP Range | Gateway |
|------|---------|--------|------------|---------|
| 10 | Management | 192.168.10.0/24 | .100-.200 | 192.168.10.1 |
| 20 | DMZ (Public) | 192.168.20.0/24 | .100-.200 | 192.168.20.1 |
| 30 | Internal Apps | 192.168.30.0/24 | .100-.200 | 192.168.30.1 |

## Planned Features

- ⏳ IPS/IDS (Suricata/Snort)
- ⏳ Threat feeds (q-feeds)
- ⏳ HAProxy reverse proxy
- ⏳ VPN (WireGuard/IPsec)

## Configuration

Legacy Terraform configuration available in `../old/terraform-opnsense/` for reference. Future automation to be implemented using:
- OPNsense API
- Ansible/Terraform modules
- GitOps workflows

---

**Status**: Active configuration, automation migration in progress
