# VLAN Implementation Summary

**Date Completed**: April 21, 2026  
**Status**: ✅ **Operational** - Guest network isolated and functional

---

## What Was Accomplished

### 1. VLAN Infrastructure (API + Web UI)

**Created 3 VLANs on trunk port igc1:**
- VLAN 10 (Management) → vlan03 → opt6 → 192.168.10.1/24
- VLAN 20 (DMZ/Guest) → vlan01 → opt4 → 192.168.20.1/24
- VLAN 30 (Internal) → vlan02 → opt5 → 192.168.30.1/24

**Method**: VLANs created via OPNsense API, interfaces assigned and configured via web UI (API limitations)

### 2. DHCP Services

**Configured ISC DHCPv4 [Legacy] on all VLANs:**
- Each VLAN: DHCP range .100-.200
- Static IP range: .2-.99 (reserved for infrastructure)
- Gateway: 192.168.{10,20,30}.1

### 3. Ruckus R720 Access Point Configuration

**Factory reset performed** to resolve management access issues.

**Created 3 SSIDs with VLAN tagging:**
| SSID | VLAN | Security | Client Isolation | Purpose |
|------|------|----------|------------------|---------|
| Homelab-Mgmt | 10 | WPA3 | Disabled | Network management devices |
| Homelab-Guest | 20 | WPA2 | Enabled + AllowList | Guest Wi-Fi, IoT, isolated |
| Homelab-Internal | 30 | WPA3 | Disabled | Trusted internal devices |

**Guest Network AllowList**: Created "Guest-Internet-Access" with auto-discovery to allow gateway communication while isolating clients from each other.

### 4. Firewall Rules - VLAN 20 (Guest) Isolation

**Created firewall alias:**
- `Internal_Networks`: 192.168.1.0/24, 192.168.10.0/24, 192.168.30.0/24

**Active firewall rules on opt4 (VLAN20):**
1. **BLOCK**: opt4 → Internal_Networks (prevents guest access to LAN, management, internal VLANs)
2. **PASS**: opt4 → any (allows internet access and gateway communication)

**Verification**: Guest devices receive DHCP, have internet access, cannot access internal networks.

### 5. Documentation

**Created comprehensive guides:**
- `VLAN_COMPLETION_GUIDE.md` - 420+ line step-by-step configuration guide with troubleshooting
- `VLAN_IMPLEMENTATION_SUMMARY.md` - This document
- Updated `NETWORK_SETUP.md` with current VLAN status

---

## Current Network State

### OPNsense Configuration

**Physical Interfaces:**
- igc0 (WAN): 192.168.7.63/24 - ISP connection
- igc1 (LAN): 192.168.1.1/24 - **Trunk port** carrying all VLAN traffic
- igc2, igc3: Unused (previously had VLANs on dedicated ports, now migrated to trunk)

**VLAN Interfaces (all operational, UP status):**
- vlan01 (tag 20): opt4 - 192.168.20.1/24 - **26k packets received, 67k transmitted** (active guest traffic)
- vlan02 (tag 30): opt5 - 192.168.30.1/24 - Minimal traffic (no active clients yet)
- vlan03 (tag 10): opt6 - 192.168.10.1/24 - Minimal traffic (no active clients yet)

**Trunk Configuration:**
- Parent interface: igc1 (1 Gbps link active)
- Protocol: 802.1Q
- Tagged VLANs: 10, 20, 30
- Untagged: Legacy LAN (192.168.1.x) for backward compatibility

### Ruckus R720 Status

- **Management IP**: 192.168.1.11 (legacy LAN, will migrate to 192.168.10.10)
- **Firmware**: Ruckus Unleashed (controller-less)
- **Connection**: Currently connected to CUDY unmanaged switch (legacy LAN)
- **VLAN Capability**: Verified working - VLAN 20 guests receiving correct IPs

**Next Step**: Migrate Ruckus connection to UniFi managed switch configured for trunk mode.

### Active Firewall Rules Summary

**VLAN 20 (opt4 - DMZ/Guest)**: 2 rules active
- Block internal network access ✅
- Allow internet access ✅

**VLAN 30 (opt5 - Internal)**: No custom rules (default allow all)
**VLAN 10 (opt6 - Management)**: No custom rules (default allow all)

---

## Verified Functionality

### ✅ What's Working

1. **Guest VLAN (20) fully operational:**
   - DHCP address assignment (192.168.20.100-200)
   - Internet connectivity via NAT
   - Gateway reachability (192.168.20.1)
   - Firewall rules blocking internal networks

2. **VLAN tagging functional:**
   - Ruckus AP correctly tagging SSID traffic
   - OPNsense receiving tagged traffic on trunk
   - DHCP responding on correct VLAN

3. **Network isolation active:**
   - Guest network cannot access 192.168.1.x (LAN)
   - Guest network cannot access 192.168.10.x (Management)
   - Guest network cannot access 192.168.30.x (Internal)

4. **Wireless client isolation enabled:**
   - Guest devices cannot communicate with each other (Ruckus setting)
   - AllowList allows gateway/DHCP communication

### ⏳ Not Yet Tested

1. **Management VLAN (10)**: No devices connected yet
2. **Internal VLAN (30)**: No devices connected yet
3. **Inter-VLAN routing policies**: Only guest isolation implemented
4. **Physical switch migration**: Still using legacy CUDY switch, UniFi switch not deployed

---

## Outstanding Tasks

### High Priority (Security)

1. **Configure VLAN 10 (Management) firewall rules:**
   - BLOCK internet access (management devices don't need it)
   - ALLOW access to all internal VLANs (10, 30, legacy 1)
   - ALLOW access to OPNsense web UI
   - BLOCK access to DMZ (VLAN 20)

2. **Configure VLAN 30 (Internal) firewall rules:**
   - ALLOW internet access
   - ALLOW access to Management VLAN (10)
   - ALLOW access to legacy LAN (1) during migration
   - BLOCK access to DMZ (VLAN 20)

3. **Migrate infrastructure devices to correct VLANs:**
   - Ruckus R720 AP: 192.168.1.11 → 192.168.10.10 (Management)
   - UniFi Switch: → 192.168.10.11 (Management)
   - TinyCA RPi: → 192.168.10.37 (Management)
   - TuringPi2 + Talos: Already at 192.168.30.27-31 (Internal)

### Medium Priority (Infrastructure)

4. **Physical cabling migration:**
   - Deploy UniFi USW-Flex-2.5G-5 switch
   - Configure trunk port for OPNsense connection (VLANs 10, 20, 30 + untagged)
   - Connect Ruckus R720 to UniFi switch trunk
   - Migrate devices from CUDY switch to UniFi switch with VLAN assignments

5. **DHCP static mappings:**
   - Create static DHCP reservations for infrastructure
   - Document MAC addresses for all managed devices

6. **Testing and verification:**
   - Complete VLAN isolation test plan (see VLAN_COMPLETION_GUIDE.md)
   - Test inter-VLAN communication rules
   - Verify NAT and routing for all VLANs
   - Monitor firewall logs for unexpected traffic

### Low Priority (Nice to Have)

7. **Future enhancements:**
   - IPS/IDS (Suricata/Snort) on guest VLAN
   - Bandwidth limiting for guest network
   - Captive portal for guest Wi-Fi
   - HAProxy reverse proxy on VLAN 20
   - VPN access to management VLAN

8. **Documentation:**
   - Network topology diagram (visual)
   - Device inventory with MAC addresses
   - Firewall rule matrix (all VLANs)

---

## Lessons Learned

### OPNsense API Limitations

**What worked via API:**
- ✅ VLAN creation and modification
- ✅ Firewall alias management
- ✅ Firewall rule creation
- ✅ Interface status queries

**What requires web UI:**
- ❌ Interface assignment (mapping vlan devices to opt interfaces)
- ❌ Interface enable/disable
- ❌ ISC DHCP configuration (legacy DHCP, not Kea)
- ❌ Gateway assignment to interfaces

**Recommendation**: For production automation, use Ansible with the `opnsense` collection which combines API + SSH for full control.

### Gateway Configuration Mystery

**Issue**: API showed `"gateways": []` for all VLAN interfaces, suggesting no gateway configured.

**Reality**: Guest network (VLAN 20) has full internet connectivity despite empty gateway field.

**Conclusion**: OPNsense uses default gateway routing behavior when VLANs are on the same device as the WAN. The API response doesn't fully reflect the actual routing configuration. Outbound NAT works automatically with "Automatic outbound NAT rule generation" mode.

**Finding**: No "IPv4 Upstream Gateway" field visible in web UI interface configuration, confirming default gateway behavior is implicit.

### Ruckus Unleashed Quirks

**Issue**: Could not access Ruckus web UI at 192.168.1.11 despite ping working.

**Resolution**: Factory reset via SSH resolved the issue (firmware corruption suspected).

**Learning**: Ruckus Unleashed firmware can become corrupted. SSH access (port 8022) remains available even when web UI fails. Factory reset preserves management IP but wipes all configuration.

### VLAN Trunk Simplification

**Initial approach**: Dedicated physical ports per VLAN (igc2=VLAN20, igc3=VLAN30).

**Final approach**: Single trunk on igc1 carrying all VLANs.

**Benefits**:
- More scalable (can add VLANs without physical ports)
- Cleaner topology (one cable to switch)
- Aligns with industry best practices
- Enables managed switch VLAN features

---

## Reference Architecture

### Current Topology

```
                          ┌─────────────┐
                ┌─────────┤ ISP Router  │
                │         └─────────────┘
                │
           ┌────▼────┐
           │OPNsense │ igc0 (WAN): 192.168.7.63
           │Firewall │ igc1 (TRUNK): 192.168.1.1 + VLANs 10,20,30
           └────┬────┘
                │ igc1 (1 Gbps trunk)
                │
         ┌──────▼──────┐
         │    CUDY     │ (unmanaged, temporary)
         │  16-port    │
         │ PoE Switch  │
         └─────┬───────┘
               │
         ┌─────▼──────┐
         │  Ruckus    │ 192.168.1.11
         │  R720 AP   │
         └────────────┘
           ├─ Homelab-Mgmt     (VLAN 10)
           ├─ Homelab-Guest    (VLAN 20) ✅ Active
           └─ Homelab-Internal (VLAN 30)
```

### Target Topology (After Switch Migration)

```
                          ┌─────────────┐
                ┌─────────┤ ISP Router  │
                │         └─────────────┘
                │
           ┌────▼────┐
           │OPNsense │ igc0 (WAN): 192.168.7.63
           │Firewall │ igc1 (TRUNK): VLANs 10,20,30 + untagged
           └────┬────┘
                │ igc1 (2.5 Gbps trunk)
                │
      ┌─────────▼─────────┐
      │  UniFi USW-Flex   │ 192.168.10.11 (VLAN 10)
      │    2.5G-5 Port    │ (managed, VLAN-aware)
      └─┬───────────────┬─┘
        │ trunk         │ access ports with VLAN tags
        │               │
  ┌─────▼─────┐   ┌────▼────────┐
  │  Ruckus   │   │  Devices    │
  │  R720 AP  │   │ (per VLAN)  │
  └───────────┘   └─────────────┘
    VLAN 10: 192.168.10.10
```

---

## Next Session Checklist

When continuing this work:

1. ✅ **Verify guest network still functional** (ping, internet access)
2. ⬜ **Test complete VLAN isolation** (use test plan in VLAN_COMPLETION_GUIDE.md)
3. ⬜ **Configure VLAN 10 and 30 firewall rules** (see "Outstanding Tasks" above)
4. ⬜ **Plan UniFi switch deployment** (trunk config, port assignments)
5. ⬜ **Migrate Ruckus AP to Management VLAN** (static IP, VLAN 10)

---

## Files Modified/Created

- ✅ `network/VLAN_COMPLETION_GUIDE.md` - Comprehensive configuration guide (420+ lines)
- ✅ `network/VLAN_IMPLEMENTATION_SUMMARY.md` - This document
- ✅ `network/NETWORK_SETUP.md` - Updated with VLAN status

**API Usage Evidence:**
- Successfully created VLANs via `/api/interfaces/vlan_settings/`
- Successfully created firewall aliases via `/api/firewall/alias/`
- Successfully created firewall rules via `/api/firewall/filter/`
- Applied all configurations via reconfigure/apply endpoints

**Web UI Configuration Required:**
- Interface assignments (vlan01→opt4, vlan02→opt5, vlan03→opt6)
- Interface enable/disable toggles
- ISC DHCP configuration for all VLANs

---

**End of Implementation Summary**
