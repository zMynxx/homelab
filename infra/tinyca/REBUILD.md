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

## Phase 1 — Generate PKI (if YubiKey is empty)

> **Do this offline.** Use an air-gapped machine or a fresh USB-booted session.
> Generated keys never touch disk outside of this phase.

### 1.1 Prepare an offline workspace

```bash
# Create a temp workspace on an encrypted USB or RAM disk
mkdir -p /tmp/pki-offline
cd /tmp/pki-offline
```

### 1.2 Generate Root CA

```bash
step certificate create "Homelab Root CA" root_ca.crt root_ca.key \
  --profile root-ca \
  --not-after 87600h \      # 10 years
  --kty EC \
  --curve P-384 \
  --no-password \
  --insecure               # key stays in this dir temporarily, goes to YubiKey next
```

### 1.3 Generate Intermediate CA

```bash
step certificate create "Homelab Intermediate CA" intermediate_ca.crt intermediate_ca.key \
  --profile intermediate-ca \
  --ca root_ca.crt \
  --ca-key root_ca.key \
  --not-after 43800h \     # 5 years
  --kty EC \
  --curve P-384 \
  --no-password \
  --insecure
```

### 1.4 Import keys into YubiKey PIV slots

```bash
# Import root CA key → slot 9a (authentication slot, used for signing)
ykman piv keys import 9a root_ca.key
ykman piv certificates import 9a root_ca.crt

# Import intermediate CA key → slot 9c (digital signature slot)
ykman piv keys import 9c intermediate_ca.key
ykman piv certificates import 9c intermediate_ca.crt

# Verify both slots are populated
ykman piv info
```

### 1.5 Destroy key files from disk

```bash
# Keys are now in YubiKey. Remove them from disk.
shred -u root_ca.key intermediate_ca.key

# Keep the .crt files — you need to distribute them
cp root_ca.crt intermediate_ca.crt ~/Desktop/   # copy before wiping USB
```

### 1.6 Save root cert for distribution

The `root_ca.crt` must be distributed to:
- Talos machine config (`machine.files[]`)
- cert-manager `ClusterIssuer` CA bundle
- Istio `cacerts` secret

Store it in the repo (cert only, never key):
```bash
# In repo: infra/tinyca/pki/root_ca.crt  (tracked in git - it's public)
mkdir -p infra/tinyca/pki
cp root_ca.crt infra/tinyca/pki/root_ca.crt
```

---

## Phase 2 — Flash and Configure the Raspberry Pi

### 2.1 Flash OS

1. Download **Ubuntu Server 24.04 LTS (64-bit ARM)** for Raspberry Pi:
   https://ubuntu.com/download/raspberry-pi
2. Flash to SD card (or USB SSD if using USB boot):
   ```bash
   # macOS - use Raspberry Pi Imager or:
   sudo dd if=ubuntu-24.04-preinstalled-server-arm64+raspi.img of=/dev/rdisk<N> bs=4m status=progress
   ```
3. Before ejecting, mount the boot partition and pre-configure:

   **Enable SSH** (create empty file):
   ```bash
   touch /Volumes/system-boot/ssh
   ```

   **Set hostname** in `user-data` cloud-init file:
   ```yaml
   hostname: tinyca
   ```

### 2.2 First boot — basic setup

Connect via SSH (default user `ubuntu`, password `ubuntu`):

```bash
ssh ubuntu@<dhcp-assigned-ip>   # find IP from OPNsense DHCP leases

# Change password immediately
passwd

# Update system
sudo apt update && sudo apt full-upgrade -y
sudo reboot
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
scp infra/tinyca/bootstrap.sh ubuntu@192.168.10.37:~/
ssh ubuntu@192.168.10.37 'sudo bash ~/bootstrap.sh'
```

This installs: `step-ca`, `step`, YubiKey PKCS#11 libraries, `pcscd`, ufw.

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

```bash
ls /usr/lib/x86_64-linux-gnu/libykcs11.so 2>/dev/null || \
ls /usr/lib/aarch64-linux-gnu/libykcs11.so 2>/dev/null || \
find /usr/lib -name 'libykcs11*' 2>/dev/null
# Expected: /usr/lib/aarch64-linux-gnu/libykcs11.so
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

```bash
sudo mkdir -p /etc/step-ca/certs
# Copy root_ca.crt (public cert only) from your workstation
scp infra/tinyca/pki/root_ca.crt ubuntu@192.168.10.37:/tmp/root_ca.crt
sudo mv /tmp/root_ca.crt /etc/step-ca/certs/root_ca.crt
sudo chmod 644 /etc/step-ca/certs/root_ca.crt
```

---

## Phase 4 — Systemd Service

Install the systemd unit from [`deployment/step-ca.service`](deployment/step-ca.service):

```bash
scp infra/tinyca/deployment/step-ca.service ubuntu@192.168.10.37:/tmp/
ssh ubuntu@192.168.10.37 'sudo mv /tmp/step-ca.service /etc/systemd/system/ && sudo systemctl daemon-reload'
```

The service requires YubiKey presence (`After=pcscd.service`). The YubiKey PIN is passed via
a credentials file (not hardcoded):

```bash
# Create PIN file (only root-readable)
sudo bash -c 'echo -n "<your-yubikey-pin>" > /etc/step-ca/yubikey-pin'
sudo chmod 600 /etc/step-ca/yubikey-pin
sudo chown root:root /etc/step-ca/yubikey-pin
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
# From your workstation
step ca health --ca-url https://192.168.10.37:8443 --root infra/tinyca/pki/root_ca.crt
# Expected: {"status":"ok"}
```

### 6.2 Issue a test certificate

```bash
step ca certificate "test.homelab.internal" test.crt test.key \
  --ca-url https://192.168.10.37:8443 \
  --root infra/tinyca/pki/root_ca.crt \
  --provisioner acme \
  --san test.homelab.internal

# Inspect it
step certificate inspect test.crt
# Verify chain
openssl verify -CAfile infra/tinyca/pki/root_ca.crt test.crt

# Cleanup
rm test.crt test.key
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

Once step-ca is verified, distribute `root_ca.crt` everywhere:

```bash
# 1. Talos machine config patch (infra/talos/patches/custom-ca.yaml)
# 2. cert-manager ClusterIssuer CA bundle (base64 encode root_ca.crt)
# 3. Istio cacerts secret
# See infra/talos/ and gitops/ for integration details
```

---

## Security Notes

- SSH should remain enabled during setup, then **disable** it once step-ca is confirmed working
- YubiKey must be physically present to start the service
- The RPi has no value without the YubiKey — physical security of the YubiKey is the real protection
- Back up the `intermediate_ca.crt` (public cert, not key) to the repo under `infra/tinyca/pki/`
- Never store private keys on disk or in Git
