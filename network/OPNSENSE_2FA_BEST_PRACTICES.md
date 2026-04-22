# OPNsense 2FA Best Practices

**Last Updated:** April 21, 2026  
**OPNsense Version:** 26.1.6

---

## Summary

This document outlines best practices for implementing TOTP 2FA on OPNsense after successfully recovering from a lockout scenario.

## Key Lessons Learned

### What Went Wrong (Initial Attempt)

1. ❌ Switched authentication server from "Local Database" to "Local Database + TOTP" **BEFORE** testing TOTP worked
2. ❌ No SSH backup access enabled
3. ❌ Didn't use System → Access → Tester to verify authentication before switching
4. ❌ Result: Complete lockout requiring single-user mode recovery

### What Worked (Successful Implementation)

1. ✅ Created TOTP authentication server with grace period position **AFTER** password
2. ✅ Generated TOTP seed and scanned QR code in authenticator app
3. ✅ **Tested authentication using System → Access → Tester BEFORE switching global auth server**
4. ✅ Verified login format: `<totp-code><password>` (e.g., `123456mypassword`)
5. ✅ Only switched global authentication server after confirming test succeeded
6. ✅ Enabled SSH as backup access method
7. ✅ Result: 2FA working perfectly, no lockout

---

## Step-by-Step 2FA Setup (Proven Procedure)

### 1. Create TOTP Authentication Server

**System → Access → Servers → Add**

```
Type: TOTP (Time based One Time Password)
Descriptive name: Local Database + TOTP
Token length: 6
Time window: 1
Grace period: 1
Grace period position: AFTER
```

**Critical:** Position **AFTER** means:
- TOTP code is entered AFTER password in the password field
- Login format: `<password><6-digit-code>`
- Example: `SecurePass123123456`

**Save**

### 2. Generate TOTP Seed for User

**System → Access → Users → Edit (root)**

1. Scroll to **OTP seed** section
2. Click **"Generate new secret (QR)"**
3. A QR code appears
4. Open authenticator app (Google Authenticator, Authy, 1Password, etc.)
5. Scan QR code
6. Verify app shows 6-digit code rotating every 30 seconds
7. **Save user**

### 3. Test Authentication (CRITICAL STEP - DO NOT SKIP)

**System → Access → Tester**

```
Authentication Server: Local Database + TOTP
Username: root
Password: <your-password><current-totp-code>
```

Example:
- Your password: `SecurePass123`
- TOTP code showing in app: `123456`
- Enter in Password field: `SecurePass123123456`

**Click "Test"**

**Expected Result:**
```
User: root authenticated successfully.
This user is a member of these groups:
admins
```

**If this fails:**
- ❌ Do NOT proceed to step 4
- Check TOTP code is current (refreshes every 30 seconds)
- Verify you're using format: `<password><code>` not `<code><password>`
- Regenerate TOTP seed and try again
- Verify time sync on your device running authenticator app

### 4. Switch Global Authentication Server

**Only after Step 3 succeeds:**

**System → Settings → Administration**

```
Authentication Server: Local Database + TOTP
```

**Save**

### 5. Test Web UI Login

1. Open **private/incognito browser window**
2. Navigate to `https://192.168.10.1:8443` (or your OPNsense URL)
3. Username: `root`
4. Password: `<password><totp-code>` (e.g., `SecurePass123123456`)
5. Click Login

**Should successfully login to OPNsense dashboard**

### 6. Enable SSH Backup Access (MANDATORY)

**System → Settings → Administration**

```
[Secure Shell Section]
☑ Enable Secure Shell
Listen Interfaces: LAN (or Management VLAN)
Permit Root Login: Yes
Permit Password Login: Yes
SSH Port: 22
```

**Save**

**Test SSH Access:**

```bash
ssh root@192.168.10.1
```

When prompted for password, enter: `<password><totp-code>`

**Should successfully login to OPNsense shell**

---

## Recovery Access Methods

With 2FA enabled, you have these recovery options:

### 1. SSH (If Enabled)

```bash
ssh root@192.168.10.1
# Password: <password><totp-code>
```

### 2. Physical Console (HDMI + Keyboard)

- Username: `root`
- Password: Your password (TOTP NOT required at console)
- Access full menu system

### 3. Serial Console (USB-C COM port)

```bash
sudo cu -l /dev/cu.usbserial-XXXXXXXX -s 115200
# Login: root
# Password: Your password (TOTP NOT required)
# Disconnect: ~.
```

### 4. Single-User Mode (If Locked Out)

See `OPNSENSE_2FA_RECOVERY.md` for detailed procedure.

**Summary:**
1. Reboot and press `3` at boot loader
2. `set boot_single="YES"` then `boot`
3. `/sbin/mount -f -u -w /`
4. Edit `/conf/config.xml` to remove TOTP
5. Reboot

---

## Important Notes

### TOTP Login Format

**Authentication Server Position:** AFTER

**Login Format:**
- Password field: `<your-password><6-digit-totp-code>`
- No spaces, no separators
- Password first, then TOTP code immediately after

**Example:**
- Your password: `MyP@ssw0rd`
- TOTP app shows: `123456`
- Enter in password field: `MyP@ssw0rd123456`

### Time Synchronization

**Critical:** TOTP relies on time synchronization.

- OPNsense uses NTP (should be configured)
- Your device running authenticator app must have correct time
- If codes don't work, check time sync on both devices

### Authenticator App Recommendations

**Recommended:**
- Google Authenticator (iOS, Android)
- Authy (iOS, Android, Desktop)
- 1Password (cross-platform, secure vault)
- Bitwarden (cross-platform, open source)

**Backup:**
- Save TOTP seed/QR code in secure location (password manager)
- If you lose device, you can re-add using saved seed

### Console Access

**Important:** Console login (physical or serial) does NOT require TOTP.

This is by design for recovery purposes:
- Console authentication uses local password only
- Web UI and SSH require password + TOTP
- This ensures you can always recover via physical access

---

## Troubleshooting

### "Login incorrect" with TOTP

**Check:**
1. Format is `<password><code>` not `<code><password>`
2. TOTP code is current (refreshes every 30 seconds)
3. Time on device is synchronized
4. Password is correct (test without TOTP at console if unsure)

### "Authentication Server" not showing TOTP option

**Fix:**
1. Verify TOTP authentication server is created (System → Access → Servers)
2. Check server is enabled
3. Reload web UI page (Ctrl+Shift+R)

### Locked out after enabling 2FA

**Recovery:**
1. Connect physical console (HDMI + keyboard or serial)
2. Use single-user mode (press `3` at boot loader)
3. Follow procedure in `OPNSENSE_2FA_RECOVERY.md`

### SSH not accepting TOTP

**Check:**
1. SSH is enabled (System → Settings → Administration → Secure Shell)
2. Using same format as web UI: `<password><code>`
3. Firewall rules allow SSH to Management VLAN
4. Try from different device/network

---

## Security Recommendations

### Do's

✅ **Enable SSH backup access** before setting up 2FA  
✅ **Test authentication** using System → Access → Tester before switching  
✅ **Use private browser window** to test login before logging out of main session  
✅ **Save TOTP seed** in secure password manager as backup  
✅ **Document recovery procedures** (done - see OPNSENSE_2FA_RECOVERY.md)  
✅ **Keep console access available** (don't disable serial/physical console)  
✅ **Use strong passwords** even with 2FA enabled  

### Don'ts

❌ **Don't switch auth server** before testing TOTP works  
❌ **Don't disable all backup access methods** (SSH, console)  
❌ **Don't assume TOTP works** without explicit testing  
❌ **Don't forget login format** (`<password><code>`, not `<code><password>`)  
❌ **Don't skip System → Access → Tester** verification step  
❌ **Don't lose access to authenticator app** without backup seed saved  

---

## Related Documentation

- **Recovery Procedure:** `OPNSENSE_2FA_RECOVERY.md` - Single-user mode config edit
- **Official Docs:** https://docs.opnsense.org/manual/how-tos/two_factor.html
- **Network Setup:** `NETWORK_SETUP.md` - Overall network architecture
- **Management Access:** `MANAGEMENT_ACCESS_SECURITY.md` - Web UI access controls

---

## Change Log

**April 21, 2026:**
- Initial documentation after successful 2FA implementation
- Documented lockout recovery via single-user mode
- Verified TOTP login format: `<password><code>` with position AFTER
- Confirmed System → Access → Tester is critical validation step
- Enabled SSH backup access (listening on Management VLAN only)
