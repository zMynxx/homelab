#!/usr/bin/env bash
# pki-init.sh — Generate new Homelab PKI and import into YubiKey PIV slots
#
# Run as root on the RPi with YubiKey plugged in:
#   sudo bash pki-init.sh
#
# What this does:
#   1. Resets YubiKey PIV applet (DESTRUCTIVE — wipes all existing keys)
#   2. Sets new PIN, PUK, and management key
#   3. Generates Root CA + Intermediate CA (EC P-384, 10y / 5y)
#   4. Imports keys and certs into YubiKey PIV slots 9a / 9c
#   5. Verifies the chain
#   6. Shreds private keys from disk
#   7. Exports public certs to /root/pki-export/ for backup

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
hdr()   { echo -e "${CYAN}[STEP]${NC}  $*"; }

[[ $EUID -ne 0 ]] && error "Must be run as root: sudo bash pki-init.sh"

WORKDIR=$(mktemp -d /tmp/pki-XXXXXX)
EXPORT_DIR="/root/pki-export"

cleanup() {
    if [[ -d "$WORKDIR" ]]; then
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT

hdr "Checking prerequisites"
command -v ykman   >/dev/null || error "ykman not found"
command -v step    >/dev/null || error "step CLI not found"
command -v openssl >/dev/null || error "openssl not found"
command -v shred   >/dev/null || error "shred not found"

ykman info >/dev/null 2>&1 || error "YubiKey not detected. Check USB connection and pcscd."
info "YubiKey detected"

echo ""
warn "This will RESET the YubiKey PIV applet and DESTROY all existing keys."
warn "This action is IRREVERSIBLE."
echo ""
read -r -p "Type 'yes' to confirm: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 0; }

hdr "Resetting YubiKey PIV applet"
ykman piv reset --force
info "PIV reset complete. Slots cleared, credentials at factory defaults."

echo ""
hdr "Setting PIN (6-8 chars, alphanumeric allowed)"
ykman piv access change-pin --pin 123456

echo ""
hdr "Setting PUK (6-8 chars, alphanumeric allowed)"
ykman piv access change-puk --puk 12345678

echo ""
hdr "Generating random AES256 management key (protected by PIN)"
ykman piv access change-management-key \
    --algorithm AES256 \
    --management-key 010203040506070801020304050607080102030405060708 \
    --generate \
    --protect

info "Management key set. It is stored on the YubiKey and unlocked by PIN."

hdr "Generating Root CA (EC P-384, 10 years)"
step certificate create "Homelab Root CA" \
    "$WORKDIR/root_ca.crt" \
    "$WORKDIR/root_ca.key" \
    --profile root-ca \
    --not-after 87600h \
    --kty EC \
    --curve P-384 \
    --no-password \
    --insecure
info "Root CA generated"

hdr "Generating Intermediate CA (EC P-384, 5 years)"
step certificate create "Homelab Intermediate CA" \
    "$WORKDIR/intermediate_ca.crt" \
    "$WORKDIR/intermediate_ca.key" \
    --profile intermediate-ca \
    --ca "$WORKDIR/root_ca.crt" \
    --ca-key "$WORKDIR/root_ca.key" \
    --not-after 43800h \
    --kty EC \
    --curve P-384 \
    --no-password \
    --insecure
info "Intermediate CA generated"

hdr "Importing Root CA into slot 9a"
ykman piv keys import 9a "$WORKDIR/root_ca.key"
ykman piv certificates import 9a "$WORKDIR/root_ca.crt"

hdr "Importing Intermediate CA into slot 9c"
ykman piv keys import 9c "$WORKDIR/intermediate_ca.key"
ykman piv certificates import 9c "$WORKDIR/intermediate_ca.crt"

info "Keys and certificates imported into YubiKey"

# ── Verify ────────────────────────────────────────────────────────────────────

hdr "Verifying YubiKey PIV slots"
ykman piv info

hdr "Verifying certificate chain"
openssl verify -CAfile "$WORKDIR/root_ca.crt" "$WORKDIR/intermediate_ca.crt" \
    || error "Certificate chain verification failed"
info "Chain OK: Intermediate CA is signed by Root CA"

hdr "Verifying keys match certificates in YubiKey"
ykman piv certificates export 9a "$WORKDIR/slot9a_check.crt"
ykman piv certificates export 9c "$WORKDIR/slot9c_check.crt"

openssl verify -CAfile "$WORKDIR/slot9a_check.crt" "$WORKDIR/slot9c_check.crt" \
    || error "YubiKey slot verification failed — cert mismatch"
info "YubiKey slots verified"

# ── Export public certs ───────────────────────────────────────────────────────

hdr "Exporting public certificates to ${EXPORT_DIR}"
mkdir -p "$EXPORT_DIR"
chmod 700 "$EXPORT_DIR"
cp "$WORKDIR/root_ca.crt"         "$EXPORT_DIR/root_ca.crt"
cp "$WORKDIR/intermediate_ca.crt" "$EXPORT_DIR/intermediate_ca.crt"
chmod 644 "$EXPORT_DIR"/*.crt
info "Certs exported (public — safe to distribute, back up to password manager)"

# ── Shred private keys ────────────────────────────────────────────────────────

hdr "Copying private keys to export dir"
cp "$WORKDIR/root_ca.key"         "$EXPORT_DIR/root_ca.key"
cp "$WORKDIR/intermediate_ca.key" "$EXPORT_DIR/intermediate_ca.key"
chmod 600 "$EXPORT_DIR"/*.key
warn "Private keys saved to ${EXPORT_DIR} — import into password manager then delete them from disk."

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
info "PKI initialisation complete"
echo ""
echo "  Root CA cert:         ${EXPORT_DIR}/root_ca.crt"
echo "  Intermediate CA cert: ${EXPORT_DIR}/intermediate_ca.crt"
echo ""
echo "  Root CA fingerprint:"
openssl x509 -in "$EXPORT_DIR/root_ca.crt" -noout -fingerprint -sha256 | sed 's/^/    /'
echo "  Intermediate CA fingerprint:"
openssl x509 -in "$EXPORT_DIR/intermediate_ca.crt" -noout -fingerprint -sha256 | sed 's/^/    /'
echo ""
warn "Back up both .crt files from ${EXPORT_DIR} to your password manager."
warn "SCP them to your workstation: scp tinyca:/root/pki-export/*.crt ."
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
