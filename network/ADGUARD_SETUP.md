# AdGuard Home Setup

AdGuard Home v0.107.74 running as an OPNsense plugin.

## Access

| | |
|---|---|
| **Web UI** | `http://192.168.10.1:3000` (MGMT VLAN only) |
| **DNS** | `192.168.1.1:53` (all VLANs) |
| **Credentials** | `$ADGUARD_USER` / `$ADGUARD_PASSWORD` |

> DNS (port 53) is intentionally accessible from all VLANs.
> Web UI (port 3000) is restricted to MGMT VLAN (`192.168.10.0/24`).

## Security Hardening (2026-04-22)

### 1. Web UI bind address
Changed `address` in `/usr/local/AdGuardHome/AdGuardHome.yaml` from `0.0.0.0:3000` to `192.168.10.1:3000`.
AdGuard Home now only serves the web UI on the MGMT VLAN interface.

### 2. Local authentication
Added a dedicated local user to the YAML (`users` section).
Previously `users: []` — the OPNsense plugin passed auth through without any local credentials.
Password is bcrypt-hashed (`auth_attempts: 5`, `block_auth_min: 15`).

### 3. DNS rewrites updated
`adguard.opnsense.internal` and `adguardhome.opnsense.internal` updated from `192.168.1.1` → `192.168.10.1` to match the new bind address.

### 4. Firewall rule — VLAN 30 (opt5)
Added BLOCK rule on opt5 (VLAN 30): `any → 192.168.1.1:3000/tcp`, logging enabled.
Belt-and-suspenders: VLAN 20 (opt4) was already blocked via the `Internal_Networks` alias.

## Config Backup

`network/adguard-backups/AdGuardHome.yaml` — canonical config with credentials redacted.
Restore by copying to `/usr/local/AdGuardHome/AdGuardHome.yaml` and filling in real credentials, then `service adguardhome restart`.

## Install Directory (OPNsense)

```
/usr/local/AdGuardHome/
├── AdGuardHome          # binary
├── AdGuardHome.yaml     # config
├── agh-backup/          # plugin-managed backup snapshot
└── data/
    ├── filters/         # cached filter lists (auto-redownloaded)
    ├── querylog.json    # query log (rolling)
    ├── sessions.db      # auth sessions
    └── stats.db         # statistics
```

## Filter Lists (active)

| Name | Purpose |
|---|---|
| AdGuard DNS filter | Core ad/tracker blocking |
| AdGuard DNS Popup Hosts filter | Popup domains |
| HaGeZi's Pro / Pro++ / Ultimate | Tiered ad+tracker blocking |
| OISD Blocklist Big | Broad ad/tracker/malware |
| HaGeZi's Threat Intelligence Feeds | Threat intel |
| Malicious URL Blocklist (URLHaus) | Malware URLs |
| HaGeZi's The World's Most Abused TLDs | Abused TLD blocking |
| uBlock₀ filters – Badware risks | Badware |
| HaGeZi's Encrypted DNS/VPN/TOR/Proxy Bypass | Bypass detection |
| The Big List of Hacked Malware Web Sites | Compromised sites |
| HaGeZi's DynDNS Blocklist | Dynamic DNS abuse |
| Stalkerware Indicators List | Stalkerware |
| HaGeZi's DNS Rebind Protection | DNS rebind attacks |
| ShadowWhisperer's Malware List | Malware |
| Scam Blocklist by DurableNapkin | Scam sites |
| HaGeZi's Badware Hoster Blocklist | Badware hosting |
| Phishing Army | Phishing |
| Dandelion Sprout's Anti-Malware List | Malware |
| NoCoin Filter List | Cryptomining |
| Phishing URL Blocklist (PhishTank/OpenPhish) | Phishing |
| Regional lists (CHN, HUN, IDN, IRN, KOR, TUR, VNM) | Regional ad/tracker blocking |

## Known Gaps

- **No TLS** on the web UI — HTTP only on port 3000. Future task.
- **No TOTP/MFA** — AdGuard Home v0.107.x does not support per-user 2FA when running under the OPNsense plugin auth model. Mitigated by MGMT VLAN restriction + local credentials.
