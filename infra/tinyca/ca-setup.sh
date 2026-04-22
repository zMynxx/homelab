#!/usr/bin/env bash
# ca-setup.sh — Configure step-ca with YubiKey KMS and start the service
#
# Run as root on the RPi after bootstrap.sh and pki-init.sh have completed:
#   sudo bash ca-setup.sh
#
# What this does:
#   1. Validates prerequisites (step-ca binary, YubiKey, slot 9c, export certs)
#   2. Prompts for YubiKey PIN and writes it to the secrets directory
#   3. Installs root and intermediate CA certs into STEPPATH
#   4. Writes ca.json (YubiKey KMS, ACME provisioner)
#   5. Installs and starts step-ca.service
#   6. Runs a health check

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
hdr()   { echo -e "${CYAN}[STEP]${NC}  $*"; }

[[ $EUID -ne 0 ]] && error "Must be run as root: sudo bash ca-setup.sh"

STEPPATH="/etc/step-ca"
EXPORT_DIR="/root/pki-export"
STEP_USER="step"
CA_URL="https://192.168.10.37:8443"

# ── Prerequisites ──────────────────────────────────────────────────────────────

hdr "Checking prerequisites"

command -v step-ca >/dev/null || error "step-ca not found — run bootstrap.sh first"
command -v ykman   >/dev/null || error "ykman not found — run bootstrap.sh first"
command -v openssl >/dev/null || error "openssl not found"

info "step-ca: $(step-ca version 2>&1 | head -1)"

# YubiKey must be present
ykman info >/dev/null 2>&1 || error "YubiKey not detected. Check USB connection and pcscd status."
info "YubiKey detected"

# Slot 9c must have the Intermediate CA
if ykman piv certificates export 9c /tmp/_ca_check.crt 2>/dev/null; then
    SLOT9C_SUBJECT=$(openssl x509 -in /tmp/_ca_check.crt -noout -subject 2>/dev/null)
    rm -f /tmp/_ca_check.crt
    info "Slot 9c: ${SLOT9C_SUBJECT}"
    echo "$SLOT9C_SUBJECT" | grep -qi "Intermediate" \
        || error "Slot 9c does not contain an Intermediate CA cert — run pki-init.sh first"
else
    rm -f /tmp/_ca_check.crt
    error "YubiKey slot 9c is empty — run pki-init.sh first"
fi

# Export certs must exist on disk
[[ -f "${EXPORT_DIR}/root_ca.crt" ]]         || error "Missing ${EXPORT_DIR}/root_ca.crt"
[[ -f "${EXPORT_DIR}/intermediate_ca.crt" ]] || error "Missing ${EXPORT_DIR}/intermediate_ca.crt"
info "Export certs found in ${EXPORT_DIR}"

# step user must exist (created by bootstrap.sh)
id "$STEP_USER" &>/dev/null || error "User '${STEP_USER}' not found — run bootstrap.sh first"

# ── YubiKey PIN ────────────────────────────────────────────────────────────────

hdr "YubiKey PIN"
echo ""
read -r -s -p "Enter YubiKey PIV PIN: " YUBIKEY_PIN
echo ""
read -r -s -p "Confirm PIN:           " YUBIKEY_PIN_CONFIRM
echo ""

[[ -n "$YUBIKEY_PIN" ]]                        || error "PIN cannot be empty"
[[ "$YUBIKEY_PIN" == "$YUBIKEY_PIN_CONFIRM" ]] || error "PINs do not match"

# ── Directory permissions ──────────────────────────────────────────────────────

hdr "Ensuring directory structure and permissions"

# bootstrap.sh creates these, but be idempotent
mkdir -p "${STEPPATH}/certs" "${STEPPATH}/config" "${STEPPATH}/secrets" "${STEPPATH}/db"
chown -R root:root "${STEPPATH}"
chmod 750 "${STEPPATH}" "${STEPPATH}/certs" "${STEPPATH}/config" "${STEPPATH}/db"
chmod 700 "${STEPPATH}/secrets"

info "Permissions set"

# ── Install CA certificates ────────────────────────────────────────────────────

hdr "Installing CA certificates"

install -o root -g root -m 644 \
    "${EXPORT_DIR}/root_ca.crt"         "${STEPPATH}/certs/root_ca.crt"
install -o root -g root -m 644 \
    "${EXPORT_DIR}/intermediate_ca.crt" "${STEPPATH}/certs/intermediate_ca.crt"

# Verify they are valid X.509 certs
openssl x509 -in "${STEPPATH}/certs/root_ca.crt"         -noout || error "root_ca.crt is not valid X.509"
openssl x509 -in "${STEPPATH}/certs/intermediate_ca.crt" -noout || error "intermediate_ca.crt is not valid X.509"

# Verify chain
openssl verify -CAfile "${STEPPATH}/certs/root_ca.crt" "${STEPPATH}/certs/intermediate_ca.crt" \
    || error "Certificate chain verification failed"

info "CA certificates installed and chain verified"

# ── Write PIN to secrets ───────────────────────────────────────────────────────

hdr "Writing PIN secrets"

# Backup copy of the PIN — not used by the service (PIN is embedded in ca.json),
# but kept here as a plaintext reference in the secured secrets directory.
printf '%s' "$YUBIKEY_PIN" > "${STEPPATH}/secrets/yubikey-pin"
chmod 600 "${STEPPATH}/secrets/yubikey-pin"
chown root:root "${STEPPATH}/secrets/yubikey-pin"

info "PIN written to ${STEPPATH}/secrets/yubikey-pin (backup reference)"

# ── Write ca.json ──────────────────────────────────────────────────────────────

hdr "Writing ca.json"

cat > "${STEPPATH}/config/ca.json" <<'EOF'
{
  "root": "/etc/step-ca/certs/root_ca.crt",
  "federatedRoots": null,
  "crt": "/etc/step-ca/certs/intermediate_ca.crt",
  "key": "yubikey:slot-id=9c",
  "kms": {
    "type": "yubikey",
    "pin": "__YUBIKEY_PIN__"
  },
  "address": ":8443",
  "dnsNames": [
    "192.168.10.37",
    "tinyca.opnsense.internal"
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
        "forceCN": true,
        "claims": {
          "minTLSCertDuration": "1h",
          "defaultTLSCertDuration": "2160h",
          "maxTLSCertDuration": "8760h"
        }
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
EOF

python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    c = json.load(f)
c['kms']['pin'] = sys.argv[2]
with open(sys.argv[1], 'w') as f:
    json.dump(c, f, indent=2)
" "${STEPPATH}/config/ca.json" "${YUBIKEY_PIN}"

# Wipe PIN from memory now that it's been written
YUBIKEY_PIN=""
YUBIKEY_PIN_CONFIRM=""
unset YUBIKEY_PIN YUBIKEY_PIN_CONFIRM

chmod 640 "${STEPPATH}/config/ca.json"
chown root:root "${STEPPATH}/config/ca.json"
info "ca.json written"

# ── Install systemd service ────────────────────────────────────────────────────

hdr "Installing step-ca.service"

cat > /etc/systemd/system/step-ca.service <<'EOF'
[Unit]
Description=step-ca Certificate Authority
Documentation=https://smallstep.com/docs/step-ca/
After=network-online.target pcscd.service
Wants=network-online.target
Requires=pcscd.service

[Service]
Type=simple
User=root
Group=root
Environment=STEPPATH=/etc/step-ca
WorkingDirectory=/etc/step-ca

ExecStartPre=+/bin/sh -c 'ykman info > /dev/null 2>&1 || (echo "YubiKey not detected" && exit 1)'
ExecStart=/usr/bin/step-ca /etc/step-ca/config/ca.json

Restart=on-failure
RestartSec=10
TimeoutStartSec=30
TimeoutStopSec=30

StandardOutput=journal
StandardError=journal
SyslogIdentifier=step-ca

NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/etc/step-ca/db /etc/step-ca/certs
ReadOnlyPaths=/etc/step-ca/config /etc/step-ca/secrets

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
info "step-ca.service installed"

# ── Enable and start ───────────────────────────────────────────────────────────

hdr "Enabling and starting step-ca"

systemctl enable step-ca

# If already running, restart to pick up new config
if systemctl is-active --quiet step-ca 2>/dev/null; then
    warn "step-ca already running — restarting to apply new config"
    systemctl restart step-ca
else
    systemctl start step-ca
fi

# Wait for startup
sleep 4

if systemctl is-active --quiet step-ca; then
    info "step-ca is running"
else
    echo ""
    error "step-ca failed to start. Check logs:
    journalctl -u step-ca -n 50 --no-pager"
fi

# ── Health check ───────────────────────────────────────────────────────────────

hdr "Health check"

sleep 2

HEALTH=$(curl -sk https://127.0.0.1:8443/health 2>/dev/null || true)
if echo "$HEALTH" | grep -q '"status":"ok"'; then
    info "Health check passed"
else
    warn "Health endpoint returned: ${HEALTH:-<no response>}"
    warn "CA may still be starting up. Check: journalctl -u step-ca -n 30 --no-pager"
fi

ACME_DIR=$(curl -sk https://127.0.0.1:8443/acme/acme/directory 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print('OK — newNonce: '+d['newNonce'])" \
    2>/dev/null || echo "not available yet")
info "ACME directory: ${ACME_DIR}"

# ── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
info "step-ca setup complete"
echo ""
echo "  CA URL:             ${CA_URL}"
echo "  ACME endpoint:      ${CA_URL}/acme/acme/directory"
echo "  Root cert:          ${STEPPATH}/certs/root_ca.crt"
echo "  Intermediate cert:  ${STEPPATH}/certs/intermediate_ca.crt"
echo "  Signing key:        YubiKey slot 9c (EC P-384)"
echo "  Provisioner:        ACME (name: acme)"
echo "  DB:                 ${STEPPATH}/db (badgerv2)"
echo ""
echo "  Logs:     journalctl -u step-ca -f"
echo "  Status:   systemctl status step-ca"
echo ""
ROOT_FP=$(openssl x509 -in "${STEPPATH}/certs/root_ca.crt" -noout -fingerprint -sha256 2>/dev/null | sed 's/^/  /')
echo "  Root CA fingerprint:"
echo "$ROOT_FP"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
