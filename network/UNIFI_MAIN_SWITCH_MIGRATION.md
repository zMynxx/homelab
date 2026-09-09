# UniFi Main Switch & CUDY Removal — Migration

**Status**: Complete — CUDY removed, Ruckus on PoE injector, UniFi is sole switch
**Last Updated**: 2026-09-07
**Goal**: Remove the CUDY PoE switch, make the UniFi USW-Flex-2.5G-5 the single main switch.

---

## Why

The CUDY 16-port PoE switch is unmanaged — no VLAN awareness, no monitoring. The UniFi
USW-Flex-2.5G-5 is a managed, VLAN-capable switch (5x 2.5GbE) and should be the main
distribution switch. The only reason CUDY cannot be removed immediately is that it currently
provides **PoE power to the Ruckus R720 AP**. Once the PoE injector arrives, CUDY becomes
redundant and is removed.

---

## Current (Realized) Topology — Final

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
                        │  UniFi 2.5G-5    │  (sole switch — Port 5 = PoE in)
                        ├──────────────────┤
                        │ Port 1  trunk ← OPNsense igc1 (VLAN 10/20/30)
                        │ Port 2  access VLAN 30 → TuringPi 2 (Talos cluster)
                        │ Port 3  access VLAN 10 → RPi-TinyCA (Management)
                        │ Port 4  trunk → PoE injector → Ruckus R720
                        │ Port 5  PoE IN (switch power — not a data port)
                        └──────────────────┘
```

**Key points:**
- OPNsense **igc1** is the trunk to UniFi **Port 1** (carries tagged VLAN 10/20/30 + untagged
  legacy LAN). There is **no igc2 link**.
- **TuringPi 2** (Talos) → UniFi **Port 2**, access on **VLAN 30**.
- **RPi-TinyCA** → UniFi **Port 3**, access on **VLAN 10** (Management).
- **Ruckus R720** → PoE injector → UniFi **Port 4** (trunk, VLANs 10/20/30). CUDY removed.
- **Port 5** is the PoE input that powers the UniFi switch itself — not a data port.

---

## Final Topology — Realized 2026-09-07

CUDY has been removed. Ruckus is powered by the PoE injector and connects directly to
UniFi Port 4 (trunk). This is the permanent wiring.

---

## UniFi Switch Port Map

| Port | Connection | Mode |
|------|-----------|------|
| **1** | Uplink — OPNsense `igc1` | Trunk (VLANs 10/20/30 + untagged) |
| **2** | TuringPi 2 (Talos cluster) | Access — VLAN 30 |
| **3** | RPi-TinyCA | Access — VLAN 10 (Management) |
| **4** | PoE injector → Ruckus R720 | Trunk (VLANs 10/20/30) |
| **5** | PoE IN — switch power | Not a data port |

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

### Phase 2 — Final (complete as of 2026-09-07)

8. [x] Power Ruckus with the PoE injector.
9. [x] Connect Ruckus **directly** to UniFi Port 4 (trunk), removing CUDY from the path.
10. [x] Remove the CUDY from the setup.
11. [x] Migrate Ruckus management to `192.168.10.10`.
12. [x] Verify all VLANs + SSID segmentation per [VLAN_TEST_RESULTS.md](./VLAN_TEST_RESULTS.md). — all three VLANs passed 2026-09-07.

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

**Status**: Complete. CUDY removed. Wiring: igc1 → UniFi Port 1 (trunk); Port 2 = TuringPi 2
(VLAN 30); Port 3 = RPi-TinyCA (VLAN 10); Port 4 = trunk → PoE injector → Ruckus R720;
Port 5 = PoE IN (switch power). UniFi mgmt `192.168.10.20`, Ruckus mgmt `192.168.10.10`.
Remaining: VLAN isolation re-verification.
