# Network Infrastructure Setup

OPNsense firewall/router configuration and network architecture documentation.

## Overview

**OPNsense** acts as the primary firewall/router sitting behind the ISP router, providing advanced network segmentation, security, DNS services, and traffic control.

## Network Configuration

### Primary Network
- **OPNsense IP**: 192.168.1.1/16
- **Role**: Firewall, router, DNS server, DHCP server
- **Position**: Behind ISP router

### User Accounts
- **root** - Administrative account with 2FA enabled
- **zMynx** - Secondary admin with 2FA enabled

## Physical Network Topology

### OPNsense Hardware
- **Model**: 4x 2.5GbE ports
- **WAN Port**: Connected to ISP router
- **LAN Port**: Connected to CUDY switch (all traffic, no VLAN tagging currently)
- **Available Ports**: 2x unused 2.5GbE (reserved for future VLAN trunking)

### Current Network Layout

```
ISP Router
    ↓ (WAN)
OPNsense (192.168.1.1/16)
    ↓ (LAN - single flat network)
CUDY 16-Port PoE Switch (unmanaged/dumb)
    ├── Ruckus R720 AP (Wi-Fi access)
    ├── TuringPi2 (Talos cluster)
    ├── Raspberry Pi (Step-CA/tinyca)
    └── Other devices

```

### Switching Infrastructure

| Device | Type | Ports | PoE | Management | Role | Status |
|--------|------|-------|-----|------------|------|--------|
| **CUDY 16-Port** | Unmanaged | 16x 1GbE | ✅ Yes | ❌ None | Primary distribution switch | Active |
| **UniFi USW-Flex-2.5G-5** | Managed | 5x 2.5GbE | 1x PoE+ In | ✅ Web UI | VLAN-aware managed switch | Not configured |

**UniFi USW-Flex-2.5G-5 Specs:**
- **Ports**: 5x 2.5GbE RJ45 (data only)
- **Power**: 1x PoE+ input port (802.3at) - switch is powered via PoE, does NOT provide PoE to other devices
- **Management**: UniFi Network Controller (self-hosted or cloud)
- **VLAN Support**: 802.1Q VLAN tagging, per-port VLAN assignment
- **Uplink**: Can operate as VLAN trunk to OPNsense
- **Use Case**: VLAN segmentation for critical infrastructure (management VLAN, DMZ uplinks)

### Wireless Access Points

| Device | Model | Standard | Power | Connection | Management | Status |
|--------|-------|----------|-------|------------|------------|--------|
| **Ruckus R720** | Enterprise AP | 802.11ac Wave 2 | PoE injector or AC adapter | Trunk port (planned) | Unleashed | Active |

**Ruckus R720 Specs:**
- **Dual-band**: 2.4GHz + 5GHz simultaneous
- **Max Speed**: 1.7 Gbps combined (867 Mbps @ 5GHz)
- **Power**: 802.3af/at via PoE injector or AC adapter (not connected to PoE switch)
- **VLAN Support**: ✅ Multiple SSIDs with VLAN tagging
- **Management**: Ruckus Unleashed (controller-less cluster mode)
- **Use Case**: Provide Wi-Fi access to all VLANs via SSID-to-VLAN mapping

**Ruckus Unleashed Configuration:**
- Software-based controller running on the AP itself
- No external controller hardware required
- Supports up to 8 SSIDs per radio
- Per-SSID VLAN tagging capability
- Web-based management interface

### Wi-Fi SSID-to-VLAN Mapping Strategy

The Ruckus R720 will broadcast multiple SSIDs, each mapped to a specific VLAN for network segmentation and security isolation:

| SSID Name | VLAN ID | Security | Target Devices | Access Policy |
|-----------|---------|----------|----------------|---------------|
| **Homelab-Mgmt** | 10 | WPA3-Enterprise or WPA2-PSK | Admin laptops, management tools | Restricted - Infrastructure access only |
| **Homelab-Internal** | 30 | WPA3-Personal or WPA2-PSK | Trusted personal devices, workstations | Full internal network access |
| **Homelab-DMZ** / **Homelab-Guest** | 20 | WPA2-PSK (rotating password) | Guest devices, IoT, untrusted | Internet only, no internal access |

**SSID Configuration Details:**

#### 1. Homelab-Mgmt (VLAN 10 - Management)
- **Purpose**: Administrative access to network infrastructure
- **VLAN Tag**: 10
- **Subnet**: 192.168.10.0/24
- **Security**: WPA3-Enterprise (RADIUS) or strong WPA2-PSK
- **DHCP**: Enabled (192.168.10.100-200)
- **Firewall Rules**:
  - ✅ Access to OPNsense management (port 443)
  - ✅ Access to switch management interfaces
  - ✅ SSH/IPMI to servers
  - ❌ No internet access (security - management VLAN isolated)
  - ❌ No access to VLAN 20, 30
- **Client Isolation**: Disabled (admins may need device-to-device communication)
- **Hidden SSID**: Optional (security through obscurity)

#### 2. Homelab-Internal (VLAN 30 - Internal Apps)
- **Purpose**: Trusted personal devices and workstations
- **VLAN Tag**: 30
- **Subnet**: 192.168.30.0/24
- **Security**: WPA3-Personal (preferred) or WPA2-PSK with strong passphrase
- **DHCP**: Enabled (192.168.30.100-200)
- **Firewall Rules**:
  - ✅ Full internet access
  - ✅ Access to internal services (NFS, databases, apps)
  - ✅ Access to Talos cluster services
  - ✅ Access to TrueNAS storage
  - ❌ No direct access to VLAN 10 (management)
  - ⚠️ Limited access to VLAN 20 (DMZ) - outbound only
- **Client Isolation**: Disabled (trusted devices can communicate)
- **Hidden SSID**: No

#### 3. Homelab-DMZ / Homelab-Guest (VLAN 20 - DMZ/Guest)
- **Purpose**: Guest devices, IoT, untrusted equipment
- **VLAN Tag**: 20
- **Subnet**: 192.168.20.0/24
- **Security**: WPA2-PSK with rotating password (monthly change)
- **DHCP**: Enabled (192.168.20.100-200)
- **Firewall Rules**:
  - ✅ Internet access only (HTTP/HTTPS outbound)
  - ✅ DNS resolution via AdGuard Home
  - ❌ **No access to VLAN 10** (management)
  - ❌ **No access to VLAN 30** (internal)
  - ❌ No access to internal services (NFS, databases)
  - ⚠️ Rate limiting on internet bandwidth (optional QoS)
- **Client Isolation**: Enabled (guest devices cannot see each other)
- **Hidden SSID**: No
- **Captive Portal**: Optional (guest agreement page)

**Ruckus Unleashed VLAN Configuration Steps:**
1. Access Unleashed web UI (typically at AP IP address)
2. Navigate to **Configuration → WLANs**
3. Create SSID: "Homelab-Mgmt"
   - Set VLAN: 10
   - Security: WPA2-PSK or WPA3
   - Advanced: Disable client isolation
4. Create SSID: "Homelab-Internal"
   - Set VLAN: 30
   - Security: WPA3-Personal
   - Advanced: Disable client isolation
5. Create SSID: "Homelab-Guest"
   - Set VLAN: 20
   - Security: WPA2-PSK
   - Advanced: Enable client isolation
6. Configure trunk port on switch side (UniFi Port 2) to allow VLANs 10, 20, 30

**Security Best Practices:**
- Use **WPA3** where supported (Homelab-Internal minimum)
- Rotate **Guest Wi-Fi password** monthly
- Enable **802.11w Management Frame Protection** (prevents deauth attacks)
- Disable **WPS** on all SSIDs
- Enable **Fast Roaming (802.11r)** for seamless handoff (if adding more APs later)
- Monitor **Ruckus Unleashed logs** for unauthorized access attempts
- Separate **IoT devices** to DMZ/Guest network by default

### Planned Network Topology (Post-VLAN Implementation)

```
ISP Router
    ↓ (WAN)
OPNsense (192.168.1.1/16)
    ↓ (Trunk - VLANs 10, 20, 30 tagged on dedicated 2.5GbE port)
UniFi USW-Flex-2.5G-5 (Managed, powered via PoE injector/CUDY)
    ├── Port 1: Trunk to OPNsense (all VLANs)
    ├── Port 2: Trunk to Ruckus R720 (VLAN 10, 20, 30 for SSIDs)
    ├── Port 3: VLAN 30 (Internal) - Talos cluster
    ├── Port 4: VLAN 30 (Internal) - TrueNAS/Storage
    └── Port 5: VLAN 20 (DMZ) - HAProxy/Public services
    
Ruckus R720 AP
    ├── Powered via: PoE injector or AC adapter (separate from UniFi switch)
    ├── Connected to: UniFi switch Port 2 (trunk, data only)
    └── SSIDs:
        ├── "Homelab-Mgmt" → VLAN 10 (Management)
        ├── "Homelab-DMZ" → VLAN 20 (DMZ/Guest)
        └── "Homelab-Internal" → VLAN 30 (Trusted devices)

CUDY 16-Port PoE (Unmanaged)
    └── Access mode devices (legacy/IoT on flat network or guest VLAN)
```

**Migration Strategy:**
1. Power UniFi switch via PoE injector from CUDY or dedicated AC adapter
2. Configure OPNsense VLAN interfaces (10, 20, 30) on unused 2.5GbE port
3. Configure UniFi switch Port 1 as trunk to OPNsense
4. Configure UniFi switch Port 2 as trunk to Ruckus R720
5. Power Ruckus R720 via PoE injector (separate from UniFi switch)
6. Configure Ruckus Unleashed with SSID-to-VLAN mappings
7. Assign remaining UniFi ports to specific VLANs per device
8. Migrate critical infrastructure to VLAN-aware ports
9. Keep CUDY switch for legacy devices or as additional PoE source

## VLAN Architecture

Network segmentation via VLANs for security and traffic isolation:

| VLAN ID | Purpose | Subnet | DHCP Range | Gateway | Description |
|---------|---------|--------|------------|---------|-------------|
| **10** | Management | 192.168.10.0/24 | 192.168.10.100-200 | 192.168.10.1 | Infrastructure management (switches, APs, IPMI) |
| **20** | DMZ | 192.168.20.0/24 | 192.168.20.100-200 | 192.168.20.1 | Public-facing services (reverse proxy, exposed apps) |
| **30** | Internal Apps | 192.168.30.0/24 | 192.168.30.100-200 | 192.168.30.1 | Internal applications and services |

### VLAN Security Design
- **VLAN 10 (Management)**: Isolated, no internet access by default, strict firewall rules
- **VLAN 20 (DMZ)**: Segmented from internal networks, monitored traffic, reverse proxy only
- **VLAN 30 (Internal)**: Trusted internal services, access to NFS/storage

### DHCP Configuration

Each VLAN has its own DHCP scope managed by OPNsense:

- **Subnet Pattern**: `192.168.<VLAN_ID>.0/24`
- **Gateway**: `192.168.<VLAN_ID>.1` (OPNsense interface IP)
- **DHCP Range**: `192.168.<VLAN_ID>.100` - `192.168.<VLAN_ID>.200` (101 addresses per VLAN)
- **Reserved Range**: `.2-.99` for static assignments (servers, infrastructure)
- **Excluded Range**: `.201-.254` reserved for future expansion

#### Static IP Allocation Guidelines
- **VLAN 10**: `.10-.49` for network infrastructure (switches, APs)
- **VLAN 10**: `.50-.99` for IPMI/management interfaces
- **VLAN 20**: `.10-.99` for DMZ services (HAProxy, public apps)
- **VLAN 30**: `.10-.99` for internal services (databases, internal apps)

## DNS & Ad Blocking

### Architecture: AdGuard Home + Unbound

**DNS Query Flow:**
```
Client Device
    ↓
AdGuard Home (Port 53) - Ad/tracker filtering
    ↓
Unbound (Port 5353) - Recursive resolver + DNSSEC validation
    ↓
DNS over TLS (Port 853) - Encrypted queries
    ↓
Public DNS (Cloudflare 1.1.1.1, Quad9 9.9.9.9)
```

### AdGuard Home Configuration
- **Implementation**: OPNsense plugin (community repository)
- **Listen Port**: 53 (default DNS)
- **Admin Interface**: Port 3000 (LAN only)
- **Upstream DNS**: Unbound at 127.0.0.1:5353
- **Features**:
  - DNS-based ad blocking
  - Tracking prevention
  - Custom blocklists
  - Client-specific filtering
  - Query logging and analytics

**Setup Guide Followed:**
- [Setup AdGuard Home on OPNsense](https://windgate.net/setup-adguard-home-opnsense-adblocker/)

### Unbound Configuration
- **Listen Port**: 5353 (changed from default 53)
- **DNSSEC**: Enabled for cryptographic validation
- **DNS over TLS**: Enabled with upstream resolvers:
  - Cloudflare: 1.1.1.1:853, 1.1.1.3:853 (cloudflare-dns.com)
  - Quad9: 9.9.9.9:853, 149.112.112.112:853 (dns.quad9.net)
- **Features**:
  - Recursive DNS resolution
  - DHCP lease registration
  - Static mapping registration
  - IPv6 link-local address registration

### DNS Privacy & Security
- **DNS over TLS**: All upstream queries encrypted
- **No DNS Leaks**: Verified via dnsleaktest.com
- **DNSSEC Validation**: Prevents DNS spoofing
- **Local Resolution**: Internal hostnames resolved locally via Unbound

## Security Features

### GeoBlocking
- **Provider**: MaxMind GeoIP database
- **Status**: Enabled
- **Purpose**: Block traffic from specific geographic regions

### Two-Factor Authentication (2FA)
- **Enabled for**: All admin accounts (root, zMynx)
- **Implementation**: OPNsense built-in 2FA

### Firewall
- **Default Policy**: Deny all, explicit allow rules only
- **VLAN Segmentation**: Isolated traffic between VLANs
- **NAT**: Configured per VLAN requirements
- **Logging**: Enabled for security analysis

## Planned Features

### IPS/IDS (Intrusion Prevention/Detection System)
- **Planned**: Suricata IDS integration
- **Purpose**: Real-time threat detection and prevention
- **Features**:
  - Signature-based detection
  - Anomaly detection
  - Protocol analysis
  - Automatic blocking of malicious traffic

See [QFEEDS_IDS_SETUP.md](./QFEEDS_IDS_SETUP.md) for the operational checklist and rule placement guidance.

### Threat Intelligence Feeds
- **Planned**: q-feeds integration
- **Purpose**: Dynamic blocklists based on threat intelligence
- **Sources**: Community-curated IP/domain reputation feeds

### Additional Planned Services
- **HAProxy**: Reverse proxy for TLS termination (VLAN 20)
- **VPN**: WireGuard or IPsec for remote access
- **Let's Encrypt**: Automated certificate management via ACME

## Integration with Infrastructure

### Connection to Talos Cluster
- **Cluster Network**: Routes through OPNsense
- **DNS**: Talos nodes use AdGuard for resolution
- **Certificate Authority**: Step-CA (tinyca) reachable via OPNsense routing

### Storage Integration
- **TrueNAS**: Accessible from appropriate VLANs
- **NFS**: Firewall rules allow DMZ → NFS (VLAN 30)

## Current Status

**Implemented:**
✅ OPNsense firewall with 2FA  
✅ AdGuard Home DNS filtering  
✅ Unbound recursive DNS with DNSSEC  
✅ DNS over TLS encryption  
✅ MaxMind GeoBlocking  
✅ Ruckus R720 Wi-Fi AP (802.11ac Wave 2)  
✅ CUDY 16-port PoE switch (unmanaged)  
✅ **VLAN infrastructure fully operational** (VLANs 10, 20, 30 on igc1 trunk)  
✅ **Ruckus SSIDs configured with VLAN tagging** (Homelab-Mgmt, Homelab-Guest, Homelab-Internal)  
✅ **DHCP services active** on all VLANs (ISC DHCPv4 Legacy)  
✅ **Guest network (VLAN 20) operational** - Isolated from internal networks with internet access  
✅ **Firewall rules active** - Guest network isolation enforced  

**Ready to Deploy:**
🔵 UniFi USW-Flex-2.5G-5 managed switch (physical migration pending)  

**In Progress:**
🟡 **VLAN isolation testing** - Complete test plan in [VLAN_COMPLETION_GUIDE.md](./VLAN_COMPLETION_GUIDE.md)  

**Planned:**
⏳ UniFi switch deployment with VLAN trunk configuration  
⏳ Physical cabling migration (Ruckus AP to UniFi switch)  
⏳ Device migration to appropriate VLANs  
⏳ IPS/IDS (Suricata/Snort)  
⏳ Threat intelligence feeds (q-feeds)  
⏳ HAProxy reverse proxy  
⏳ VPN (WireGuard/IPsec)  

**VLAN Configuration Status:**
- **VLAN 10 (Management)**: ✅ **Fully Configured**
  - Interface: vlan03 → opt6 → 192.168.10.1/24
  - DHCP: 192.168.10.100-200
  - Firewall: ✅ **5 rules active** (blocks internet, allows infrastructure only)
  - Devices: ⏳ None connected yet
  - Security: Internet blocked, OPNsense UI + internal access allowed
  
- **VLAN 20 (DMZ/Guest)**: ✅ **Fully Functional**
  - Interface: vlan01 → opt4 → 192.168.20.1/24
  - DHCP: 192.168.20.100-200 (active)
  - Firewall: ✅ **2 rules active** (blocks internal networks, allows internet)
  - Devices: ✅ Guest clients connected (26k packets RX, 67k packets TX)
  - SSID: "Homelab-Guest" with wireless client isolation enabled
  
- **VLAN 30 (Internal)**: ✅ **Fully Configured**
  - Interface: vlan02 → opt5 → 192.168.30.1/24
  - DHCP: 192.168.30.100-200
  - Firewall: ✅ **5 rules active** (allows internet + management, blocks DMZ)
  - Devices: ⏳ None connected yet (Talos cluster at 192.168.30.27-31 on legacy LAN)
  - Security: Full internal access, DMZ isolated

**Trunk Configuration:**
- Parent Interface: igc1 (1 Gbps active, 2.5 Gbps capable)
- Protocol: 802.1Q
- Tagged VLANs: 10, 20, 30
- Untagged: Legacy LAN (192.168.1.x) for backward compatibility

**Next Steps:**
1. Test VLAN isolation (see [VLAN_COMPLETION_GUIDE.md](./VLAN_COMPLETION_GUIDE.md#verification--testing))
2. Deploy UniFi switch with trunk configuration
3. Migrate devices to appropriate VLANs

**Documentation:**
- Detailed configuration guide: [VLAN_COMPLETION_GUIDE.md](./VLAN_COMPLETION_GUIDE.md)
- Implementation summary: [VLAN_IMPLEMENTATION_SUMMARY.md](./VLAN_IMPLEMENTATION_SUMMARY.md)
- Firewall rules matrix: [FIREWALL_RULES.md](./FIREWALL_RULES.md)  

## References

- [AdGuard Home + Unbound Setup Guide](https://windgate.net/setup-adguard-home-opnsense-adblocker/)
- [OPNsense Documentation](https://docs.opnsense.org/)
- [MaxMind GeoIP](https://www.maxmind.com/)
