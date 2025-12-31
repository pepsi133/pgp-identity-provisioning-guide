# Quick Fix Commands (Try These First)

~~~bash
# 1. Install YubiKey udev rules via Debian package (recommended)
sudo apt-get install -y libu2f-udev

# 2. Remove and reinsert YubiKey physically

# 3. Restart pcscd and kill gpg-agent
sudo systemctl restart pcscd
gpgconf --kill gpg-agent
sleep 2

# 4. Test detection
ykman list
gpg --card-status
~~~


Try This First (Without Changing Modes)
bash
# 1. Check what mode you're currently in
ykman config usb --list
# 2. The issue might just be scdaemon/pcscd conflicts
# Kill everything and restart fresh
sudo systemctl stop pcscd
sudo pkill -9 gpg-agent scdaemon pcscd 2>/dev/null
sleep 2
# 3. Start pcscd cleanly
sudo systemctl start pcscd
sleep 2
# 4. Remove and reinsert YubiKey (often needed even without mode change)
echo ">>> REMOVE YubiKey, wait 3 seconds, then REINSERT it"
read -p "Press Enter after reinserting..."
# 5. Kill gpg-agent and try again
gpgconf --kill gpg-agent
sleep 1
gpg --card-status
If That Still Fails: Temporary CCID-Only for Provisioning
You can set it to CCID-only just for the provisioning process, then switch back:

bash
# During provisioning (now)
ykman config usb --enable CCID --disable OTP --disable FIDO2 --force
# After provisioning is complete, restore all features:
ykman config usb --enable CCID --enable OTP --enable FIDO2 --force
What Each Mode Does
OTP: One-Time Passwords (Yubico OTP, HOTP)
FIDO2/U2F: Web authentication (FIDO2, WebAuthn)
CCID: Smart card interface (GPG, PIV, OpenPGP)
You can have all three enabled simultaneously. The issue is that on some systems, having multiple modes can cause conflicts with pcscd/GPG.

Alternative: Check if it's a gpg.conf Issue
bash
# Check scdaemon settings
cat ~/.gnupg/scdaemon.conf 2>/dev/null
# Try adding reader-port directive
mkdir -p ~/.gnupg
echo "reader-port \"Yubico YubiKey\"" > ~/.gnupg/scdaemon.conf
gpgconf --kill gpg-agent
gpg --card-status





# 1. Kill all conflicting processes
sudo pkill -9 gpg-agent pcscd scdaemon 2>/dev/null
# 2. Restart pcscd with verbose logging
sudo systemctl restart pcscd
sleep 2
# 3. Check if pcscd can see the card reader
pcsc_scan
# Press Ctrl+C after you see output (should show YubiKey as a reader)
# 4. Kill pcsc_scan and test GPG
# (Press Ctrl+C to stop pcsc_scan first)
gpgconf --kill gpg-agent
sleep 1
# 5. Try card-status again
gpg --card-status
If that doesn't work, try this:

Alternative: Set YubiKey to CCID-only Mode
The issue might be that YubiKey is in a mixed mode. Force CCID-only:

bash
# Check current mode
ykman config usb --list
# Set to CCID-only (this will disable OTP and FIDO2)
ykman config usb --enable CCID --disable OTP --disable FIDO2 --force
# Remove and reinsert the YubiKey physically
echo ">>> Remove YubiKey, wait 5 seconds, then reinsert it"
read -p "Press Enter after reinserting..."
# Restart services
sudo systemctl restart pcscd
gpgconf --kill gpg-agent
sleep 2
# Test
gpg --card-status
Check pcscd Status
If still failing, check if pcscd is actually running:

bash
# Check service status
systemctl status pcscd
# Check if pcscd can list readers
pcsc_scan
# Look for errors in syslog
sudo journalctl -u pcscd -n 50






# YubiKey Detection Troubleshooting

**Run this if you encounter "No YubiKey detected" errors during Step 0.5**

This comprehensive diagnostic script will help you identify and fix YubiKey detection issues on Debian Live systems.

~~~bash
echo ">>> YubiKey Troubleshooting Diagnostics"

# 1. Check if YubiKey is physically detected by USB
echo "--- 1. USB Detection ---"
lsusb | grep -i yubikey
if lsusb | grep -iq yubikey; then
  echo "✅ YubiKey detected on USB bus"
else
  echo "❌ YubiKey NOT detected on USB - check physical connection"
  echo "   Try: different USB port, remove/reinsert, check cable"
fi

# 2. Check udev rules (required for non-root access)
echo ""
echo "--- 2. Udev Rules ---"
if dpkg -l | grep -q libu2f-udev; then
  echo "✅ YubiKey udev package (libu2f-udev) installed"
else
  echo "⚠️  YubiKey udev rules NOT found - installing libu2f-udev package..."
  sudo apt-get install -y libu2f-udev
  echo "   Please REMOVE and REINSERT the YubiKey now"
  read -p "   Press Enter after reinserting YubiKey..." _
fi

# 3. Check pcscd service
echo ""
echo "--- 3. Smart Card Service (pcscd) ---"
if systemctl is-active --quiet pcscd; then
  echo "✅ pcscd is running"
else
  echo "⚠️  pcscd not running - starting..."
  sudo systemctl unmask pcscd
  sudo systemctl start pcscd
  sleep 2
fi

# 4. Test ykman detection
echo ""
echo "--- 4. YubiKey Manager ---"
if ykman list 2>/dev/null | grep -q "YubiKey"; then
  echo "✅ ykman can detect YubiKey"
  ykman info
else
  echo "❌ ykman cannot detect YubiKey"
  echo "   Trying after killing conflicting processes..."
  sudo pkill -9 gpg-agent pcscd 2>/dev/null
  sudo systemctl start pcscd
  sleep 2
  if ykman list 2>/dev/null | grep -q "YubiKey"; then
    echo "✅ YubiKey now detected"
  else
    echo "❌ Still cannot detect YubiKey - check mode below"
  fi
fi

# 5. Check GPG card status
echo ""
echo "--- 5. GPG Card Detection ---"
gpgconf --kill gpg-agent
sleep 1
if gpg --card-status 2>&1 | grep -q "Application ID"; then
  echo "✅ GPG can access YubiKey OpenPGP applet"
else
  echo "❌ GPG cannot access YubiKey"
  echo "   The YubiKey might not be in CCID mode"
fi

# 6. Check and set CCID mode if needed
echo ""
echo "--- 6. YubiKey USB Mode ---"
CURRENT_MODE=$(ykman config usb --list 2>/dev/null | grep "Enabled" || echo "unknown")
echo "Current mode: $CURRENT_MODE"
if echo "$CURRENT_MODE" | grep -q "CCID"; then
  echo "✅ CCID mode is enabled"
else
  echo "⚠️  CCID mode not enabled - enabling now..."
  read -p "   Set mode to CCID-only? This will disable FIDO2/OTP. (y/N): " ENABLE_CCID
  if [ "$ENABLE_CCID" = "y" ] || [ "$ENABLE_CCID" = "Y" ]; then
    ykman config usb --enable CCID --disable OTP --disable FIDO2 --force
    echo "   YubiKey mode changed. REMOVE and REINSERT the YubiKey now."
    read -p "   Press Enter after reinserting YubiKey..." _
    gpgconf --kill gpg-agent
    sleep 2
  fi
fi

# Final verification
echo ""
echo "--- Final Verification ---"
if gpg --card-status 2>&1 | grep -q "Application ID" && ykman list 2>/dev/null | grep -q "YubiKey"; then
  echo "✅ YubiKey is fully operational for OpenPGP"
  echo "   You can proceed with Step 0.5 or the main provisioning"
else
  echo "❌ YubiKey detection still failing"
  echo "   Possible issues:"
  echo "   - YubiKey firmware too old (need 5.x+)"
  echo "   - Hardware defect"
  echo "   - USB controller compatibility"
  echo "   Try: different computer, different USB port, or contact Yubico support"
fi
~~~

## Common Issues and Solutions

### Issue: "No YubiKey detected" by ykman but GPG works
**Cause**: YubiKey is in OTP+FIDO mode, not CCID mode  
**Solution**: Run step 6 above to enable CCID mode

### Issue: udev rules missing
**Cause**: Fresh Debian Live system doesn't have YubiKey udev rules  
**Solution**: Install `libu2f-udev` package: `sudo apt-get install -y libu2f-udev`

### Issue: pcscd not running
**Cause**: Smart card daemon not started  
**Solution**: Step 3 above starts the pcscd service

### Issue: Permissions denied
**Cause**: User not in correct group or udev rules not applied  
**Solution**: Reinsert YubiKey after installing udev rules (step 2)

## Integration with Main Guide

Add this as **Step 0.4.1** (between Step 0.4 and Step 0.5) in the main `openpgp-airgapped-provisioning.md` file. Insert it right before the line:

```
**Step 0.5 (Optional but Recommended, Network OK): YubiKey Dry-Run Diagnostic**
```
