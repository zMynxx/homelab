# Management Interface Access Security

**Last Updated**: April 21, 2026  
**Security Policy**: Zero Trust - Management interfaces accessible ONLY from Management VLAN

---

## Security Principle

**Management interfaces should be isolated from production networks.**

Following security best practices and Zero Trust principles:
- Management interfaces (web UI, SSH, API) accessible **only** from dedicated Management VLAN
- Production VLANs (Internal, DMZ/Guest) **cannot** access management interfaces
- Multi-layered security: Interface restriction + Firewall rules + Network segmentation

---

## Management Interfaces Inventory

### OPNsense Firewall
- **Management IP**: 192.168.10.1
- **Web UI**: HTTPS on port 443 (configurable)
- **SSH**: Port 22 (if enabled)
- **API**: HTTPS on port 443
- **Access Restriction**: Listen only on opt6 (VLAN10_Management)

### Ruckus R720 Access Point
- **Management IP**: 192.168.10.10 (migrated from 192.168.1.11)
- **Web UI**: HTTP/HTTPS
- **SSH**: Ports 22, 8022
- **Management VLAN**: VLAN 10 (untagged for management interface)
- **Access Restriction**: Management VLAN ID set to 10 in Ruckus configuration

### TinyCA (Step-CA)
- **Management IP**: 192.168.10.37 (planned migration from 192.168.1.37)
- **Web UI**: HTTPS on port 9000 (example)
- **API**: HTTPS
- **Access Restriction**: Network-level (only accessible from Management VLAN)

### UniFi USW-Flex Switch (Planned)
- **Management IP**: 192.168.10.11 (planned)
- **Web UI**: HTTPS
- **SSH**: Port 22
- **Access Restriction**: Native VLAN 10 for management

---

## Security Controls

### Layer 1: Interface-Level Restriction

**OPNsense Web UI:**
- Configuration: **System → Settings → Administration → Listen Interfaces**
- Setting: **ONLY `opt6` (VLAN10_Management)** selected
- Effect: Web UI daemon only binds to 192.168.10.1, refuses connections on other IPs
- **Status**: ⏳ User action required (web UI configuration)

**Ruckus AP:**
- Configuration: **Technology → VLANs → Management VLAN ID**
- Setting: **VLAN ID = 10**
- Static IP: 192.168.10.10/24, Gateway 192.168.10.1
- Effect: Management interface operates on VLAN 10 only
- **Status**: ⏳ Planned migration (see migration plan below)

---

### Layer 2: Firewall Rules

**VLAN 10 (Management) - Allowed Services:**
```
Rule 1: PASS port 443 to OPNsense (web UI)
Rule 2: PASS port 53 to OPNsense (DNS)
Rule 3: PASS to Internal_Networks (for managing internal devices)
Rule 4: BLOCK to DMZ_Network
Rule 5: BLOCK to any (internet)
```

**VLAN 30 (Internal) - Management Access:**
```
Rule 1: PASS port 53 to OPNsense (DNS only)
Rule 2: PASS to Management_Network (general access, but web UI won't respond due to Layer 1 restriction)
Rule 3: PASS to LAN
Rule 4: BLOCK to DMZ_Network
Rule 5: PASS to any (internet)
```

**Note**: VLAN 30 Rule 2 allows reaching 192.168.10.x for future management services (monitoring, logging, etc.), but OPNsense web UI won't respond due to interface-level restriction (defense in depth).

**VLAN 20 (DMZ/Guest) - No Management Access:**
```
Rule 1: BLOCK to Internal_Networks (includes 192.168.10.x management)
Rule 2: PASS to any (internet only)
```

---

### Layer 3: Network Segmentation

**Management VLAN (10):**
- Isolated from production traffic
- No internet access (hardened)
- Can access internal networks for management purposes
- Cannot access DMZ/Guest network

**Physical Segmentation:**
- Dedicated SSID: "Homelab-Mgmt" → VLAN 10
- Managed switch ports configured with native VLAN 10 (when UniFi switch deployed)

---

## Access Control Matrix

| From VLAN ↓ / To → | OPNsense Web UI (10.1:443) | Ruckus AP (10.10:80) | TinyCA (10.37) | UniFi Switch (10.11) |
|---------------------|----------------------------|----------------------|----------------|----------------------|
| **Management (10)** | ✅ **ALLOWED**             | ✅ **ALLOWED**       | ✅ **ALLOWED** | ✅ **ALLOWED**       |
| **DMZ/Guest (20)**  | ❌ **BLOCKED**             | ❌ **BLOCKED**       | ❌ **BLOCKED** | ❌ **BLOCKED**       |
| **Internal (30)**   | ❌ **BLOCKED** (Layer 1)   | ✅ **ALLOWED**       | ✅ **ALLOWED** | ✅ **ALLOWED**       |
| **Legacy LAN (1)**  | ❌ **BLOCKED** (Layer 1)   | ❌ **BLOCKED** (after migration) | ⏳ Pending migration | ⏳ Pending deployment |

**Notes:**
- OPNsense web UI blocked from Internal/Legacy via **interface restriction** (Layer 1), even though firewall rules allow reaching 192.168.10.1
- Internal VLAN can access other management devices (AP, TinyCA, switch) for operational purposes
- Guest/DMZ completely isolated from all management interfaces

---

## Implementation Status

### ✅ Completed
- [x] Created Management VLAN (VLAN 10) with 192.168.10.0/24 subnet
- [x] Configured DHCP on Management VLAN (.100-.200 range)
- [x] Created "Homelab-Mgmt" SSID with VLAN 10 tagging
- [x] Configured firewall rules for Management VLAN access control
- [x] Documented security architecture and access controls

### ⏳ User Action Required
1. **Restrict OPNsense Web UI listening interface**:
   - Navigate to: **System → Settings → Administration**
   - Set **Listen Interfaces** to: **ONLY `opt6` (VLAN10_Management)**
   - Save configuration
   - Verify web UI only accessible from 192.168.10.x devices

2. **Migrate Ruckus AP to Management VLAN**:
   - See detailed migration plan below
   - Create DHCP static mapping for AP MAC → 192.168.10.10
   - Reconfigure AP management VLAN and static IP
   - Verify access via http://192.168.10.10

### 📋 Planned (Future Infrastructure)
- [ ] Deploy UniFi USW-Flex-2.5G-5 managed switch
- [ ] Configure switch port for Ruckus AP (native VLAN 10 + tagged 10,20,30)
- [ ] Migrate TinyCA to 192.168.10.37
- [ ] Migrate Talos cluster to VLAN 30 (from legacy LAN)
- [ ] Deploy UniFi switch with management IP 192.168.10.11

---

## Ruckus AP Migration Plan

### Current State
- **IP**: 192.168.1.11 (Legacy LAN)
- **Physical**: Connected to CUDY 16-port PoE (unmanaged switch)
- **SSIDs**: Broadcasting VLAN-tagged traffic (10, 20, 30)
- **Management**: Accessible from legacy LAN

### Target State
- **IP**: 192.168.10.10 (Management VLAN)
- **Physical**: Same connection (CUDY switch)
- **SSIDs**: Continue broadcasting VLAN-tagged traffic
- **Management**: Accessible only from VLAN 10

### Migration Steps

#### Step 1: Create DHCP Static Mapping (OPNsense)

1. Get Ruckus AP MAC address:
   - Via web UI: **Status → System → MAC Address**
   - Or via SSH: `get macaddr`

2. In OPNsense web UI:
   - Navigate to: **Services → DHCPv4 → [VLAN10_Management]**
   - Scroll to: **DHCP Static Mappings**
   - Click **+** to add new mapping:
     - **MAC Address**: (AP's MAC address)
     - **IP Address**: `192.168.10.10`
     - **Hostname**: `ruckus-ap`
     - **Description**: `Ruckus R720 Access Point - Management Interface`
   - Click **Save**
   - Click **Apply Changes**

#### Step 2: Reconfigure Ruckus AP Management VLAN

1. Access current AP web UI: http://192.168.1.11

2. Navigate to: **Technology → VLANs**
   - Set **Management VLAN ID**: `10`
   - Save (don't apply yet)

3. Navigate to: **Technology → IP Settings** (or **Configure → System**)
   - Change from DHCP to Static (if not already):
     - **IP Address**: `192.168.10.10`
     - **Subnet Mask**: `255.255.255.0` (/24)
     - **Default Gateway**: `192.168.10.1`
     - **Primary DNS**: `192.168.10.1`
   - Save

4. Apply all changes (AP will reboot - takes ~2-3 minutes)

#### Step 3: Verify New Access

1. Connect a device to "Homelab-Mgmt" SSID (VLAN 10)
   - Should receive IP in 192.168.10.100-200 range

2. Access new management interface:
   - Web UI: http://192.168.10.10
   - Confirm web UI loads and you can log in

3. Verify SSIDs still work:
   - "Homelab-Guest" → VLAN 20 (should still get 192.168.20.x)
   - "Homelab-Internal" → VLAN 30 (should still get 192.168.30.x)
   - "Homelab-Mgmt" → VLAN 10 (should still get 192.168.10.x)

#### Step 4: Verify Access Restrictions

Test that legacy LAN **cannot** access new management IP:

```bash
# From a device on legacy LAN (192.168.1.x):
ping 192.168.10.10        # Should timeout
curl http://192.168.10.10 # Should timeout or connection refused
```

---

## Security Verification Checklist

### OPNsense Web UI Access
- [ ] Web UI accessible from Management VLAN (192.168.10.x)
- [ ] Web UI **NOT** accessible from Internal VLAN (192.168.30.x)
- [ ] Web UI **NOT** accessible from DMZ/Guest VLAN (192.168.20.x)
- [ ] Web UI **NOT** accessible from Legacy LAN (192.168.1.x)

### Ruckus AP Web UI Access
- [ ] AP web UI accessible from Management VLAN (192.168.10.x)
- [ ] AP web UI **NOT** accessible from Legacy LAN (192.168.1.x)
- [ ] All SSIDs continue broadcasting normally
- [ ] Client devices receive correct VLAN IPs

### Firewall Logs
- [ ] Check for blocked attempts to access management interfaces from unauthorized VLANs
- [ ] Navigate to: **Firewall → Log Files → Live View**
- [ ] Filter by interface: opt4 (VLAN 20), opt5 (VLAN 30)
- [ ] Look for BLOCK entries to 192.168.10.x destinations

---

## Troubleshooting

### Cannot Access OPNsense Web UI After Restricting Listen Interfaces

**Symptoms**: Cannot access https://192.168.10.1 from Management VLAN

**Diagnosis**:
1. Verify you're connected to Management VLAN (192.168.10.x IP)
2. Check interface restriction setting:
   - Console access required (physical keyboard/monitor or SSH)
   - Run: `configctl webgui restart`
3. Verify firewall rules allow port 443 from Management VLAN

**Recovery**:
- Physical console access: Press `8` for shell, edit configuration
- Or SSH from Management VLAN: `ssh root@192.168.10.1`
- Reset listen interfaces: **System → Settings → Administration** → Change back to "All"

### Lost Access to Ruckus AP After Migration

**Symptoms**: Cannot access AP web UI at new IP 192.168.10.10

**Diagnosis**:
1. Verify you're connected to Management VLAN SSID ("Homelab-Mgmt")
2. Check DHCP static mapping is correct (MAC address matches)
3. Verify AP received correct IP:
   - Check DHCP leases in OPNsense: **Services → DHCPv4 → [VLAN10] → Leases**

**Recovery**:
- Factory reset AP (hold reset button 10+ seconds)
- Reconfigure from scratch starting at 192.168.1.11 (default)
- Follow migration steps again

### SSIDs Stopped Working After AP Migration

**Symptoms**: Cannot connect to Wi-Fi SSIDs after AP migration

**Diagnosis**:
1. Verify SSIDs are still broadcasting (check with phone/laptop Wi-Fi scanner)
2. Check VLAN configuration on AP:
   - **Technology → VLANs** → Verify VLAN IDs 10, 20, 30 still configured
3. Check SSID VLAN assignments:
   - Each SSID should still be tagged with correct VLAN ID

**Recovery**:
- Management VLAN ID change should not affect SSID VLAN tagging
- If SSIDs lost VLAN tags, reconfigure:
   - Navigate to: **Configuration → WLANs**
   - Edit each SSID and re-assign VLAN ID
   - Apply changes

---

## Best Practices

### Defense in Depth
- ✅ Layer 1: Interface restriction (web UI only listens on Management VLAN)
- ✅ Layer 2: Firewall rules (explicit allow on Management, block on others)
- ✅ Layer 3: Network segmentation (dedicated Management VLAN, separate SSID)
- ✅ Layer 4: Physical segmentation (planned - dedicated switch ports)

### Principle of Least Privilege
- Management interfaces accessible only from dedicated Management VLAN
- Management VLAN has no internet access (hardened)
- Internal VLAN cannot access management web UIs (interface restriction)
- DMZ/Guest completely isolated from all management interfaces

### Operational Security
- Access management interfaces only when needed
- Use strong passwords and 2FA on all management interfaces
- Regularly review firewall logs for unauthorized access attempts
- Keep management interface firmware/software updated
- Document all management IP addresses and access methods

### Future Enhancements
- Deploy VPN (WireGuard/IPsec) for remote management access
- Implement jump host/bastion in Management VLAN for SSH access
- Add IDS/IPS monitoring on Management VLAN
- Implement certificate-based authentication for web UIs
- Add RADIUS/802.1X for Management SSID authentication

---

## References

- [VLAN Implementation Summary](./VLAN_IMPLEMENTATION_SUMMARY.md)
- [Firewall Rules Documentation](./FIREWALL_RULES.md)
- [Network Architecture](./NETWORK_SETUP.md)
- [VLAN Test Results](./VLAN_TEST_RESULTS.md)

---

**Document Version**: 1.0  
**Security Review Date**: April 21, 2026  
**Next Review**: After Ruckus AP migration completion
