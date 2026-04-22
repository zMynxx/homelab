#!/usr/bin/env bash
# bootstrap.sh — TinyCA Raspberry Pi 5 initial setup
#
# Run as root on a fresh Ubuntu Server 24.04 LTS (ARM64) install:
#   sudo bash bootstrap.sh
#
# What this does:
#   1. System hardening (hostname, timezone, NTP, unattended-upgrades)
#   2. Installs step-ca, step CLI, YubiKey PKCS#11 libraries, pcscd
#   3. Creates the step-ca system user and STEPPATH directory
#   4. Configures ufw firewall (allow SSH + 8443 only)
#   5. Enables pcscd (smartcard daemon) for YubiKey

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
STEPCA_VERSION="0.27.4"     # https://github.com/smallstep/certificates/releases
STEP_VERSION="0.27.4"       # https://github.com/smallstep/cli/releases
STEPPATH="/etc/step-ca"
STEPCA_USER="step"
TIMEZONE="Asia/Jerusalem"
HOSTNAME="tinyca"
# ──────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Must be run as root (sudo bash bootstrap.sh)"

ARCH=$(uname -m)
[[ "$ARCH" != "aarch64" ]] && warn "Expected aarch64, got $ARCH — continuing anyway"

# ── 1. System basics ──────────────────────────────────────────────────────────
info "Setting hostname to ${HOSTNAME}"
hostnamectl set-hostname "$HOSTNAME"
echo "127.0.1.1 ${HOSTNAME}" >> /etc/hosts

info "Setting timezone to ${TIMEZONE}"
timedatectl set-timezone "$TIMEZONE"

info "Enabling NTP sync"
timedatectl set-ntp true

info "Updating system packages"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl \
  wget \
  jq \
  openssl \
  pcscd \
  pcsc-tools \
  libpcsclite-dev \
  yubikey-manager \
  ykcs11 \
  libykcs11-1 \
  ufw \
  unattended-upgrades \
  apt-listchanges

info "Configuring unattended security upgrades"
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF

# ── 2. Install step CLI ───────────────────────────────────────────────────────
STEP_DEB="step_linux_${STEP_VERSION}_arm64.deb"
info "Downloading step CLI v${STEP_VERSION}"
wget -q "https://dl.smallstep.com/cli/docs-cli-install/${STEP_VERSION}/${STEP_DEB}" \
  -O "/tmp/${STEP_DEB}"
dpkg -i "/tmp/${STEP_DEB}"
rm "/tmp/${STEP_DEB}"
step version

# ── 3. Install step-ca ────────────────────────────────────────────────────────
# step-ca must be built with YubiKey (PKCS#11) support.
# The official release builds include it; verify with `step-ca --help | grep yubikey`
STEPCA_DEB="step-ca_linux_${STEPCA_VERSION}_arm64.deb"
info "Downloading step-ca v${STEPCA_VERSION}"
wget -q "https://dl.smallstep.com/certificates/docs-ca-install/${STEPCA_VERSION}/${STEPCA_DEB}" \
  -O "/tmp/${STEPCA_DEB}"
dpkg -i "/tmp/${STEPCA_DEB}"
rm "/tmp/${STEPCA_DEB}"
step-ca version

# Verify YubiKey support is compiled in
if step-ca --help 2>&1 | grep -q "yubikey\|kms"; then
  info "step-ca YubiKey/KMS support confirmed"
else
  warn "Could not confirm YubiKey support in step-ca. Check build flags."
fi

# ── 4. PKCS#11 library symlink ────────────────────────────────────────────────
# step-ca references the PKCS#11 module path in ca.json. Ensure it's consistent.
YKCS11_PATH=$(find /usr/lib -name 'libykcs11.so' 2>/dev/null | head -1)
if [[ -z "$YKCS11_PATH" ]]; then
  error "libykcs11.so not found. YubiKey PKCS#11 library not installed correctly."
fi
info "YubiKey PKCS#11 library: ${YKCS11_PATH}"
# Create a stable symlink at a known path
ln -sf "$YKCS11_PATH" /usr/local/lib/libykcs11.so
info "Symlink created: /usr/local/lib/libykcs11.so → ${YKCS11_PATH}"

# ── 5. Create step-ca system user and directories ─────────────────────────────
info "Creating system user '${STEPCA_USER}'"
if ! id "$STEPCA_USER" &>/dev/null; then
  useradd --system --shell /bin/false --home-dir "$STEPPATH" --create-home "$STEPCA_USER"
fi

# Add step user to pcscd group so it can access YubiKey
usermod -aG pcscd "$STEPCA_USER" 2>/dev/null || true

info "Creating STEPPATH directories"
mkdir -p "${STEPPATH}/certs"
mkdir -p "${STEPPATH}/config"
mkdir -p "${STEPPATH}/db"
mkdir -p "${STEPPATH}/secrets"
chown -R "${STEPCA_USER}:${STEPCA_USER}" "$STEPPATH"
chmod 750 "$STEPPATH"
chmod 700 "${STEPPATH}/secrets"

# ── 6. pcscd (smartcard daemon) ───────────────────────────────────────────────
info "Enabling and starting pcscd"
systemctl enable pcscd
systemctl start pcscd

# ── 7. ufw firewall ───────────────────────────────────────────────────────────
info "Configuring ufw firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# SSH — restrict to Management VLAN only
ufw allow from 192.168.10.0/24 to any port 22 proto tcp comment "SSH from Management VLAN"

# step-ca ACME — Management, Internal, DMZ, Legacy LAN
ufw allow from 192.168.10.0/24 to any port 8443 proto tcp comment "step-ca from Management VLAN"
ufw allow from 192.168.30.0/24 to any port 8443 proto tcp comment "step-ca from Internal VLAN (cert-manager)"
ufw allow from 192.168.20.0/24 to any port 8443 proto tcp comment "step-ca from DMZ (reverse proxy)"
ufw allow from 192.168.1.0/24  to any port 8443 proto tcp comment "step-ca from Legacy LAN (migration)"

ufw --force enable
ufw status verbose

# ── 8. Udev rule for YubiKey ──────────────────────────────────────────────────
info "Adding udev rule for YubiKey"
cat > /etc/udev/rules.d/70-yubikey.rules <<'EOF'
# YubiKey — allow pcscd group access
SUBSYSTEM=="usb", ATTRS{idVendor}=="1050", MODE="0664", GROUP="pcscd"
EOF
udevadm control --reload-rules
udevadm trigger

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
info "Bootstrap complete!"
echo ""
echo "Next steps:"
echo "  1. Plug in the YubiKey and run:  ykman info"
echo "  2. Check YubiKey PIV slots:       ykman piv info"
echo "  3. Copy root_ca.crt to:           ${STEPPATH}/certs/root_ca.crt"
echo "  4. Initialize step-ca:            See REBUILD.md Phase 3"
echo "  5. Install systemd service:       deployment/step-ca.service"
echo ""
echo "STEPPATH: ${STEPPATH}"
echo "PKCS#11:  /usr/local/lib/libykcs11.so → ${YKCS11_PATH}"
echo "User:     ${STEPCA_USER}"
