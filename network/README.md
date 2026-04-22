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

## Hardening

- ✅ VLAN segmentation (Management / DMZ / Internal)
- ✅ 2FA on OPNsense
- ✅ SSH key-based access
- ✅ Threat feeds (q-feeds) — `Ingress QFeeds` BLOCK rules active on WAN, LAN, VLAN 20, VLAN 30
- ✅ IDS (Suricata) — detection mode on WAN, 21 rulesets (ET Open + abuse.ch)

## Planned Features

- ⏳ IPS/IDS (Suricata)
- ⏳ HAProxy reverse proxy
- ⏳ VPN (WireGuard/IPsec)

See [QFEEDS_IDS_SETUP.md](./QFEEDS_IDS_SETUP.md) for the firewall-side setup guide and verification checklist.

## Configuration

Legacy Terraform configuration available in `../old/terraform-opnsense/` for reference. Future automation to be implemented using:
- OPNsense API
- Ansible/Terraform modules
- GitOps workflows

---

**Status**: Active configuration, automation migration in progress
