# VLAN Configuration Completion Guide

**Status**: ✅ **COMPLETE** - VLANs operational, firewall rules active, guest network isolated and functional

## What's Complete (via API)

### ✅ VLAN Interfaces Created on igc1 (Trunk Mode)
```
VLAN 10 → vlan03 → Management (192.168.10.0/24)
VLAN 20 → vlan01 → DMZ (192.168.20.0/24)
VLAN 30 → vlan02 → Internal (192.168.30.0/24)
```

All VLANs are configured on **igc1 (LAN)** as 802.1Q tagged VLANs. The parent interface is operational and ready for trunk traffic.

### ✅ Ruckus R720 SSIDs Configured
- **Homelab-Mgmt** → VLAN 10 (WPA3, no client isolation)
- **Homelab-Guest** → VLAN 20 (WPA2, client isolation enabled)
- **Homelab-Internal** → VLAN 30 (WPA3, no client isolation)

---

## Remaining Configuration (Web UI Required)

OPNsense's JSON API does not expose interface assignment or legacy DHCP configuration endpoints. The following steps must be completed via the web UI at `https://firewall.opnsense.internal:8443`.

### Step 1: Assign VLAN 10 Interface

**Navigation**: `Interfaces → Assignments`

1. In the "Available network ports" dropdown, select **vlan03**
2. Click **+ Add** button
3. The interface will be assigned as **OPT3** (or next available)
4. Click **Save**

### Step 2: Configure VLAN 10 Interface (Management)

**Navigation**: `Interfaces → [OPT3]` (or the assigned interface name)

**Settings**:
- ☑ **Enable interface**
- **Description**: `VLAN10_Management`
- **IPv4 Configuration Type**: `Static IPv4`
- **IPv4 Address**: `192.168.10.1` / `24`
- **IPv6 Configuration Type**: `None`

Click **Save** → **Apply Changes**

### Step 3: Enable VLAN 20 Interface (DMZ)

**Navigation**: `Interfaces → [OPT4]`

**Current Status**: Interface exists (vlan01) with IP `192.168.20.1/24` but is **disabled**

**Settings**:
- ☑ **Enable interface**
- Verify **IPv4 Address**: `192.168.20.1` / `24`
- Verify **Description**: `VLAN20` or change to `VLAN20_DMZ`

Click **Save** → **Apply Changes**

### Step 4: Enable VLAN 30 Interface (Internal)

**Navigation**: `Interfaces → [OPT5]`

**Current Status**: Interface exists (vlan02) with IP `192.168.30.1/24` but is **disabled**

**Settings**:
- ☑ **Enable interface**
- Verify **IPv4 Address**: `192.168.30.1` / `24`
- Verify **Description**: `VLAN30` or change to `VLAN30_Internal`

Click **Save** → **Apply Changes**

### Step 5: Configure DHCP for VLAN 10 (Management)

**Navigation**: `Services → DHCPv4 → [VLAN10_Management]`

**Settings**:
- ☑ **Enable DHCP server on the VLAN10_Management interface**
- **Range**:
  - **from**: `192.168.10.100`
  - **to**: `192.168.10.200`
- **DNS servers**: Leave default (will use OPNsense gateway)
- **Gateway**: `192.168.10.1` (auto-filled)

Click **Save**

### Step 6: Configure DHCP for VLAN 20 (DMZ)

**Navigation**: `Services → DHCPv4 → [VLAN20]`

**Settings**:
- ☑ **Enable DHCP server on the VLAN20 interface**
- **Range**:
  - **from**: `192.168.20.100`
  - **to**: `192.168.20.200`

Click **Save**

### Step 7: Configure DHCP for VLAN 30 (Internal)

**Navigation**: `Services → DHCPv4 → [VLAN30]`

**Settings**:
- ☑ **Enable DHCP server on the VLAN30 interface**
- **Range**:
  - **from**: `192.168.30.100`
  - **to**: `192.168.30.200`

Click **Save**

---

## Verification Steps

### 1. Check Interface Status

**Navigation**: `Interfaces → Overview`

Verify all VLAN interfaces show:
- **Status**: `up` (green)
- **IPv4**: Correct IP address assigned
- **Media**: `1000baseT <full-duplex>` or `2500Base-T <full-duplex>`

### 2. Check VLAN Configuration

**Navigation**: `Interfaces → Other Types → VLAN`

Verify all VLANs show:
```
Tag  Parent  Device   Description
10   igc1    vlan03   Management
20   igc1    vlan01   DMZ
30   igc1    vlan02   Internal
```

### 3. Test DHCP

**Connect a device to each SSID** and verify IP assignment:

- **Homelab-Mgmt** SSID → Should get `192.168.10.x` IP
- **Homelab-Guest** SSID → Should get `192.168.20.x` IP
- **Homelab-Internal** SSID → Should get `192.168.30.x` IP

**Check DHCP leases**: `Services → DHCPv4 → Leases`

### 4. Test Inter-VLAN Routing

By default, OPNsense allows all traffic between VLANs. Test:

```bash
# From a device on VLAN 30 (192.168.30.x)
ping 192.168.10.1   # Gateway for VLAN 10
ping 192.168.20.1   # Gateway for VLAN 20
```

If you want to **restrict** traffic (recommended for DMZ), configure firewall rules next.

---

## Next Steps (After VLAN Configuration)

### 1. Firewall Rules (Security Hardening)

**Navigation**: `Firewall → Rules → [Interface]`

**Recommended rules**:

#### VLAN 10 (Management)
- ✅ Allow all (management devices need full access)

#### VLAN 20 (DMZ/Guest)
- ✅ Allow DNS to OPNsense (port 53)
- ✅ Allow DHCP
- ✅ Allow internet access (WAN)
- ❌ **Block** access to VLAN 10 (192.168.10.0/24)
- ❌ **Block** access to VLAN 30 (192.168.30.0/24)
- ❌ **Block** access to LAN (192.168.1.0/24)

#### VLAN 30 (Internal)
- ✅ Allow all (trusted internal network)

### 2. Physical Cabling

**Current State**:
- igc1 (LAN) → CUDY 16-port unmanaged switch → All devices on 192.168.1.0/24
- igc2, igc3 → Not connected

**Target State** (Trunk Mode):
- igc1 (LAN) → **UniFi USW-Flex-2.5G-5** (managed, trunk port) → VLAN-tagged traffic
- UniFi switch → CUDY switch (for legacy 192.168.1.0/24 devices)
- UniFi switch → Ruckus R720 (trunk, carries all VLANs)

**UniFi Switch Configuration Required**:
1. Configure port connected to OPNsense igc1 as **trunk** (allow VLANs 10, 20, 30)
2. Configure port connected to Ruckus R720 as **trunk** (allow VLANs 10, 20, 30)
3. Configure ports for wired devices as **access ports** on appropriate VLAN

### 3. Static IP Assignments

**Recommended static IPs** (configure via DHCP static mappings or manual):

| Device | VLAN | Static IP | Reason |
|--------|------|-----------|--------|
| Ruckus R720 AP | 10 | 192.168.10.10 | Management access |
| UniFi Switch | 10 | 192.168.10.11 | Management access |
| TuringPi2 | 30 | 192.168.30.27 | Existing static |
| Talos nodes (3x) | 30 | 192.168.30.29-31 | Kubernetes cluster |
| TinyCA RPi | 10 | 192.168.10.37 | Certificate authority |

**How to configure**: `Services → DHCPv4 → [Interface] → Scroll to "Static Mappings"`

---

## Verification & Testing

### Current Status (Verified Working)

**✅ Guest Network (VLAN 20) Functional:**
- Devices connecting to "Homelab-Guest" SSID receive DHCP addresses (192.168.20.100-200)
- Internet access working correctly
- Firewall rules active and blocking access to internal networks

**✅ Active Firewall Rules:**
```
Interface: opt4 (VLAN20_DMZ)
  Rule 1 (sequence 1): BLOCK opt4 → Internal_Networks (192.168.1.0/24, 10.0/24, 30.0/24)
  Rule 2 (sequence 2): PASS opt4 → any (allows internet + gateway communication)
```

**✅ VLAN Interfaces Operational:**
- vlan01 (tag 20) → opt4 → 192.168.20.1/24 - UP, 26k packets received, 67k transmitted
- vlan02 (tag 30) → opt5 → 192.168.30.1/24 - UP
- vlan03 (tag 10) → opt6 → 192.168.10.1/24 - UP

### Complete VLAN Isolation Test Plan

To thoroughly verify network segmentation, test the following from each VLAN:

#### Test 1: Guest Network (VLAN 20) Isolation

**From device connected to "Homelab-Guest" SSID:**

```bash
# Should WORK (internet access):
ping 8.8.8.8                    # Google DNS
ping 1.1.1.1                    # Cloudflare DNS
curl https://www.google.com     # HTTPS connectivity
nslookup google.com             # DNS resolution

# Should WORK (gateway access):
ping 192.168.20.1               # VLAN 20 gateway

# Should FAIL (blocked by firewall - internal network isolation):
ping 192.168.1.1                # OPNsense LAN IP (should timeout)
ping 192.168.1.11               # Ruckus AP on legacy LAN (should timeout)
ping 192.168.10.1               # Management VLAN gateway (should timeout)
ping 192.168.10.10              # Any management device (should timeout)
ping 192.168.30.1               # Internal VLAN gateway (should timeout)
ping 192.168.30.27              # TuringPi2 (should timeout)

# Should FAIL (inter-VLAN blocking):
curl http://192.168.30.27       # Access to internal services (should timeout)
ssh user@192.168.10.10          # SSH to management devices (should timeout)
```

**Expected Results:**
- ✅ Internet: Full access
- ✅ Gateway (192.168.20.1): Reachable
- ❌ LAN (192.168.1.x): Blocked
- ❌ Management (192.168.10.x): Blocked  
- ❌ Internal (192.168.30.x): Blocked

#### Test 2: Internal Network (VLAN 30) Access

**From device connected to "Homelab-Internal" SSID:**

*Note: Firewall rules not yet configured for VLAN 30. Default behavior should allow all.*

```bash
# Should WORK (internet):
ping 8.8.8.8
curl https://www.google.com

# Should WORK (gateway):
ping 192.168.30.1

# Expected behavior (no rules configured yet):
ping 192.168.1.1                # Likely works (no restrictions)
ping 192.168.10.1               # Likely works (no restrictions)
ping 192.168.20.1               # Likely works (no restrictions)
```

**Note**: VLAN 30 rules should be configured to allow:
- Full internet access
- Access to Management VLAN (192.168.10.x) for infrastructure
- Access to legacy LAN (192.168.1.x) during migration
- BLOCK access from VLAN 30 to VLAN 20 (DMZ should be isolated)

#### Test 3: Management Network (VLAN 10) Access

**From device connected to "Homelab-Mgmt" SSID:**

*Note: Firewall rules not yet configured for VLAN 10.*

**Expected configuration** (to be implemented):
- BLOCK internet access (management devices shouldn't need it)
- ALLOW access to all internal VLANs (10, 30, legacy 1)
- ALLOW access to OPNsense web UI
- BLOCK access to DMZ (VLAN 20)

#### Test 4: Firewall State Verification

**Via OPNsense API or Web UI:**

1. **Active States**: Check `Firewall → Diagnostics → States`
   - Should see connections from 192.168.20.x → internet
   - Should NOT see connections from 192.168.20.x → 192.168.1/10/30.x

2. **Firewall Logs**: Check `Firewall → Log Files → Live View`
   - Filter by interface: opt4
   - Should see PASS logs for internet traffic
   - Should see BLOCK logs for internal network attempts

3. **Rule Statistics**: Check `Firewall → Rules → [Interface]`
   - Verify rule hit counters are incrementing
   - Block rule should show hits if isolation tested

### Performance Baseline

**Before Physical Switch Migration:**
- Guest VLAN 20: 26,453 packets received, 67,816 transmitted, 2.5 MB in, 92 MB out
- No errors on VLAN interfaces
- 1 Gbps link speed on igc1 trunk

### Recommended Next Tests

1. **Wireless Client Isolation**: From one guest device, try to ping another guest device on same SSID (should fail due to wireless client isolation on Ruckus AP)

2. **VLAN Hopping Test**: Attempt to send malformed VLAN-tagged packets from guest network to test firewall/switch VLAN security

3. **NAT Verification**: From guest device, visit https://whatismyipaddress.com and confirm public IP matches OPNsense WAN IP (192.168.7.63)

4. **DNS Leak Test**: Verify DNS queries are going through OPNsense/AdGuard, not ISP DNS

---

## Troubleshooting

### VLANs not working after configuration

**Symptom**: Devices connect to SSIDs but don't get IP addresses

**Checks**:
1. Verify interfaces are **enabled** (green in `Interfaces → Overview`)
2. Verify DHCP is enabled on each VLAN interface
3. Check `Status → System Logs → DHCP` for errors
4. Verify Ruckus AP is actually tagging traffic (check WLAN VLAN settings)

### Can't access OPNsense after configuration

**Symptom**: Lost access to OPNsense web UI

**Recovery**:
1. Connect wired to igc1 port directly (bypass switch)
2. You should get 192.168.1.x IP on the LAN network (still operational)
3. Access OPNsense at `https://192.168.1.1:8443`

### Devices get wrong VLAN

**Symptom**: Connecting to "Homelab-Mgmt" but getting 192.168.20.x instead of 192.168.10.x

**Checks**:
1. Verify SSID VLAN configuration in Ruckus (should match: Mgmt=10, Guest=20, Internal=30)
2. Verify VLAN interfaces are up on OPNsense
3. Check if switch between AP and OPNsense is stripping VLAN tags (must be trunk/802.1Q aware)

---

## Configuration Summary

### Network Topology (After Completion)

```
                                   ┌─────────────┐
                         ┌─────────┤ ISP Router  │
                         │         └─────────────┘
                         │
                    ┌────▼────┐
                    │ OPNsense│ (4x 2.5GbE)
                    │ Firewall│
                    └────┬────┘
                         │ igc1 (TRUNK: VLANs 10,20,30 + untagged LAN)
                         │
              ┌──────────▼──────────┐
              │  UniFi USW-Flex     │ (Managed, 2.5GbE)
              │  2.5G-5 Switch      │
              └─┬────────────────┬──┘
                │                │
                │ trunk          │ trunk (VLANs 10,20,30)
                │                │
          ┌─────▼─────┐    ┌────▼────────┐
          │   CUDY    │    │ Ruckus R720 │
          │ Unmanaged │    │     AP      │
          │  Switch   │    └─────────────┘
          └───────────┘
          (Legacy LAN:        SSIDs:
           192.168.1.x)       - Homelab-Mgmt     (VLAN 10)
                              - Homelab-Guest    (VLAN 20)
                              - Homelab-Internal (VLAN 30)
```

### VLAN Summary

| VLAN | Name | Subnet | Gateway | DHCP Range | Purpose |
|------|------|--------|---------|------------|---------|
| 10 | Management | 192.168.10.0/24 | 192.168.10.1 | .100-.200 | Network devices (AP, switches, IPMI) |
| 20 | DMZ | 192.168.20.0/24 | 192.168.20.1 | .100-.200 | Guest Wi-Fi, IoT devices, public services |
| 30 | Internal | 192.168.30.0/24 | 192.168.30.1 | .100-.200 | Trusted devices (Talos, workstations, servers) |
| 1 (untagged) | LAN | 192.168.1.0/24 | 192.168.1.1 | .10-.254 | Legacy/transition network (existing devices) |

---

## API Limitations Encountered

The following operations **cannot** be performed via OPNsense JSON API and require web UI access:

1. **Interface assignment** - Mapping VLAN devices (vlan01, vlan02, vlan03) to logical interfaces (OPT1, OPT2, etc.)
2. **Interface enable/disable** - Toggling interface operational state
3. **Legacy DHCP configuration** - ISC DHCP server settings (system uses legacy DHCP, not Kea)
4. **Interface IP configuration** - Setting static IPs on interfaces (can be set during VLAN creation but not updated)

**What worked via API**:
- ✅ VLAN creation (`/api/interfaces/vlan_settings/addItem`)
- ✅ VLAN modification (`/api/interfaces/vlan_settings/setItem`)
- ✅ VLAN reconfiguration/apply (`/api/interfaces/vlan_settings/reconfigure`)
- ✅ VLAN verification (`/api/interfaces/vlan_settings/searchItem`)

**Recommendation**: For production automation, consider:
- Ansible with `opnsense` collection (uses API + SSH for full configuration)
- Direct XML configuration file manipulation via SSH
- Migration to Kea DHCP (modern, fully API-enabled)
