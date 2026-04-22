# OPNsense Serial Console Recovery - Step by Step

**Serial Device:** `/dev/cu.usbserial-FTM0J3ER`  
**Baud Rate:** 115200

---

## Quick Start

Open a new terminal and run:

```bash
screen /dev/cu.usbserial-FTM0J3ER 115200
```

Or use the helper script:

```bash
/tmp/opnsense-serial-connect.sh
```

---

## Step-by-Step Recovery Procedure

### Step 1: Connect to Console

```bash
screen /dev/cu.usbserial-FTM0J3ER 115200
```

You should see OPNsense console output. If blank screen, press **Enter**.

### Step 2: Access OPNsense Menu

You should see:

```
*** OPNsense.localdomain: OPNsense 26.1.6 (amd64/OpenSSL) ***

  0) Logout                              7) Ping host
  1) Assign interfaces                   8) Shell
  2) Set interface IP address            9) pfTop
  3) Reset the root password            10) Firewall log
  4) Reset to factory defaults          11) Restart web interface
  5) Power off system                   12) Update from console
  6) Reboot system                      13) Restore a backup
```

**Type:** `8` (then press Enter) to access Shell

### Step 3: Run Password Reset Tool

At the shell prompt, run:

```bash
/usr/local/sbin/opnsense-shell
```

You'll see the same menu. **Type:** `3` (Reset the root password)

### Step 4: Reset Password

Follow the prompts:
- Enter new password for root
- Confirm password

**IMPORTANT:** This will automatically revert the authentication server from "Local Database + TOTP" back to "Local Database" (password only).

### Step 5: Exit and Test

1. Type `exit` to leave shell
2. Type `0` to logout from console
3. Disconnect from screen: **Ctrl-A** then **K**, then **Y**

### Step 6: Test Web UI Login

Open browser to: `https://192.168.10.1:8443`

Login with:
- **Username:** root
- **Password:** (the new password you just set)
- **No TOTP code required** - authentication is back to password-only

---

## Alternative Method: Manual Config Edit

If password reset doesn't work, you can manually edit the config:

### At the Shell (step 2 above, option 8):

```bash
# Backup current config
cp /conf/config.xml /conf/config.xml.backup

# Edit config
vi /conf/config.xml

# Find this line (around line 271):
#   <authmode>Local Database + TOTP</authmode>
# Change to:
#   <authmode>Local Database</authmode>

# Find and DELETE these lines (around 321-329):
#   <authserver>
#     <refid>69e7cd2ae8c19</refid>
#     <type>totp</type>
#     <name>Local Database + TOTP</name>
#     <otpLength>6</otpLength>
#     <timeWindow/>
#     <graceperiod/>
#     <passwordFirst>1</passwordFirst>
#   </authserver>

# Save and exit (:wq in vi)

# Restart web configurator
/usr/local/etc/rc.d/configd restart

# Exit shell
exit
```

---

## Using Pre-Made Fixed Config (Fastest)

If you can access the network from the serial console shell:

```bash
# Download the fixed config we already prepared
fetch -o /conf/config.xml.new http://192.168.10.YOUR_MAC_IP:8000/opnsense-config.xml

# Backup current
cp /conf/config.xml /conf/config.xml.before-fix

# Apply fixed config
mv /conf/config.xml.new /conf/config.xml

# Restart
/usr/local/etc/rc.d/configd restart
```

To serve the file from your Mac, open another terminal:

```bash
cd /tmp
python3 -m http.server 8000
```

Then use your Mac's IP on the Management VLAN (192.168.10.x) in the fetch command.

---

## Screen Commands Reference

- **Detach from screen (keep session running):** Ctrl-A then D
- **Kill screen session:** Ctrl-A then K, then Y
- **Scroll up:** Ctrl-A then Esc (then use arrow keys, Esc to exit scroll mode)

---

## Troubleshooting

### Blank Screen After Connecting

- Press **Enter** several times
- If still blank, disconnect (Ctrl-A K Y) and reconnect
- Try rebooting the Protectli box

### "Line in use" Error

```bash
# Kill existing screen sessions
killall screen

# Try connecting again
screen /dev/cu.usbserial-FTM0J3ER 115200
```

### Permission Denied

```bash
# Check device permissions
ls -la /dev/cu.usbserial-FTM0J3ER

# Try with sudo (usually not needed for cu.* devices)
sudo screen /dev/cu.usbserial-FTM0J3ER 115200
```

### Lost Connection

- Reconnect: `screen /dev/cu.usbserial-FTM0J3ER 115200`
- Screen may resume previous session automatically

---

## After Recovery: Enable SSH Backup Access

Once you're back in the web UI:

1. **System → Settings → Administration**
2. **Secure Shell:**
   - ✅ Enable Secure Shell
   - Listen Interfaces: **VLAN10_Management** (192.168.10.1)
   - Permit root user login: **Yes** (or create a different admin user)
   - Permit password login: **Yes** (initially, then switch to keys)

3. **Test SSH access:**
   ```bash
   ssh root@192.168.10.1
   ```

4. **This gives you a recovery method if web UI fails again**

---

## Next: Proper 2FA Setup

See `/Users/develeap/Desktop/Projects/homelab/network/OPNSENSE_2FA_RECOVERY.md` section "Prevention - Proper 2FA Setup Procedure" for the correct way to enable 2FA without locking yourself out.

**Key points:**
1. Keep auth server as "Local Database"
2. Generate TOTP seed
3. **Test TOTP works in private browser**
4. Only then switch auth server to "Local Database + TOTP"
5. Have SSH enabled as backup access

---

## Files Reference

- **Fixed config:** `/tmp/opnsense-config.xml`
- **Connection script:** `/tmp/opnsense-serial-connect.sh`
- **This guide:** `/Users/develeap/Desktop/Projects/homelab/network/SERIAL_CONSOLE_RECOVERY_STEPS.md`
- **Full recovery doc:** `/Users/develeap/Desktop/Projects/homelab/network/OPNSENSE_2FA_RECOVERY.md`
