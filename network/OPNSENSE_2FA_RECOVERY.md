# OPNsense 2FA Authentication Lockout - Recovery Documentation

**Date:** April 21, 2026  
**OPNsense Version:** 26.1.6  
**Issue:** User locked out after enabling TOTP 2FA without proper verification

---

## Problem Summary

User attempted to enable 2FA (TOTP) on OPNsense web UI but became locked out during the process.

### What Happened

1. ✅ Generated TOTP seed for root user in **System → Access → Users**
2. ✅ Scanned QR code with authenticator app
3. ❌ Changed authentication server in **System → Settings → Administration** from "Local Database" to "Local Database + TOTP" **before verifying TOTP worked**
4. **Result:** Username/password authentication fails before reaching 2FA prompt

### Root Cause

OPNsense requires TOTP validation when "Local Database + TOTP" authentication server is selected. However, if the TOTP seed wasn't properly verified before switching, or if there's a mismatch, authentication fails completely at the password step.

---

## Recovery Attempts

### ✅ Successful Steps

1. **API Access Confirmed**
   - OPNsense API working with credentials from environment variables
   - Can download current configuration via `/api/core/backup/download/this`

2. **Configuration File Retrieved and Modified**
   - Downloaded `/conf/config.xml` (98KB)
   - Located authentication settings:
     ```xml
     <authmode>Local Database + TOTP</authmode>
     <authserver>
       <refid>69e7cd2ae8c19</refid>
       <type>totp</type>
       <name>Local Database + TOTP</name>
       ...
     </authserver>
     ```
   - Root user had TOTP seed: `<otp_seed>XSPS2Q2UINQCEDL6N6Z6ONGSGTIPBMIU</otp_seed>`

3. **Created Fixed Configuration**
   - Changed `<authmode>Local Database + TOTP</authmode>` → `<authmode>Local Database</authmode>`
   - Removed entire `<authserver>` section (lines 321-329)
   - Removed `<otp_seed>` from root user
   - Saved to `/tmp/opnsense-config.xml`

### ❌ Failed Recovery Methods

**API Restore Endpoint Not Available:**
- Tested `/api/core/backup/restore` - **Endpoint not found**
- Tested `/api/core/backup/import` - **Endpoint not found**  
- Tested `/api/core/backup/upload` - **Endpoint not found**
- Tested `/api/backup/restore` - **Endpoint not found**
- Tested multiple parameter variations (`conffile`, `file`, `backup_file`) - All failed

**Web UI Restore Blocked:**
- Web UI requires authenticated session (can't log in)
- CSRF token protection prevents direct POST
- API credentials don't work for web UI PHP pages

**No User Management API:**
- Cannot create new admin user via API
- No endpoints found for user creation/modification
- Cannot bypass TOTP by adding a non-TOTP user

**SSH Disabled:**
- User confirmed SSH access is disabled
- Cannot use `/usr/local/sbin/opnsense-shell` for password reset

**Physical Console Not Working:**
- HDMI output not working with Azorpa portable monitor
- Mini HDMI → HDMI cable tested, no display

---

## Available Recovery Options

### Option 1: Single-User Mode Config Edit (PROVEN SUCCESSFUL ✅)

**This method successfully recovered access on April 21, 2026**

**Requirements:**
- Physical console access (HDMI monitor or serial console)
- Keyboard connected to OPNsense device

**Procedure:**

1. **Reboot the OPNsense device** and watch for the boot loader countdown (10 seconds)

2. **Press `3`** during countdown to "Escape to loader prompt"

3. **At the `OK` prompt**, enter these commands:
   ```
   set boot_single="YES"
   boot
   ```

4. **At the mountroot prompt**:
   - If asked, type: `ufs:/dev/ada0s1a` and press Enter
   - Or just press Enter if it auto-detects

5. **Mount filesystems as read-write** (critical step):
   ```bash
   # If standard mount fails with "operation not permitted", use -f flag
   /sbin/mount -f -u -w /
   /sbin/mount -f -u -w /conf
   ```

6. **Verify filesystem is writable**:
   ```bash
   mount | grep "on / "
   ```
   Should show `(rw,` not `(ro,`

7. **Edit the configuration to remove TOTP**:
   ```bash
   # Remove TOTP authentication mode
   sed -i '' 's/<authmode>Local Database + TOTP<\/authmode>/<authmode>Local Database<\/authmode>/' /conf/config.xml
   
   # Remove otp_seed from root user
   sed -i '' '/<otp_seed>/d' /conf/config.xml
   
   # Optional: Verify changes
   grep authmode /conf/config.xml
   grep otp_seed /conf/config.xml  # Should return nothing
   ```

8. **Reboot**:
   ```bash
   reboot
   ```

9. **Login to web UI** with your standard root password (no TOTP required)

**Why This Works:**
- Single-user mode bypasses all authentication
- Direct config.xml editing removes TOTP requirement before services start
- The `-f` (force) flag on mount bypasses FreeBSD read-only protection

**Recovery Time:** ~5 minutes from reboot to web UI access

---

### Option 2: Serial Console Access (If HDMI not available)

**Requirements:**
- USB-to-Serial adapter (USB-C or USB-A to DB9/console port)
- Protectli box with serial/console port

**Procedure:**
1. Connect USB-to-Serial adapter to Protectli console port (USB-C COM port on some models)
2. On Mac, find device:
   ```bash
   ls /dev/cu.usbserial*
   ```
3. Connect via cu (NOT screen - PTY issues):
   ```bash
   sudo cu -l /dev/cu.usbserial-XXXXXXXX -s 115200
   ```
4. Follow single-user mode procedure above (Option 1)
5. Disconnect: `~.` (tilde-period)
4. Reboot Protectli or press Enter to access console menu
5. Select option 8: Shell
6. Run recovery commands:
   ```bash
   # Download the fixed config we prepared
   fetch -o /conf/config.xml http://[your-mac-ip]:8000/opnsense-config.xml
   
   # Or manually edit on the box
   vi /conf/config.xml
   # Find and change: <authmode>Local Database + TOTP</authmode>
   # To: <authmode>Local Database</authmode>
   # Remove authserver section (around line 321-329)
   # Remove otp_seed from root user
   
   # Restart web configurator
   /usr/local/etc/rc.d/configd restart
   ```

**Alternative - Reset Password Tool:**
```bash
/usr/local/sbin/opnsense-shell
# Select option 3: Reset webConfigurator password
# This will also revert authentication server to default
```

### Option 2: Boot Loader Single-User Mode

**Requirements:**
- Working display output (try different HDMI cables/monitors/adapters)
- Or serial console access

**Procedure:**
1. Reboot Protectli box
2. During boot, press **ESC** or **F12** to access boot menu
3. Select "Boot Single User"
4. At the prompt:
   ```bash
   mount -uw /
   vi /conf/config.xml
   # Make the same changes as above
   reboot
   ```

### Option 3: Configuration USB Recovery

**Procedure:**
1. Prepare USB drive with fixed config:
   ```bash
   # On your Mac, copy the fixed config to USB
   cp /tmp/opnsense-config.xml /Volumes/USB_DRIVE/config.xml
   ```
2. Boot OPNsense from install media or recovery mode
3. Mount USB and copy config:
   ```bash
   mount -t msdosfs /dev/da1s1 /mnt
   cp /mnt/config.xml /conf/config.xml
   reboot
   ```

### Option 4: Reinstall OPNsense (LAST RESORT)

**Warning:** This will require complete reconfiguration of:
- VLANs (10, 20, 30)
- DHCP servers
- Firewall rules (12 rules across 3 VLANs)
- Management interface restrictions
- All other settings

**Only use if:**
- No other recovery method works
- You have documentation of all settings
- You can afford the downtime

---

## Fixed Configuration File

**Location:** `/tmp/opnsense-config.xml` (on recovery Mac)

**Changes Made:**
1. Line 271: `<authmode>Local Database</authmode>` (was: `Local Database + TOTP`)
2. Lines 321-329: Removed entire `<authserver>` block for TOTP
3. Removed `<otp_seed>XSPS2Q2UINQCEDL6N6Z6ONGSGTIPBMIU</otp_seed>` from root user

**File Size:** ~98KB  
**Backup of Original:** `/tmp/opnsense-config-backup.xml`

---

## Prevention - Proper 2FA Setup Procedure

**✅ SUCCESSFULLY IMPLEMENTED on April 21, 2026**

### Correct Procedure (Verified Working)

1. **Create TOTP Authentication Server:**
   - System → Access → Servers → Add
   - Type: **TOTP (Time based One Time Password)**
   - Descriptive name: "Local Database + TOTP"
   - Token length: **6** (standard)
   - Time window: **1** (30-second intervals)
   - **CRITICAL:** Grace period: Set position to **AFTER** password
     - This means login format is: `<password><6-digit-totp-code>`
     - Example: `mypassword123456`
   - Save

2. **Generate TOTP seed for user:**
   - System → Access → Users → Edit root
   - Scroll to OTP seed section
   - Click **"Generate new secret (QR)"**
   - Scan QR code with authenticator app (Google Authenticator, Authy, etc.)
   - **Save user**

3. **Test TOTP BEFORE switching authentication server:**
   - System → Access → Tester
   - Authentication Server: **"Local Database + TOTP"**
   - Username: **root**
   - Password: **`<password><totp-code>`** (password then 6 digits)
   - Click **Test**
   - **MUST show:** "User: root authenticated successfully"
   - **If fails:** Do NOT proceed - troubleshoot first

4. **Only after test succeeds, switch global auth server:**
   - System → Settings → Administration
   - Authentication Server: Change to **"Local Database + TOTP"**
   - **Save**

5. **Test login in private browser window:**
   - Open incognito/private window
   - Go to https://192.168.10.1:8443
   - Username: **root**
   - Password: **`<password><totp-code>`** (e.g., `mypassword123456`)
   - Should login successfully

6. **Enable SSH as backup access method (CRITICAL):**
   - System → Settings → Administration
   - Secure Shell: **Enable Secure Shell**
   - Listen Interfaces: **LAN** or Management VLAN only
   - Permit Root Login: **Yes** (for recovery)
   - Authentication Method: **Public Key + Password** (most secure with fallback)
   - **Save**
   - Test: `ssh root@192.168.10.1` (use same `<password><totp-code>` format)

### ❌ What NOT to Do

- ❌ Switch global authentication server BEFORE testing with System → Access → Tester
- ❌ Assume TOTP works without explicit testing
- ❌ Set up 2FA without SSH backup access enabled
- ❌ Forget the login format: `<password><totp-code>` (password BEFORE code when position=AFTER)
- ❌ Disable console access when 2FA is enabled

### 🔒 TOTP Login Format Reference

**Authentication Server Configuration:**
- Grace period position: **AFTER** password

**Login Format:**
- Username: `root`
- Password field: `<your-password><6-digit-totp-code>`
- Example: If password is `SecurePass123` and TOTP code is `123456`, enter: `SecurePass123123456`

**Why "AFTER" means password comes FIRST:**
OPNsense's "AFTER" position means TOTP is validated after password validation in the authentication flow. The user inputs password first, then TOTP code immediately after in the single password field.

---

## Lessons Learned

1. **Always test authentication changes in a separate session** before closing your working session
2. **Enable backup access methods** (SSH) before implementing 2FA
3. **Physical/serial console access is critical** for recovery scenarios
4. **OPNsense API lacks config restore endpoint** in version 26.1.6 - cannot recover via API alone
5. **TOTP lockout is a common issue** - proper procedure must be followed

---

## Current System State

**Network Configuration:** ✅ Fully operational
- VLANs 10 (Management), 20 (DMZ/Guest), 30 (Internal) - working
- Ruckus AP migrated to Management VLAN (192.168.10.10) - working
- OPNsense web UI restricted to Management VLAN only - working
- Firewall rules verified - working

**Access Status:** 🚨 **LOCKED OUT**
- Web UI: Cannot authenticate (TOTP required but not working)
- SSH: Disabled
- Physical console: HDMI not working
- Serial console: Not tested (hardware TBD)

**Recovery Status:** ⏸️ **PAUSED - Awaiting Hardware**
- Fixed config file ready at `/tmp/opnsense-config.xml`
- Need serial console adapter OR working display
- Cannot proceed without physical access

---

## Next Steps

**Immediate:**
1. Acquire USB-to-Serial adapter (if Protectli has DB9 port)
2. OR try different HDMI cables/monitors/adapters
3. Access console using one of the methods above
4. Apply the fixed configuration

**After Recovery:**
1. Verify web UI login works with username/password only
2. Re-enable SSH for backup access
3. Properly implement 2FA using correct procedure
4. Document backup recovery procedures
5. Test recovery procedures before finalizing 2FA

---

## Reference Files

- **Fixed Config:** `/tmp/opnsense-config.xml`
- **Original Backup:** `/tmp/opnsense-config-backup.xml`
- **Recovery Script:** `/tmp/fix-auth.sh`
- **This Document:** `/Users/develeap/Desktop/Projects/homelab/network/OPNSENSE_2FA_RECOVERY.md`

---

## Contact Information

**User Environment:**
- Location: Connected to Management VLAN (192.168.10.x) via "Homelab-Mgmt" SSID
- Can access: Ruckus AP (192.168.10.10), network devices on Management VLAN
- Cannot access: OPNsense web UI (authentication fails)

**Recovery Support:**
If you need assistance with serial console setup or have questions about the recovery procedure, the fixed configuration file is ready and waiting to be applied.
