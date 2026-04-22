# OPNsense SSH Key-Based Authentication Setup

**Date:** April 22, 2026  
**Status:** Configured and ready for testing

---

## SSH Key Details

**Key Type:** ED25519 (modern, secure)  
**Private Key:** `~/.ssh/id_ed25519_opnsense`  
**Public Key:** `~/.ssh/id_ed25519_opnsense.pub`  
**Key Comment:** `opnsense-recovery-key`

**Public Key (for OPNsense):**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICw17h9ceWYrvlAd+bzBPpkLoKwfLECykIsebDcejtI6 opnsense-recovery-key
```

---

## SSH Config Entry

**Location:** `~/.ssh/config`

```
Host opnsense
    HostName 192.168.10.1
    User root
    IdentityFile ~/.ssh/id_ed25519_opnsense
    IdentitiesOnly yes
```

**Usage:**
```bash
ssh opnsense
```

---

## OPNsense Configuration Required

### 1. Add Public Key to Root User

**System → Access → Users → Edit root**

1. Scroll to **Authorized keys** section
2. Paste the public key:
   ```
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICw17h9ceWYrvlAd+bzBPpkLoKwfLECykIsebDcejtI6 opnsense-recovery-key
   ```
3. Click **Save**

### 2. Enable SSH Service

**System → Settings → Administration**

```
[Secure Shell Section]
☑ Enable Secure Shell
Listen Interfaces: LAN (192.168.10.1)
Permit Root Login: Yes
Authentication Method: Public Key + Password (recommended)
                       or Public Key Only (most secure)
SSH Port: 22
```

**Recommended:** Start with "Public Key + Password" to ensure key auth works, then switch to "Public Key Only" after testing.

Click **Save**

---

## Testing

### Test SSH Connection

```bash
ssh opnsense
```

**Expected Result:**
- No password prompt (key-based authentication)
- Direct login to OPNsense shell
- Shows OPNsense banner and shell prompt

**If it asks for password:**
- Key auth not configured correctly
- Check public key was added to root user
- Check Authentication Method includes "Public Key"
- Check firewall rules allow SSH from your network

### Verify Key Authentication

```bash
ssh -v opnsense 2>&1 | grep "Offering public key"
```

Should show:
```
debug1: Offering public key: /Users/develeap/.ssh/id_ed25519_opnsense ED25519 SHA256:ha3Bp...
debug1: Server accepts key: /Users/develeap/.ssh/id_ed25519_opnsense ED25519 SHA256:ha3Bp...
```

---

## Security Benefits

**Key-based authentication is superior to password+TOTP because:**

1. ✅ **No password transmission** - private key never leaves your machine
2. ✅ **Immune to TOTP lockout** - bypasses 2FA issues entirely
3. ✅ **Stronger cryptography** - ED25519 uses 256-bit elliptic curve
4. ✅ **Automated access** - scripts can use SSH without interaction
5. ✅ **Audit trail** - each key can be tracked and revoked individually
6. ✅ **Recovery access** - works even if web UI 2FA is broken

---

## Recovery Scenarios

### If Locked Out of Web UI (2FA Issues)

**SSH provides complete recovery access:**

```bash
# Connect via SSH
ssh opnsense

# Access OPNsense shell
/usr/local/sbin/opnsense-shell

# Option 3: Reset password
# Option 8: Shell for advanced recovery
```

### If Need to Edit Config Directly

```bash
ssh opnsense
# At shell
vi /conf/config.xml
# Make changes
/usr/local/etc/rc.reload_all
```

### If Need to Disable 2FA

```bash
ssh opnsense
sed -i '' 's/<authmode>Local Database + TOTP<\/authmode>/<authmode>Local Database<\/authmode>/' /conf/config.xml
sed -i '' '/<otp_seed>/d' /conf/config.xml
/usr/local/etc/rc.reload_all
```

---

## Key Management

### Backup Private Key

**CRITICAL:** Store private key in secure location (password manager, encrypted backup):

```bash
# Copy private key to secure storage
cat ~/.ssh/id_ed25519_opnsense
```

**If you lose this key, you'll need to:**
1. Generate new key pair
2. Access OPNsense via console/web UI
3. Replace authorized key with new public key

### Add Additional Keys (Multiple Devices)

**OPNsense supports multiple authorized keys:**

1. Generate key on second device
2. System → Access → Users → Edit root
3. Add second public key on new line in "Authorized keys"
4. Each device can authenticate with its own key

### Revoke Key Access

**To remove a key:**

1. System → Access → Users → Edit root
2. Delete the public key line from "Authorized keys"
3. Save

---

## Firewall Rules

**Ensure SSH access is allowed from Management VLAN:**

**Firewall → Rules → LAN (or Management VLAN)**

```
Action: Pass
Interface: LAN
Protocol: TCP
Source: Management VLAN network (192.168.10.0/24)
Destination: LAN address (192.168.10.1)
Destination Port: 22 (SSH)
Description: Allow SSH to OPNsense from Management VLAN
```

---

## Troubleshooting

### SSH Connection Refused

**Check:**
1. SSH enabled: System → Settings → Administration → Secure Shell ☑
2. Firewall rules allow SSH from your IP
3. Correct interface selected (LAN / Management VLAN)
4. Port 22 not blocked by upstream firewall

### Permission Denied (publickey)

**Check:**
1. Public key added to root user's Authorized keys
2. Authentication Method includes "Public Key"
3. Key file permissions: `chmod 600 ~/.ssh/id_ed25519_opnsense`
4. SSH config points to correct key file

### Still Asks for Password

**Check:**
1. Authentication Method is "Public Key Only" or "Public Key + Password"
2. Not "Password Only"
3. Public key exactly matches (no extra spaces/newlines)
4. Restart SSH service after config changes

### Verify SSH Service Running

```bash
ssh opnsense
# At shell
/etc/rc.d/sshd status
```

---

## Related Documentation

- **2FA Recovery:** `OPNSENSE_2FA_RECOVERY.md` - Single-user mode recovery
- **2FA Best Practices:** `OPNSENSE_2FA_BEST_PRACTICES.md` - Proper TOTP setup
- **Network Setup:** `NETWORK_SETUP.md` - Network architecture

---

## Change Log

**April 22, 2026:**
- Generated ED25519 SSH key pair for OPNsense access
- Created SSH config entry for easy connection (`ssh opnsense`)
- Documented public key for OPNsense configuration
- Created complete setup and testing procedures
