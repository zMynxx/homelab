# TinyCA Rebuild Guide

Complete procedure to rebuild the Step-CA Raspberry Pi from scratch. Covers OS setup, YubiKey
state assessment, PKI generation, step-ca installation, and verification.

**Target state after this guide:**
- RPi 5 running Ubuntu Server 24.04 LTS (ARM64)
- Static IP `192.168.10.37` on VLAN 10 (Management)
- step-ca listening on port `8443` (HTTPS)
- Root CA private key stored in YubiKey PIV slot 9a
- Intermediate CA private key stored in YubiKey PIV slot 9c
- ACME provisioner active for cert-manager integration
- systemd service that requires YubiKey presence to start

---

## Prerequisites

On your workstation, install the Smallstep CLI:
```bash
# macOS
brew install step

# Verify
step version
```

---

## Phase 0 — Assess YubiKey State

Before flashing anything, check if your YubiKey still has usable CA keys.
See [`yubikey-setup.md`](yubikey-setup.md) for full YubiKey procedures.

```bash
# On your workstation with YubiKey plugged in
ykman info                          # confirm YubiKey is detected
ykman piv info                      # show PIV slots and stored certificates
ykman piv certificates export 9a root_ca.crt 2>/dev/null && echo "SLOT 9a HAS CERT" || echo "SLOT 9a EMPTY"
ykman piv certificates export 9c intermediate_ca.crt 2>/dev/null && echo "SLOT 9c HAS CERT" || echo "SLOT 9c EMPTY"
```

**Decision tree:**
- **Both slots have certs** → skip Phase 1 (PKI generation), go to Phase 2
- **Slots empty / unknown** → run Phase 1 to generate fresh PKI

---

## Phase 1 — Generate PKI and Initialize YubiKey

> **Run directly on the RPi** with the YubiKey plugged in. The `pki-init.sh` script handles
> everything: PIV reset, PIN/PUK/management key setup, cert generation, YubiKey import, and export.

### 1.1 Copy and run pki-init.sh

```bash
scp infra/tinyca/pki-init.sh zmynx@192.168.1.37:~/
ssh zmynx@192.168.1.37 sudo bash ~/pki-init.sh
```

The script will prompt you to:
1. Confirm the destructive PIV reset
2. Set a new PIN (6–8 chars, alphanumeric)
3. Set a new PUK (6–8 chars, alphanumeric)
4. Enter the PIN once more for management key protection

On completion, find in `/root/pki-export/`:
- `root_ca.crt` / `root_ca.key`
- `intermediate_ca.crt` / `intermediate_ca.key`

### 1.2 Back up keys and certs

SCP to your workstation and import into your password manager:

```bash
scp zmynx@192.168.1.37:/root/pki-export/*.crt .
scp zmynx@192.168.1.37:/root/pki-export/*.key .
```

Then encrypt and commit to the repo:

```bash
# Files land in infra/tinyca/pki/pki-export/*.secret (gitignored)
# Build the SOPS-encrypted backup
python3 -c "
import os, sys
files = {
  'root_ca_crt': open('infra/tinyca/pki/pki-export/root_ca.crt.secret').read(),
  'root_ca_key': open('infra/tinyca/pki/pki-export/root_ca.key.secret').read(),
  'intermediate_ca_crt': open('infra/tinyca/pki/pki-export/intermediate_ca.crt.secret').read(),
  'intermediate_ca_key': open('infra/tinyca/pki/pki-export/intermediate_ca.key.secret').read(),
}
for k, v in files.items():
    print(f'{k}: |')
    for line in v.splitlines(): print('  ' + line)
" > infra/tinyca/pki/pki-export/pki-export.sops.yaml
SOPS_AGE_KEY_FILE=key.txt.secret sops --encrypt --in-place infra/tinyca/pki/pki-export/pki-export.sops.yaml
```

### 1.3 Shred private keys from RPi

```bash
ssh zmynx@192.168.1.37 sudo shred -uzv /root/pki-export/root_ca.key /root/pki-export/intermediate_ca.key
```

Public certs (`*.crt`) may stay in `/root/pki-export/` — they are not sensitive.

---

## Phase 2 — Flash and Configure the Raspberry Pi

### 2.1 Flash OS

1. Download **Ubuntu Server 24.04 LTS (64-bit ARM)** for Raspberry Pi:
   https://ubuntu.com/download/raspberry-pi
2. Flash to SD card using Raspberry Pi Imager (or `dd`)
3. Before ejecting, overwrite the `user-data` file on the `system-boot` partition with the
   pre-configured cloud-init from the repo:

   ```bash
   # Decrypt and write the cloud-init user-data
   SOPS_AGE_KEY_FILE=key.txt.secret sops --decrypt --extract '["user_data"]' \
     infra/tinyca/pki/secrets.sops.yaml > /Volumes/system-boot/user-data
   # OR — use the plaintext user-data.secret directly (gitignored)
   cp infra/tinyca/user-data.secret /Volumes/system-boot/user-data
   ```

   This pre-configures: hostname `tinyca`, user `zmynx`, SSH public key auth, password.

### 2.2 First boot

Boot the RPi and find its DHCP-assigned IP from OPNsense. SSH in:

```bash
ssh zmynx@<dhcp-ip>

# Verify step and step-ca are installed (done by bootstrap.sh via cloud-init)
step version
step-ca version
```

If bootstrap.sh was not run via cloud-init, run it manually:

```bash
scp infra/tinyca/bootstrap.sh zmynx@<dhcp-ip>:~/
ssh zmynx@<dhcp-ip> sudo bash ~/bootstrap.sh
```

### 2.3 Static IP on VLAN 10

Edit netplan config:

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.10.37/24
      routes:
        - to: default
          via: 192.168.10.1
      nameservers:
        addresses:
          - 192.168.10.1    # OPNsense / AdGuard
        search:
          - homelab.internal
```

```bash
sudo netplan apply
```

> **Note**: The RPi must be connected to a switch port tagged for VLAN 10. If still on legacy LAN
> (untagged), set `192.168.1.37/24` with gateway `192.168.1.1` as a temporary address, then
> move the switch port to VLAN 10 and update.

### 2.4 Run bootstrap script

Copy and run [`bootstrap.sh`](bootstrap.sh):

```bash
scp infra/tinyca/bootstrap.sh zmynx@192.168.10.37:~/
ssh zmynx@192.168.10.37 'sudo bash ~/bootstrap.sh'
```

This installs: `step` v0.30.2, `step-ca` v0.30.2 (from GitHub releases), YubiKey PKCS#11 libraries (`libykcs11`, `yubico-piv-tool`), `pcscd`, `ykman`, ufw.

---

## Phase 3 — Initialize step-ca

After bootstrap.sh completes, proceed with CA initialization.

### 3.1 Plug in YubiKey

Insert the YubiKey into the RPi. Verify it's detected:

```bash
ssh ubuntu@192.168.10.37
ykman info
```

### 3.2 Find the PKCS#11 module path

`bootstrap.sh` creates a symlink at `/usr/local/lib/libykcs11.so` pointing to the platform
library. Verify it exists:

```bash
ls -la /usr/local/lib/libykcs11.so
# Expected: /usr/local/lib/libykcs11.so -> /usr/lib/aarch64-linux-gnu/libykcs11.so.2
```

### 3.3 Initialize step-ca with YubiKey

```bash
# Set STEPPATH (step-ca working directory)
export STEPPATH=/etc/step-ca

# Initialize CA - uses YubiKey slot 9c (intermediate) for signing
step ca init \
  --name "Homelab CA" \
  --dns "192.168.10.37" \
  --dns "tinyca.homelab.internal" \
  --address ":8443" \
  --provisioner "acme" \
  --kms "yubikey:slot-id=9c" \
  --root /tmp/root_ca.crt \             # root cert (not key) 
  --no-db
```

> If `step ca init` doesn't support direct YubiKey init, use the manual config approach
> in section 3.4 below.

### 3.4 Manual config (alternative to 3.3)

If the init wizard doesn't support YubiKey directly, initialize without YubiKey first, then
edit the config:

```bash
# Initialize with software key (temp)
step ca init \
  --name "Homelab CA" \
  --dns "192.168.10.37,tinyca.homelab.internal" \
  --address ":8443" \
  --provisioner "acme"

# Then edit /etc/step-ca/config/ca.json to point key to YubiKey
# See the ca.json template below
```

**`/etc/step-ca/config/ca.json`** (final form):

```json
{
  "root": "/etc/step-ca/certs/root_ca.crt",
  "federatedRoots": [],
  "crt": "/etc/step-ca/certs/intermediate_ca.crt",
  "key": "yubikey:slot-id=9c",
  "kms": {
    "type": "yubikey",
    "pin": "{{ .Env.YUBIKEY_PIN }}"
  },
  "address": ":8443",
  "dnsNames": [
    "192.168.10.37",
    "tinyca.homelab.internal"
  ],
  "logger": {
    "format": "json"
  },
  "db": {
    "type": "badgerv2",
    "dataSource": "/etc/step-ca/db"
  },
  "authority": {
    "provisioners": [
      {
        "type": "ACME",
        "name": "acme",
        "forceCN": true
      },
      {
        "type": "JWK",
        "name": "admin",
        "key": {
          "use": "sig",
          "kty": "EC",
          "crv": "P-256",
          "alg": "ES256"
        },
        "encryptedKey": "..."
      }
    ]
  },
  "tls": {
    "cipherSuites": [
      "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
      "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
    ],
    "minVersion": 1.2,
    "maxVersion": 1.3,
    "renegotiation": false
  }
}
```

### 3.5 Copy root cert to step-ca

Extract the root cert from the SOPS backup and copy it to the RPi:

```bash
SOPS_AGE_KEY_FILE=key.txt.secret sops --decrypt --extract '["root_ca_crt"]' \
  infra/tinyca/pki/pki-export/pki-export.sops.yaml > /tmp/root_ca.crt
scp /tmp/root_ca.crt zmynx@192.168.10.37:/tmp/root_ca.crt
ssh zmynx@192.168.10.37 'sudo mkdir -p /etc/step-ca/certs && sudo mv /tmp/root_ca.crt /etc/step-ca/certs/root_ca.crt && sudo chmod 644 /etc/step-ca/certs/root_ca.crt'
rm /tmp/root_ca.crt
```

---

## Phase 4 — Systemd Service

Install the systemd unit from [`deployment/step-ca.service`](deployment/step-ca.service):

```bash
scp infra/tinyca/deployment/step-ca.service zmynx@192.168.10.37:/tmp/
ssh zmynx@192.168.10.37 'sudo mv /tmp/step-ca.service /etc/systemd/system/ && sudo systemctl daemon-reload'
```

The service requires YubiKey presence (`After=pcscd.service`). The YubiKey PIN is passed via
`/etc/step-ca/secrets/yubikey-pin` (read-only to the `step` service user):

```bash
# Create secrets dir and PIN file
ssh zmynx@192.168.10.37 'sudo mkdir -p /etc/step-ca/secrets'
# Write PIN (replace <pin> with your actual PIN)
ssh zmynx@192.168.10.37 'sudo bash -c "echo -n <pin> > /etc/step-ca/secrets/yubikey-pin && chmod 640 /etc/step-ca/secrets/yubikey-pin && chown root:step /etc/step-ca/secrets/yubikey-pin"'
```

Enable and start:

```bash
sudo systemctl enable step-ca
sudo systemctl start step-ca
sudo systemctl status step-ca
```

---

## Phase 5 — Firewall (OPNsense)

step-ca lives on Management VLAN (`192.168.10.37`) but must be reachable from every network
that needs certificates. The CA does **not** need to be co-located with its clients — only
port `8443` needs to be reachable.

### Why the CA stays in Management VLAN

Putting the CA in the DMZ (VLAN 20) would be a security regression: a compromised DMZ service
would be on the same segment as the root of trust. Management VLAN is the correct placement;
access is controlled by explicit firewall rules below.

### Required firewall rules

Add these rules in OPNsense → Firewall → Rules on each source interface:

**opt6 (VLAN 10 — Management)** — already has full access, no rule needed.

**opt5 (VLAN 30 — Internal)** — cert-manager and Talos nodes:
```
Action:      Pass
Interface:   opt5 (VLAN30_Internal)
Protocol:    TCP
Source:      VLAN30_Internal net
Destination: 192.168.10.37
Dest port:   8443
Description: Allow Internal → step-ca ACME/PKI
```

**opt4 (VLAN 20 — DMZ)** — reverse proxy ACME renewal:
```
Action:      Pass
Interface:   opt4 (VLAN20_DMZ)
Protocol:    TCP
Source:      VLAN20_DMZ net
Destination: 192.168.10.37
Dest port:   8443
Description: Allow DMZ → step-ca ACME only
```
> This is the only exception to the DMZ isolation rule. It is a single-port, single-destination
> allow. The CA never initiates connections back into the DMZ.

**LAN (legacy, 192.168.1.x)** — workstation access during migration:
```
Action:      Pass
Interface:   LAN
Protocol:    TCP
Source:      LAN net
Destination: 192.168.10.37
Dest port:   8443
Description: Allow LAN → step-ca (migration period)
```
> Remove this rule once all devices are on their target VLANs.

### Verify reachability after applying rules

```bash
# From a DMZ device (or simulate from workstation via correct VLAN):
curl -k https://192.168.10.37:8443/acme/acme/directory

# From an Internal VLAN device / Talos node:
step ca health --ca-url https://192.168.10.37:8443 --root /path/to/root_ca.crt
```

---

## Phase 6 — Verification

### 6.1 Health check

```bash
# From your workstation — extract root cert first
SOPS_AGE_KEY_FILE=key.txt.secret sops --decrypt --extract '["root_ca_crt"]' \
  infra/tinyca/pki/pki-export/pki-export.sops.yaml > /tmp/root_ca.crt
step ca health --ca-url https://192.168.10.37:8443 --root /tmp/root_ca.crt
# Expected: {"status":"ok"}
rm /tmp/root_ca.crt
```

### 6.2 Issue a test certificate

```bash
SOPS_AGE_KEY_FILE=key.txt.secret sops --decrypt --extract '["root_ca_crt"]' \
  infra/tinyca/pki/pki-export/pki-export.sops.yaml > /tmp/root_ca.crt

step ca certificate "test.homelab.internal" test.crt test.key \
  --ca-url https://192.168.10.37:8443 \
  --root /tmp/root_ca.crt \
  --provisioner acme \
  --san test.homelab.internal

# Inspect it
step certificate inspect test.crt
# Verify chain
openssl verify -CAfile /tmp/root_ca.crt test.crt

# Cleanup
rm test.crt test.key /tmp/root_ca.crt
```

### 6.3 ACME directory endpoint

```bash
curl -k https://192.168.10.37:8443/acme/acme/directory | jq .
```

### 6.4 Register DNS entry in AdGuard

Add a static DNS rewrite in AdGuard (OPNsense → `http://192.168.10.1:3000`):
```
tinyca.homelab.internal → 192.168.10.37
```

---

## Post-Setup: Distribute Root CA

Once step-ca is verified, distribute `root_ca.crt` everywhere. Extract it from SOPS first:

```bash
SOPS_AGE_KEY_FILE=key.txt.secret sops --decrypt --extract '["root_ca_crt"]' \
  infra/tinyca/pki/pki-export/pki-export.sops.yaml > /tmp/root_ca.crt

# 1. Talos machine config patch (infra/talos/patches/custom-ca.yaml)
# 2. cert-manager ClusterIssuer CA bundle (base64 encode root_ca.crt)
# 3. Istio cacerts secret
# See infra/talos/ and gitops/ for integration details

rm /tmp/root_ca.crt
```

---

## Security Notes

- SSH should remain enabled during setup, then **disable** it once step-ca is confirmed working
- YubiKey must be physically present to start the service
- The RPi has no value without the YubiKey — physical security of the YubiKey is the real protection
- Back up the `intermediate_ca.crt` (public cert, not key) to the repo under `infra/tinyca/pki/`
- Never store private keys on disk or in Git
