# OPNsense qfeeds and IDS Setup

**Date:** April 22, 2026  
**Status:** ✅ Active — qfeeds rules live on WAN/LAN/VLAN20/VLAN30; IDS (Suricata) running on WAN in detection mode

---

## Overview

This guide records the OPNsense flow for qfeeds-backed firewall rules and IDS enablement.

### Current live state (as of April 22, 2026)

qfeeds `Ingress QFeeds` BLOCK rules are **active** on all internet-facing interfaces:

| Interface | VLAN | Rule Description | Alias | Status |
|-----------|------|-----------------|-------|--------|
| WAN | — | Ingress QFeeds | `__qfeeds_malware_ip` | ✅ Active (configured manually in UI) |
| LAN | — | Ingress QFeeds | `__qfeeds_malware_ip` | ✅ Active (configured manually in UI) |
| opt4 | VLAN 20 (DMZ/Guest) | Ingress QFeeds | `__qfeeds_malware_ip` | ✅ Active (UUID: `51236bb7-16bc-4749-a29e-7e33721605a0`) |
| opt5 | VLAN 30 (Internal) | Ingress QFeeds | `__qfeeds_malware_ip` | ✅ Active (UUID: `8ee0f140-b964-400d-832e-45c656d396d6`) |
| opt6 | VLAN 10 (Management) | — | — | ⏭️ Skipped — internet already fully blocked on this VLAN |

> **Note**: WAN and LAN rules were configured manually via the OPNsense web UI and are **not** visible via the `/api/firewall/filter/searchRule` endpoint. This is a known OPNsense limitation — the API only returns rules in the "Automation" category. The VLAN rules (opt4, opt5) were added via API and are fully queryable.

---

## qfeeds

### Alias used

The qfeeds plugin auto-creates the alias `__qfeeds_malware_ip` (URL table type, populated by the plugin). This is the alias referenced in all `Ingress QFeeds` BLOCK rules.

### Placement

- ✅ WAN — blocks inbound traffic from known malicious IPs
- ✅ LAN — blocks traffic from internal devices to/from malicious IPs
- ✅ VLAN 20 (opt4) — guest/IoT devices blocked from reaching malicious IPs
- ✅ VLAN 30 (opt5) — internal devices blocked from reaching malicious IPs
- ⏭️ VLAN 10 (opt6) — skipped, internet is fully blocked on management VLAN

### Rule ordering

The `Ingress QFeeds` BLOCK rule sits **before** the broad PASS rules on each interface, so threat-feed IPs are dropped before any allow rule can match.

### Verification

Use the API to confirm VLAN rules are visible (WAN/LAN rules are in the UI-only category and won't appear here):

```bash
curl -sk -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  "https://${OPNSENSE_HOST#https://}/api/firewall/filter/searchRule" | \
  jq '.rows[] | select((.description // "") | test("Ingress QFeeds"; "i"))'
```

Expected output: two rules (opt4 and opt5).

> **Known limitation**: WAN and LAN Ingress QFeeds rules are in the OPNsense "non-Automation" category and are **not** returned by the API search endpoint. This is expected behaviour — confirm those via the web UI at Firewall → Rules → WAN / LAN.

---

## IDS (Suricata)

### Current state (as of April 22, 2026)

| Setting | Value |
|---------|-------|
| Status | ✅ **Running** |
| Mode | PCAP live mode (detection-only — **not blocking**) |
| Interface | WAN |
| Rulesets enabled | 21 |

### Enabled rulesets

| Ruleset | Description | Category |
|---------|-------------|----------|
| `abuse.ch.feodotracker.rules` | Feodo Tracker (banking trojan C&C) | Threat intel |
| `abuse.ch.sslblacklist.rules` | SSL Fingerprint Blacklist | Threat intel |
| `abuse.ch.sslipblacklist.rules` | SSL IP Blacklist | Threat intel |
| `abuse.ch.threatfox.rules` | ThreatFox (malware IOC database) | Threat intel |
| `abuse.ch.urlhaus.rules` | URLhaus (malware distribution URLs) | Threat intel |
| `botcc.rules` | ET open Bot C&C | Malware |
| `botcc.portgrouped.rules` | ET open Bot C&C (port-grouped) | Malware |
| `compromised.rules` | ET open known compromised hosts | Threat intel |
| `drop.rules` | ET open Spamhaus DROP list | Threat intel |
| `dshield.rules` | ET open DShield scanner list | Threat intel |
| `emerging-attack_response.rules` | ET open attack responses | Detection |
| `emerging-coinminer.rules` | ET open crypto miners | Malware |
| `emerging-exploit.rules` | ET open exploits | Detection |
| `emerging-exploit_kit.rules` | ET open exploit kits | Detection |
| `emerging-malware.rules` | ET open malware C&C | Malware |
| `emerging-phishing.rules` | ET open phishing | Detection |
| `emerging-shellcode.rules` | ET open shellcode | Detection |
| `emerging-web_client.rules` | ET open web client attacks | Detection |
| `emerging-web_server.rules` | ET open web server attacks | Detection |
| `threatview_CS_c2.rules` | ET open ThreatView C2 tracking | Threat intel |
| `tor.rules` | ET open Tor exit nodes | Detection |

### Safe initial posture (applied)
- ✅ Detection-only mode (PCAP) — no traffic blocking
- ✅ Logging enabled before any blocking mode
- ✅ WAN interface only for initial rollout
- ⏳ Expand to LAN/VLANs after validating noise level

### Common workflow
1. Open **Services → Intrusion Detection**
2. Enable IDS
3. Select the interface(s) to monitor
4. Update rulesets/signatures
5. Review alerts and tune exclusions

### Verification

```bash
# Check service status
curl -sk -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  "https://${OPNSENSE_HOST#https://}/api/ids/service/status" | jq '.status'
# Expected: "running"

# Count enabled rulesets
curl -sk -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  "https://${OPNSENSE_HOST#https://}/api/ids/settings/listRulesets" | \
  jq '[.rows[] | select(.enabled == "1")] | length'
# Expected: 21
```

Alerts appear in **Services → Intrusion Detection → Alerts** in the OPNsense web UI.

---

## Notes

- WAN and LAN rules were set up manually in the OPNsense UI; VLAN 20/30 rules were created via API.
- After exporting the live config, replace the XML backup in `network/`.
- IDS (Suricata) is the next hardening step — see the IDS section above.
