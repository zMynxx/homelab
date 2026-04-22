# Firewall Rules Configuration

**Last Updated**: April 21, 2026  
**Status**: ✅ Complete - All VLAN firewall rules configured and active

---

## Overview

This document describes the complete firewall rule matrix for all VLANs in the homelab network. Rules are configured on OPNsense using the JSON API and enforce network segmentation, isolation, and access control.

### Security Model

- **Defense in Depth**: Multiple layers of security (wireless isolation + VLAN segmentation + firewall rules)
- **Least Privilege**: Each VLAN has minimum required access
- **Zero Trust DMZ**: Guest/DMZ network has no access to internal resources
- **Management Isolation**: Management VLAN blocked from internet to reduce attack surface

---

## Firewall Rule Matrix

### VLAN 10 - Management (opt6 - 192.168.10.0/24)

**Purpose**: Administrative access to network infrastructure (switches, APs, IPMI)  
**Internet Access**: ❌ **BLOCKED** (security hardening)  
**Strategy**: Allow infrastructure access only, block all outbound internet

| Seq | Action | Protocol | Source | Destination | Port | Description |
|-----|--------|----------|--------|-------------|------|-------------|
| 1 | ✅ PASS | TCP | opt6 net | (self) | 443 | Allow HTTPS to OPNsense web UI |
| 2 | ✅ PASS | TCP/UDP | opt6 net | (self) | 53 | Allow DNS to OPNsense |
| 3 | ✅ PASS | any | opt6 net | Internal_Networks | any | Allow management access to internal networks (LAN, VLAN 30) |
| 4 | 🚫 BLOCK | any | opt6 net | DMZ_Network | any | Block management access to DMZ/Guest network |
| 5 | 🚫 BLOCK | any | opt6 net | any | any | Block internet access from management VLAN |

**Allowed Access**:
- ✅ OPNsense web UI (https://192.168.10.1:443, 192.168.1.1:8443)
- ✅ DNS resolution via OPNsense
- ✅ Legacy LAN (192.168.1.x) - switches, APs, existing devices
- ✅ Internal VLAN (192.168.30.x) - Talos cluster, servers
- ✅ Management VLAN (192.168.10.x) - peer devices (SSH, IPMI, etc.)

**Blocked Access**:
- ❌ Internet (all outbound traffic)
- ❌ DMZ/Guest VLAN (192.168.20.x)

**Use Cases**:
- Administer OPNsense firewall
- Manage switches and access points
- SSH to servers and infrastructure
- Access IPMI/BMC for hardware management
- Monitor internal network devices

---

### VLAN 20 - DMZ/Guest (opt4 - 192.168.20.0/24)

**Purpose**: Guest Wi-Fi, IoT devices, isolated untrusted devices  
**Internet Access**: ✅ **ALLOWED**  
**Strategy**: Full isolation from internal networks, internet-only access

| Seq | Action | Protocol | Source | Destination | Port | Description |
|-----|--------|----------|--------|-------------|------|-------------|
| 1 | 🚫 BLOCK | any | opt4 net | Internal_Networks | any | Block guest access to LAN and internal VLANs |
| 2 | ✅ PASS | any | opt4 net | any | any | Allow guest internet access and gateway communication |

**Allowed Access**:
- ✅ Internet (all protocols)
- ✅ Gateway (192.168.20.1) for DHCP, DNS, routing
- ✅ DNS via OPNsense (port 53)

**Blocked Access**:
- ❌ Legacy LAN (192.168.1.x)
- ❌ Management VLAN (192.168.10.x)
- ❌ Internal VLAN (192.168.30.x)
- ❌ Other guest devices (wireless client isolation on Ruckus AP)

**Additional Security**:
- Wireless client isolation enabled (Ruckus R720 setting)
- AllowList "Guest-Internet-Access" permits gateway/DHCP only
- WPA2-PSK with rotating password (monthly)

**Use Cases**:
- Guest Wi-Fi for visitors
- IoT devices (smart home, cameras)
- Untrusted devices requiring internet only
- Testing/quarantine network

---

### VLAN 30 - Internal (opt5 - 192.168.30.0/24)

**Purpose**: Trusted internal devices (Talos cluster, workstations, servers)  
**Internet Access**: ✅ **ALLOWED**  
**Strategy**: Full internal access, internet access, isolated from DMZ

| Seq | Action | Protocol | Source | Destination | Port | Description |
|-----|--------|----------|--------|-------------|------|-------------|
| 1 | ✅ PASS | TCP/UDP | opt5 net | (self) | 53 | Allow DNS to OPNsense |
| 2 | ✅ PASS | any | opt5 net | Management_Network | any | Allow access to management VLAN |
| 3 | ✅ PASS | any | opt5 net | lan | any | Allow access to legacy LAN (migration period) |
| 4 | 🚫 BLOCK | any | opt5 net | DMZ_Network | any | Block access to DMZ/Guest network |
| 5 | ✅ PASS | any | opt5 net | any | any | Allow internet access |

**Allowed Access**:
- ✅ Internet (all protocols)
- ✅ DNS via OPNsense
- ✅ Management VLAN (192.168.10.x) - access switches, APs, infrastructure
- ✅ Legacy LAN (192.168.1.x) - during migration period
- ✅ Internal VLAN (192.168.30.x) - peer devices (Kubernetes, NFS, etc.)

**Blocked Access**:
- ❌ DMZ/Guest VLAN (192.168.20.x)

**Use Cases**:
- Kubernetes cluster nodes (Talos)
- Development workstations
- Internal services (databases, file servers)
- Admin laptops (trusted devices)
- CI/CD runners

---

## Firewall Aliases

### Network Aliases

| Alias Name | Type | Content | Description |
|------------|------|---------|-------------|
| **Internal_Networks** | network | 192.168.1.0/24<br>192.168.10.0/24<br>192.168.30.0/24 | Internal networks to protect from guest VLAN |
| **DMZ_Network** | network | 192.168.20.0/24 | DMZ/Guest VLAN - isolated network |
| **Management_Network** | network | 192.168.10.0/24 | Management VLAN - infrastructure devices |
| **RFC1918_Private** | network | 192.168.0.0/16<br>10.0.0.0/8<br>172.16.0.0/12 | All RFC1918 private networks (not actively used) |

### Port Aliases

| Alias Name | Type | Content | Description |
|------------|------|---------|-------------|
| **OPNsense_WebUI** | port | 443<br>8443 | OPNsense web UI ports (HTTPS) |

### Special Aliases (Auto-Generated)

| Alias Name | Type | Description |
|------------|------|-------------|
| **__lan_network** | internal | Legacy LAN network (192.168.1.0/24) |
| **__opt4_network** | internal | VLAN 20 network (192.168.20.0/24) |
| **__opt5_network** | internal | VLAN 30 network (192.168.30.0/24) |
| **__opt6_network** | internal | VLAN 10 network (192.168.10.0/24) |

---

## Access Control Matrix

### Inter-VLAN Communication

| From ↓ / To → | LAN<br>(192.168.1.x) | VLAN 10<br>Management | VLAN 20<br>DMZ/Guest | VLAN 30<br>Internal | Internet | OPNsense UI |
|---------------|----------------------|-----------------------|----------------------|---------------------|----------|-------------|
| **LAN** (192.168.1.x) | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes |
| **VLAN 10** (Management) | ✅ Yes | ✅ Yes | ❌ **BLOCKED** | ✅ Yes | ❌ **BLOCKED** | ✅ Yes |
| **VLAN 20** (DMZ/Guest) | ❌ **BLOCKED** | ❌ **BLOCKED** | ❌ **ISOLATED** | ❌ **BLOCKED** | ✅ Yes | ❌ No |
| **VLAN 30** (Internal) | ✅ Yes | ✅ Yes | ❌ **BLOCKED** | ✅ Yes | ✅ Yes | ✅ Yes |

**Legend**:
- ✅ **Yes** - Traffic allowed
- ❌ **BLOCKED** - Traffic blocked by firewall rule
- ❌ **ISOLATED** - Traffic blocked by wireless client isolation (Ruckus AP)

**Notes**:
- Legacy LAN (192.168.1.x) has full access during migration period
- Guest VLAN has wireless client isolation enabled - guests cannot communicate with each other
- Management VLAN intentionally blocked from internet to reduce attack surface
- DMZ/Guest VLAN fully isolated from all internal resources

---

## Service Access Matrix

### Common Services

| Service | Port | VLAN 10<br>Management | VLAN 20<br>DMZ/Guest | VLAN 30<br>Internal |
|---------|------|-----------------------|----------------------|---------------------|
| **DNS** | 53 UDP/TCP | ✅ OPNsense | ✅ OPNsense | ✅ OPNsense |
| **DHCP** | 67/68 UDP | ✅ Auto | ✅ Auto | ✅ Auto |
| **HTTPS (OPNsense)** | 443, 8443 | ✅ Yes | ❌ No | ✅ Yes |
| **SSH** | 22 | ✅ Internal only | ❌ No | ✅ Internal only |
| **HTTP/HTTPS** | 80/443 | ❌ **BLOCKED** | ✅ Internet | ✅ Internet |
| **NTP** | 123 UDP | ❌ **BLOCKED** | ✅ Internet | ✅ Internet |
| **Kubernetes API** | 6443 | ✅ VLAN 30 | ❌ No | ✅ VLAN 30 |

---

## Rule Ordering and Processing

### Rule Evaluation Order

OPNsense firewall rules are evaluated **top-to-bottom** with **first-match-wins** logic (due to `quick` flag on all rules):

1. Rules are checked sequentially by sequence number
2. First matching rule is applied immediately (quick mode)
3. Subsequent rules are not evaluated for that packet
4. Default policy: **BLOCK** (implicit deny at end)

### Best Practices Applied

- ✅ **Specific rules first** (DNS, web UI access) before broad rules
- ✅ **Block rules before allow** where needed (Management → DMZ before Management → Internet)
- ✅ **Logging enabled on BLOCK rules** for security monitoring
- ✅ **Logging disabled on PASS rules** to reduce noise
- ✅ **Explicit deny-all** as last rule where appropriate

---

## Security Considerations

### Defense in Depth Layers

1. **Layer 1 - Physical**: VLAN trunking on managed switch
2. **Layer 2 - Wireless**: Client isolation on Ruckus AP (guest SSID)
3. **Layer 3 - Network**: VLAN segmentation (802.1Q tagging)
4. **Layer 4 - Firewall**: Per-VLAN firewall rules (this document)

### Threat Model Addressed

**Guest/IoT Compromise**:
- ✅ Guest VLAN fully isolated from internal networks
- ✅ No lateral movement possible (blocked by firewall + wireless isolation)
- ✅ Internet-only access prevents internal reconnaissance

**Management Device Compromise**:
- ✅ Management VLAN blocked from internet (reduces attack surface)
- ✅ Cannot exfiltrate data to internet
- ✅ Can still administer internal infrastructure
- ✅ Blocked from accessing DMZ (prevent pivot to compromised guests)

**Internal Device Compromise**:
- ✅ Cannot access guest network (prevent pivot to IoT)
- ✅ Can access management for legitimate admin tasks
- ✅ Internet access for updates and operations

### Logging and Monitoring

**Logged Events**:
- ❌ BLOCK rules: sequence 1 (opt4), sequence 4 (opt5), sequence 4-5 (opt6)
- ✅ PASS rules: Logging disabled to reduce log volume

**Recommended Monitoring**:
- Check `Firewall → Log Files → Live View` for blocked traffic
- Filter by interface (opt4, opt5, opt6) to see VLAN-specific blocks
- Alert on unusual block patterns (potential security incidents)
- Monitor rule hit counters in `Firewall → Rules → [Interface]`

---

## Testing and Verification

### Test Plan

See [VLAN_COMPLETION_GUIDE.md](./VLAN_COMPLETION_GUIDE.md#verification--testing) for complete test procedures.

**Quick Verification**:

```bash
# From VLAN 20 (Guest) device:
ping 192.168.1.1      # Should FAIL (blocked)
ping 192.168.10.1     # Should FAIL (blocked)
ping 192.168.30.1     # Should FAIL (blocked)
ping 8.8.8.8          # Should WORK (internet allowed)

# From VLAN 30 (Internal) device:
ping 192.168.10.1     # Should WORK (management allowed)
ping 192.168.1.1      # Should WORK (LAN allowed)
ping 192.168.20.1     # Should FAIL (DMZ blocked)
ping 8.8.8.8          # Should WORK (internet allowed)

# From VLAN 10 (Management) device:
ping 192.168.30.1     # Should WORK (internal allowed)
ping 192.168.1.1      # Should WORK (LAN allowed)
ping 192.168.20.1     # Should FAIL (DMZ blocked)
ping 8.8.8.8          # Should FAIL (internet blocked)
curl https://192.168.10.1  # Should WORK (OPNsense UI)
```

### Firewall State Verification

```bash
# Via OPNsense API:
curl -k -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  "https://firewall.opnsense.internal:8443/api/diagnostics/firewall/pf_states" | \
  jq '.rows | .[] | select(.src | contains("192.168.20"))'

# Should see states for internet traffic, no states for internal networks
```

---

## Troubleshooting

### Common Issues

**Issue**: Management VLAN cannot access OPNsense web UI  
**Cause**: Rule 1 (HTTPS) or Rule 2 (DNS) missing/disabled  
**Fix**: Verify rules with sequence 1-2 exist on opt6 interface

**Issue**: Internal VLAN cannot access management devices  
**Cause**: Rule 2 on opt5 missing/disabled  
**Fix**: Verify "Allow access to management VLAN" rule exists on opt5

**Issue**: Guest network can access internal networks  
**Cause**: Rule 1 on opt4 missing/disabled or alias incorrect  
**Fix**: Verify `Internal_Networks` alias contains 192.168.1.0/24, 192.168.10.0/24, 192.168.30.0/24

**Issue**: Firewall rules not taking effect  
**Cause**: Rules not applied after creation  
**Fix**: Run `/api/firewall/filter/apply` via API or click "Apply Changes" in web UI

### Debug Commands

```bash
# List all firewall rules for a VLAN:
curl -k -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  "https://firewall.opnsense.internal:8443/api/firewall/filter/searchRule" | \
  jq '.rows | map(select(.interface == "opt4"))'

# Check firewall aliases:
curl -k -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  "https://firewall.opnsense.internal:8443/api/firewall/alias/searchItem" | \
  jq '.rows | .[] | {name, content}'

# View firewall logs (live):
# Navigate to Firewall → Log Files → Live View in web UI
# Filter by interface: opt4, opt5, or opt6
```

---

## Future Enhancements

### Planned Additions

1. **IPS/IDS Integration** (Suricata/Snort)
   - Enable on guest VLAN (opt4) to detect malicious traffic
   - Signature-based detection for known threats
   - Anomaly detection for zero-day threats

2. **Bandwidth Limiting** (Traffic Shaping)
   - Limit guest VLAN bandwidth to prevent DoS
   - QoS for internal VLAN (prioritize Kubernetes traffic)

3. **Geo-Blocking** (MaxMind GeoIP)
   - Block guest VLAN access from high-risk countries
   - Already configured: `GeoIPBlock_CN_RU_US` alias

4. **Time-Based Rules**
   - Restrict guest Wi-Fi to business hours
   - Maintenance windows for management VLAN

5. **VPN Access**
   - WireGuard tunnel to management VLAN for remote admin
   - IPsec site-to-site for branch offices

---

## API Configuration Reference

### Creating Firewall Rules via API

```bash
# Example: Create a PASS rule
curl -k -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  "https://firewall.opnsense.internal:8443/api/firewall/filter/addRule" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "rule": {
      "enabled": "1",
      "sequence": "1",
      "action": "pass",
      "interface": "opt4",
      "ipprotocol": "inet",
      "protocol": "tcp",
      "source_net": "opt4",
      "destination_net": "any",
      "destination_port": "443",
      "description": "Allow HTTPS",
      "log": "0"
    }
  }'

# Apply rules
curl -k -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  "https://firewall.opnsense.internal:8443/api/firewall/filter/apply" \
  -X POST
```

### Creating Firewall Aliases via API

```bash
# Example: Create a network alias
curl -k -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  "https://firewall.opnsense.internal:8443/api/firewall/alias/addItem" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "alias": {
      "enabled": "1",
      "name": "MyNetwork",
      "type": "network",
      "content": "192.168.10.0/24\n192.168.20.0/24",
      "description": "My custom network alias"
    }
  }'

# Apply aliases
curl -k -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
  "https://firewall.opnsense.internal:8443/api/firewall/alias/reconfigure" \
  -X POST
```

---

## Related Documentation

- [VLAN Configuration Guide](./VLAN_COMPLETION_GUIDE.md) - Complete VLAN setup instructions
- [VLAN Implementation Summary](./VLAN_IMPLEMENTATION_SUMMARY.md) - Project completion record
- [Network Architecture](./NETWORK_SETUP.md) - Overall network design and topology
- [OPNsense API Documentation](https://docs.opnsense.org/development/api.html) - Official API reference

---

**Document Status**: ✅ Complete and accurate as of April 21, 2026  
**Last Verified**: All rules confirmed active via API query  
**Configuration Applied**: All changes applied and operational
