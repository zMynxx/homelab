# UniFi Main Switch & CUDY Removal — Migration

**Status**: In Progress (interim wiring in place, waiting on PoE injector)
**Last Updated**: 2026-08-29
**Goal**: Remove the CUDY PoE switch, make the UniFi USW-Flex-2.5G-5 the single main switch.

---

## Why

The CUDY 16-port PoE switch is unmanaged — no VLAN awareness, no monitoring. The UniFi
USW-Flex-2.5G-5 is a managed, VLAN-capable switch (5x 2.5GbE) and should be the main
distribution switch. The only reason CUDY cannot be removed immediately is that it currently
provides **PoE power to the Ruckus R720 AP**. Once the PoE injector arrives, CUDY becomes
redundant and is removed.

---

## Current (Realized) Topology — Interim

```
                          ┌─────────────┐
                          │  ISP Router │
                          └──────┬──────┘
                                 │ WAN
                            ┌────▼────┐
                            │OPNsense │ igc0 (WAN): 192.168.7.63
                            └────┬────┘
                       igc1 trunk │ (VLAN 10/20/30 + untagged)
                                 │
                        ┌────────▼────────┐
                        │  UniFi 2.5G-5    │  (main switch, igc1 → Port 1)
                        ├──────────────────┤
                        │ Port 1  trunk ← OPNsense igc1 (VLAN 10/20/30)
                        │ Port 2  access VLAN 30 → TPi2 (Talos cluster)
                        │ Port 3  access VLAN 10 → RPi-TinyCA
                        │ Port 4  trunk → CUDY → Ruckus R720 (PoE, interim)
                        │ Port 5  (free / unused)
                        └──────────────────┘
```

**Key points about the interim state:**
- OPNsense **igc1** is the trunk to UniFi **Port 1** (carries tagged VLAN 10/20/30 + untagged
  legacy LAN). There is **no igc2 link** in the current setup.
- **TPi2** (Talos) → UniFi **Port 2**, access on **VLAN 30**.
- **RPi-TinyCA** → UniFi **Port 3**, access on **VLAN 10** (Management).
- **Ruckus R720** → CUDY → UniFi **Port 4** (trunk). The Ruckus is PoE-powered by CUDY.

---

## Target (Final) Topology — after CUDY removal

```
                          ┌─────────────┐
                          │  ISP Router │
                          └──────┬──────┘
                                 │ WAN
                            ┌────▼────┐
                            │OPNsense │ igc0 (WAN): 192.168.7.63
                            └────┬────┘
                       igc1 trunk │ (VLAN 10/20/30 + untagged)
                                 │
                        ┌────────▼────────┐
                        │  UniFi 2.5G-5    │  (main switch)
                        ├──────────────────┤
                        │ Port 1  trunk ← OPNsense igc1 (VLAN 10/20/30)
                        │ Port 2  access VLAN 30 → TPi2 (Talos)
                        │ Port 3  access VLAN 10 → RPi-TinyCA
                        │ Port 4  trunk → Ruckus R720  (PoE injector power)
                        │ Port 5  (free / wired device)
                        └──────────────────┘

                        CUDY: removed
```

Once the Ruckus is powered by its own PoE injector, it connects **directly** to UniFi
Port 4 (trunk) and the CUDY is removed from the path entirely.

---

## UniFi Switch Port Map

| Port | Interim (now) | Final (after CUDY removal) |
|------|---------------|----------------------------|
| **1** | Uplink — OPNsense `igc1` (trunk, VLANs 10/20/30) | Uplink — OPNsense `igc1` (trunk, VLANs 10/20/30) |
| **2** | Access **VLAN 30** → TPi2 (Talos cluster) | Access **VLAN 30** → TPi2 (Talos cluster) |
| **3** | Access **VLAN 10** → RPi-TinyCA (Management) | Access **VLAN 10** → RPi-TinyCA (Management) |
| **4** | **Trunk → CUDY** → Ruckus R720 (PoE, interim) | **Trunk → Ruckus R720** (PoE injector) |
| **5** | (free / unused) | (free / wired device) |

- UniFi management IP: `192.168.10.20` (static, Management VLAN 10 — set as native/management VLAN).
- Port 1 must be a **trunk** allowing untagged (native) + tagged VLANs 10, 20, 30 to carry the
  OPNsense trunk.
- Port 4 is a **trunk** in both states (toward CUDY, then later directly to the Ruckus), carrying
  VLANs 10/20/30 so the Ruckus SSID-to-VLAN tagging can work.

---

## Ruckus R720 — Interim vs Final

### Interim

- Powered via **CUDY PoE** (CUDY connects to UniFi Port 4 trunk).
- Because Port 4 is a **trunk** and CUDY passes tagged frames transparently to the Ruckus, the
  Ruckus can continue to tag its SSIDs **10/20/30** correctly.
- **No SSID segmentation regression** in this wiring (unlike the earlier igc2-based plan).

### Final (after injector + CUDY removal)

1. Power the Ruckus with the **PoE injector** (802.3af/at).
2. Keep Ruckus on UniFi **Port 4** as a **trunk** carrying VLANs 10/20/30 (CUDY now bypassed).
3. Confirm Ruckus SSID-to-VLAN mapping:
   - Homelab-Mgmt → VLAN 10
   - Homelab-Guest → VLAN 20
   - Homelab-Internal → VLAN 30
4. Migrate Ruckus management to `192.168.10.10` (VLAN 10) as per
   [MANAGEMENT_ACCESS_SECURITY.md](./MANAGEMENT_ACCESS_SECURITY.md).
5. Remove the CUDY from the path.

---

## OPNsense Configuration

> `igc1` is the LAN trunk carrying tagged VLANs 10/20/30 plus untagged legacy LAN. No
> additional OPNsense interface changes are required for this migration — the VLAN interfaces
> remain on `igc1` in both interim and final states. There is **no igc2 link**.

No new OPNsense VLAN subinterfaces are needed for the current wiring.

---

## Migration Steps (ordered)

### Phase 1 — Interim (complete)

All Phase 1 wiring and verification done: igc1 trunk → UniFi Port 1, Port 2=Talos VLAN 30,
Port 3=TinyCA VLAN 10, Port 4=trunk→CUDY→Ruckus. UniFi mgmt `192.168.10.20`, Ruckus mgmt
`192.168.10.10`. All devices reachable and SSIDs tagging correctly.

1. [x] OPNsense `igc1` trunk connects to UniFi **Port 1**.
2. [x] UniFi **Port 2** = access VLAN 30 → TPi2 (Talos).
3. [x] UniFi **Port 3** = access VLAN 10 → RPi-TinyCA (Management).
4. [x] UniFi **Port 4** = trunk → CUDY → Ruckus R720 (PoE from CUDY).
5. [x] Set UniFi management IP `192.168.10.20` (static), native VLAN 10.
6. [x] Confirm TPi2 (VLAN 30) and TinyCA (VLAN 10) are reachable and functional.
7. [x] Confirm Ruckus SSIDs tag correctly to VLANs 10/20/30 through the Port 4 trunk.

### Phase 2 — Final (once PoE injector arrives)

8. [ ] Power Ruckus with the PoE injector.
9. [ ] Connect Ruckus **directly** to UniFi Port 4 (trunk), removing CUDY from the path.
10. [ ] Remove the CUDY from the setup.
11. [ ] Migrate Ruckus management to `192.168.10.10`.
12. [ ] Verify all VLANs + SSID segmentation per [VLAN_TEST_RESULTS.md](./VLAN_TEST_RESULTS.md).

---

## Verification

- **After Phase 1**: TPi2 on VLAN 30, TinyCA on VLAN 10, Ruckus SSIDs tagging 10/20/30 via the
  Port 4 trunk — all functional. No isolation regression expected with this wiring.
- **After Phase 2**: Ruckus on UniFi Port 4 with PoE injector; CUDY removed. Re-run VLAN
  isolation tests (Guest isolated on VLAN 20, Management restored).
- UniFi reachable at `192.168.10.20`; Ruckus reachable at `192.168.10.10`.

---

## Related Documentation

- [NETWORK_SETUP.md](./NETWORK_SETUP.md) — overall network architecture
- [VLAN_COMPLETION_GUIDE.md](./VLAN_COMPLETION_GUIDE.md) — VLAN trunk + port config
- [MANAGEMENT_ACCESS_SECURITY.md](./MANAGEMENT_ACCESS_SECURITY.md) — management IPs / security
- [FIREWALL_RULES.md](./FIREWALL_RULES.md) — VLAN firewall / segmentation model
- [VLAN_TEST_RESULTS.md](./VLAN_TEST_RESULTS.md) — VLAN isolation test plan

---

**Status**: Interim wiring realized (igc1 → UniFi Port 1; Port 2=Talos VLAN 30; Port 3=TinyCA
VLAN 10; Port 4=trunk→CUDY→Ruckus). UniFi mgmt `192.168.10.20`, Ruckus mgmt `192.168.10.10`.
Awaiting PoE injector to complete Phase 2 (CUDY removal).
