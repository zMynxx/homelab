# YubiKey Setup & PIV Slot Management

Procedures for checking the current YubiKey state and (re)initializing PIV slots for TinyCA.

---

## Prerequisites

```bash
# macOS
brew install ykman

# Verify YubiKey is detected
ykman info
```

Expected output includes: `Serial:`, `Firmware:`, `Form factor:`, and `Applications` showing `PIV`.

---

## Step 1 — Check Current PIV State

Run this before deciding whether to regenerate PKI:

```bash
ykman piv info
```

Look for:
- **PIN retries remaining** — if 0, the PIN is locked
- **Management key** — whether it's the default or custom
- **Slot 9a** (Authentication) — should hold the Root CA cert
- **Slot 9c** (Digital Signature) — should hold the Intermediate CA cert

Export any existing certificates to inspect them:

```bash
ykman piv certificates export 9a /tmp/slot9a.crt 2>/dev/null && \
  step certificate inspect /tmp/slot9a.crt || echo "Slot 9a is empty"

ykman piv certificates export 9c /tmp/slot9c.crt 2>/dev/null && \
  step certificate inspect /tmp/slot9c.crt || echo "Slot 9c is empty"
```

**Decision:**
- Both slots have valid CA certs → skip to [Step 4](#step-4--verify-keys-match-certs)
- Slots are empty or expired → proceed to [Step 2](#step-2--reset-and-reinitialize-piv)

---

## Step 2 — Reset and Reinitialize PIV (if needed)

> ⚠️ This destroys all keys and certificates in all PIV slots. Only do this if you are
> generating a completely new PKI.
>
> **Prefer `pki-init.sh`** — it automates everything in this section (reset, PIN, PUK,
> management key, cert generation, YubiKey import, and export to `/root/pki-export/`).
> Use the manual commands below only for troubleshooting or partial re-initialization.

```bash
ykman piv reset --force
```

After reset, all PIV slots are empty and credentials return to factory defaults:
- PIN: `123456`
- PUK: `12345678`
- Management key: `010203040506070801020304050607080102030405060708` (3DES default)

### Set a strong PIN and PUK

```bash
# Change PIN (6-8 digits or alphanumeric)
ykman piv access change-pin --pin 123456

# Change PUK (used to unblock a locked PIN)
ykman piv access change-puk --puk 12345678

# Change management key to random AES256, protected by PIN
ykman piv access change-management-key \
    --algorithm AES256 \
    --management-key 010203040506070801020304050607080102030405060708 \
    --generate \
    --protect
# --generate: random 24-byte AES256 key  --protect: stored on device, unlocked by PIN
```

> **Record the PIN and PUK somewhere secure** (password manager, not Git).
> The management key with `--protect` is stored on the YubiKey itself, unlocked by PIN.

---

## Step 3 — Import CA Keys into PIV Slots

> **Note**: `pki-init.sh` handles this automatically after generating the certs.
> Run these commands manually only if you are importing pre-existing keys.

This assumes you have already generated `root_ca.crt`, `root_ca.key`,
`intermediate_ca.crt`, `intermediate_ca.key` — see REBUILD.md Phase 1.

### Slot 9a — Root CA (Authentication slot)

```bash
# Import private key
ykman piv keys import 9a root_ca.key

# Import certificate (so the slot is queryable)
ykman piv certificates import 9a root_ca.crt

# Verify
ykman piv certificates export 9a /tmp/check.crt && step certificate inspect /tmp/check.crt
```

### Slot 9c — Intermediate CA (Digital Signature slot)

```bash
ykman piv keys import 9c intermediate_ca.key
ykman piv certificates import 9c intermediate_ca.crt

# Verify
ykman piv certificates export 9c /tmp/check.crt && step certificate inspect /tmp/check.crt
```

### Destroy key files from disk

```bash
# Back up keys to your password manager FIRST (see REBUILD.md 1.2), then:
shred -uzv root_ca.key intermediate_ca.key
rm -f /tmp/check.crt /tmp/slot9a.crt /tmp/slot9c.crt
```

---

## Step 4 — Verify Keys Match Certs

Confirms the private key in each slot mathematically corresponds to the certificate:

```bash
# Export certs from YubiKey
ykman piv certificates export 9a /tmp/root_ca_yubikey.crt
ykman piv certificates export 9c /tmp/intermediate_yubikey.crt

# Verify intermediate is signed by root
openssl verify -CAfile /tmp/root_ca_yubikey.crt /tmp/intermediate_yubikey.crt
# Expected: /tmp/intermediate_yubikey.crt: OK

# Verify cert chain
step certificate verify /tmp/intermediate_yubikey.crt --roots /tmp/root_ca_yubikey.crt

# Inspect validity dates
step certificate inspect /tmp/root_ca_yubikey.crt | grep -E "Not Before|Not After|Subject:"
step certificate inspect /tmp/intermediate_yubikey.crt | grep -E "Not Before|Not After|Subject:"

rm /tmp/root_ca_yubikey.crt /tmp/intermediate_yubikey.crt
```

---

## Step 5 — Test Signing via PKCS#11

Before configuring step-ca, confirm the YubiKey can sign via PKCS#11:

```bash
# Find PKCS#11 module
YKCS11=$(find /usr/lib -name 'libykcs11.so' 2>/dev/null | head -1)
echo "Module: $YKCS11"

# List PKCS#11 slots
pkcs11-tool --module "$YKCS11" --list-slots

# List objects in slots
pkcs11-tool --module "$YKCS11" --list-objects

# Test sign operation (requires PIN)
echo "test" | pkcs11-tool --module "$YKCS11" \
  --sign --slot 1 --mechanism ECDSA \
  --id 03 \          # slot 9c object ID
  --login && echo "Signing works" || echo "Signing FAILED"
```

---

## Slot Reference

| PIV Slot | Hex | Usage in TinyCA | Key Type |
|----------|-----|-----------------|----------|
| 9a | `01` | Root CA private key | EC P-384 |
| 9c | `03` | Intermediate CA private key | EC P-384 |
| 9d | `04` | Reserved / unused | — |
| 9e | `05` | Reserved / unused | — |

---

## Troubleshooting

### PIN locked (0 retries)

```bash
# Unblock PIN using PUK
ykman piv access unblock-pin
# If PUK also locked: full reset required (ykman piv reset)
```

### YubiKey not detected on RPi

```bash
# Check pcscd is running
sudo systemctl status pcscd

# Check USB device list
lsusb | grep -i yubico

# Check pcsc sees the card
pcsc_scan
```

### step-ca fails with "no such object" or PKCS#11 error

1. Confirm YubiKey is plugged in
2. Confirm pcscd is running: `systemctl status pcscd`
3. Confirm YUBIKEY_PIN env var / PIN file is correct
4. Confirm the slot IDs in `ca.json` match what's in the YubiKey (`ykman piv info`)

### Lost PIN but have PUK

```bash
ykman piv access unblock-pin --puk <puk> --new-pin <new-pin>
```

### Lost both PIN and PUK

Full PIV reset is required. The CA keys will be destroyed. You must regenerate PKI from scratch
(REBUILD.md Phase 1) and re-bootstrap the cluster PKI.
