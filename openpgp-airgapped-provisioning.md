# Air-Gapped OpenPGP Root Identity & Hardware Provisioning Protocol

Version: 1.4 (Debian Stable Live, streamlined for advanced users)
Target System: Debian Stable Live ISO. All package sourcing is from Debian Main (stable).

External references to keep handy (outside this document, as QR/URL placeholders):
- GnuPG Manual: https://gnupg.org/documentation/manuals/gnupg/
- drduh YubiKey/SSH/Git guide: https://github.com/drduh/YubiKey-Guide

Hardware Required:

* 2x **YubiKey 5C NFC** (Tier 2 "Identity" Keys)
* 1x **USB Flash Drive** (Primary backup target)
* 1x **SSD/HDD** (Secondary backup target)
* 1x **USB Printer** (Direct connect)

## **Index**

1. [Phase 0: Environment Preparation](#phase-0-environment-preparation)
2. [Phase 1: Secure Session Setup](#phase-1-secure-session-setup)
3. [Phase 2: Master Key Generation](#phase-2-master-key-generation)
4. [Phase 3: Physical & Digital Backups (Including Revocation)](#phase-3-physical--digital-backups-including-revocation)
5. [Phase 4: The "Clean Slate" Restoration Test](#phase-4-the-clean-slate-restoration-test)
6. [Phase 5: Subkey Generation](#phase-5-subkey-generation)
7. [Phase 5.5: Finalize Master Key Backup with Subkeys (CRITICAL)](#phase-55-finalize-master-key-backup-with-subkeys-critical)
8. [Phase 6: YubiKey Configuration (PINs & Touch)](#phase-6-yubikey-configuration-pins--touch)
9. [Phase 7: Loading Keys to Hardware](#phase-7-loading-keys-to-hardware)
10. [Phase 8: Final Verification & Cleanup](#phase-8-final-verification--cleanup)
11. [Appendix A: Emergency Operations](#appendix-a-emergency-operations)

## **Phase 0: Environment Preparation**

**Goal:** Verify tools, define variables, ready the printer, and lock in Debian Live persistence.

**Step 0.0: Configure Debian Live Persistence (cache only)**

If using a persistent Debian Live USB, configure persistence to retain only **/var/cache/apt** and **/var/lib/apt**. Do **NOT** persist **$GNUPGHOME** or **/tmp**.

1. Boot the Debian Stable Live ISO with persistence enabled.
2. Mount the persistence partition (often **/media/${USER}/persistence**).
3. Create **persistence.conf** with cache-only entries:

~~~bash
sudo tee /media/${USER}/persistence/persistence.conf >/dev/null <<'EOF'
/var/cache/apt union
/var/lib/apt union
EOF
sudo sync
~~~

4. Reboot to apply. Confirm that **$GNUPGHOME** and **/tmp** are not persistent.

**Step 0.1: Define Variables**

Open a terminal. Edit the variables to match your identity and mount points. Use RAM-based **$GNUPGHOME**.

~~~bash
# --- USER IDENTITY ---
export MY_NAME="Test User"
export MY_EMAIL="testin@test.tst"
export MY_EMAIL_2="secondary@test.tst"   # optional

# --- STORAGE PATHS (confirm with lsblk/df -h) ---
export USB_BACKUP_PATH="/media/debian/usb_backup"
export SSD_BACKUP_PATH="/media/debian/ssd_backup"

# --- SYSTEM CONSTANTS (do not change) ---
export GNUPGHOME=/tmp/tmp.gnupg_dpa_tmp
export BACKUP_DIR_NAME="PGP_Master_Backup"
mkdir -p "$GNUPGHOME"

# Save variables for session recovery
cat << EOF > "$GNUPGHOME/session_vars.sh"
export MY_NAME="$MY_NAME"
export MY_EMAIL="$MY_EMAIL"
export MY_EMAIL_2="$MY_EMAIL_2"
export USB_BACKUP_PATH="$USB_BACKUP_PATH"
export SSD_BACKUP_PATH="$SSD_BACKUP_PATH"
export GNUPGHOME="$GNUPGHOME"
EOF

echo "✅ Session variables saved to: $GNUPGHOME/session_vars.sh"
echo "   To recover after interruption: source $GNUPGHOME/session_vars.sh"
~~~

**Step 0.2: Pre-Flight Tool Check (Debian Stable Main repos)**

All tooling should come from Debian Main. Packages: **gnupg paperkey qrencode zbar-tools coreutils yubikey-manager wamerican scdaemon pcscd cups-client rng-tools**.

~~~bash
REQUIRED_TOOLS=("gpg" "paperkey" "qrencode" "zbarimg" "zbarcam" "shuf" "sha256sum" "ykman" "lp")
PACKAGES="gnupg paperkey qrencode zbar-tools coreutils yubikey-manager wamerican scdaemon pcscd cups-client rng-tools"

echo ">>> Initial Tool Check..."
for tool in "${REQUIRED_TOOLS[@]}"; do
  command -v "$tool" >/dev/null && echo "  ✅ $tool" || echo "  ❌ $tool (missing)"
done

echo ">>> Checking Internet Connectivity..."
if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
  echo "✅ Internet connected."; NETWORK_OK=1
else
  echo "❌ No internet. Skipping installation."; NETWORK_OK=0
fi

echo ""
if [ $NETWORK_OK -eq 1 ]; then
  echo ">>> Updating Debian Main repos..."
  sudo apt-get update || true
  echo ""
  echo ">>> Installing packages..."
  sudo apt-get install -y $PACKAGES || sudo apt-get install -y --fix-missing $PACKAGES || true
  echo ""
fi

echo ">>> Starting pcscd service..."
sudo systemctl unmask pcscd || true
sudo systemctl start pcscd || true

# Final verification
MISSING_COUNT=0
for tool in "${REQUIRED_TOOLS[@]}"; do
  if command -v "$tool" >/dev/null; then
    echo "  ✅ $tool"
  else
    echo "  ❌ $tool (missing)"; MISSING_COUNT=$((MISSING_COUNT + 1))
  fi
done
[ $MISSING_COUNT -gt 0 ] && echo "⚠️  $MISSING_COUNT tool(s) missing. Install manually: sudo apt-get install -y <package>" || echo "✅ All tools available."
~~~

**Step 0.2 (Optional): Offline Bundle for Air-Gap Injection**

On a separate online Debian Stable machine:

~~~bash
# Create a local pool of .deb files for required packages
mkdir -p /tmp/pgp_bundle && cd /tmp/pgp_bundle
apt-get update
apt-get download gnupg paperkey qrencode zbar-tools coreutils yubikey-manager wamerican scdaemon pcscd cups-client rng-tools
ls -lh
~~~

Copy the directory to your air-gapped media. On the air-gapped Debian Live system, install with:

~~~bash
cd /path/to/pgp_bundle
sudo dpkg -i *.deb || { echo "⚠️ dpkg reported errors; attempting apt-get -f install..."; sudo apt-get -f install -y || echo "❌ Offline bundle install failed; review errors above."; }
~~~

**Step 0.3: Printer Setup (Network Required)**

* Add the USB printer via Settings → Printers while online so CUPS pulls dependencies.
* Print a test page before disconnecting.

**Step 0.4 (Optional but Recommended, Network OK): Diagnostic QR Test (Dummy Loopback)**

Goal: Prove **zbarcam** and **paperkey** work with your camera/printer before any secrets or passphrases are generated. Do this while network is available so you can troubleshoot drivers if needed.

~~~bash
# Use an isolated temp GNUPGHOME for the dummy key
export GNUPGHOME_DIAG=/tmp/tmp.gnupg_diag
mkdir -p "$GNUPGHOME_DIAG"

gpg --homedir "$GNUPGHOME_DIAG" --quick-generate-key "QR Test <qr-test@example.com>" ed25519 default 1d
DUMMY_KEYID=$(gpg --homedir "$GNUPGHOME_DIAG" --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')

gpg --homedir "$GNUPGHOME_DIAG" --export-secret-key "$DUMMY_KEYID" > "$GNUPGHOME_DIAG/dummy_secret.gpg"
paperkey --secret-key "$GNUPGHOME_DIAG/dummy_secret.gpg" --output "$GNUPGHOME_DIAG/dummy_paperkey.txt"
cat "$GNUPGHOME_DIAG/dummy_paperkey.txt" | qrencode -l M -o "$GNUPGHOME_DIAG/dummy_qr.png"

# Print and scan to mobile (OpenKeychain or similar) to confirm end-to-end
lp "$GNUPGHOME_DIAG/dummy_qr.png"

# Desktop reconstruction sanity check (requires an actual camera scan for full test)
command -v zbarcam >/dev/null && echo "✅ zbarcam available" || echo "❌ zbarcam not found"
paperkey --pubring <(gpg --homedir "$GNUPGHOME_DIAG" --export "$DUMMY_KEYID") --secrets "$GNUPGHOME_DIAG/dummy_paperkey.txt" --output "$GNUPGHOME_DIAG/dummy_rebuild.gpg"
sha256sum "$GNUPGHOME_DIAG/dummy_secret.gpg" "$GNUPGHOME_DIAG/dummy_rebuild.gpg"

# Cleanup
rm -rf "$GNUPGHOME_DIAG"
unset GNUPGHOME_DIAG
~~~

If the dummy key fails to round-trip on mobile or desktop, fix scanning/printing before proceeding.

**Step 0.5 (Optional but Recommended, Network OK): YubiKey Dry-Run Diagnostic**

Goal: Validate YubiKey detection, CCID mode, touch policy, and keytocard workflow with a disposable test key before touching real identities. Run this while network is available for driver troubleshooting. This will wipe the YubiKey OpenPGP applet when reset—perform on each YubiKey and run `ykman openpgp reset -f` afterward to return it to a clean state before Phase 6/7.

~~~bash
export GNUPGHOME_YK_DIAG=/tmp/tmp.gnupg_yk_diag
mkdir -p "$GNUPGHOME_YK_DIAG"

gpg --homedir "$GNUPGHOME_YK_DIAG" --quick-generate-key "YubiKey Test <yk-test@example.com>" ed25519 default 1d
YK_TEST_KEYID=$(gpg --homedir "$GNUPGHOME_YK_DIAG" --list-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')

gpg --card-status | grep -q "OpenPGP card" && echo "✅ YubiKey detected" || echo "❌ CRITICAL: YubiKey not detected"

# Ensure CCID-only and touch policies are configurable
ykman config mode ccid || true
gpgconf --kill gpg-agent
gpg --card-status | grep -q "OpenPGP card" && echo "✅ CCID mode OK" || echo "⚠️  CCID check: investigate"
ykman openpgp keys set-touch sig ON || true
ykman openpgp keys set-touch aut ON || true
ykman openpgp keys set-touch enc ON || true

# Load dummy key to card (exercises keytocard flow)
cat << 'EOF'
At the gpg> prompt (dummy key):
- key 1 → keytocard → 1 (Signature) → Admin PIN → key 1 (deselect)
- key 2 → keytocard → 2 (Encryption) → Admin PIN → key 2 (deselect)
- key 3 → keytocard → 3 (Authentication) → Admin PIN
- save
EOF
read -p "Proceed with dummy keytocard? Type YES to continue: " YK_DRYRUN
if [ "$YK_DRYRUN" = "YES" ]; then
  gpg --homedir "$GNUPGHOME_YK_DIAG" --edit-key "$YK_TEST_KEYID"
  gpgconf --kill gpg-agent; sleep 2
  gpg --card-status | grep -q "Signature key" && echo "✅ Dummy signature key detected on card" || echo "⚠️  Dummy signature key not detected"
fi

ykman openpgp reset -f  # wipe dummy data; required before real provisioning
rm -rf "$GNUPGHOME_YK_DIAG"
unset GNUPGHOME_YK_DIAG
~~~

If any YubiKey step fails, resolve hardware/driver issues now while online if needed. Restart Phase 0 after resetting the YubiKey.

**Step 0.6: Establish Air-Gap (CRITICAL)**

~~~bash
echo ">>> Verifying Air-Gap Status..."
if ip route get 8.8.8.8 >/dev/null 2>&1; then
  echo "❌ CRITICAL: Default route exists. Network may still be reachable."; ip route show
elif ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
  echo "❌ CRITICAL: Ping succeeded. Network is reachable."
else
  echo "✅ Air-gap verified: Network is unreachable"
fi
~~~

## **Phase 1: Secure Session Setup**

**Goal:** Harden the GPG environment in RAM and prepare entropy.

**Step 1.0: Entropy Hardening (run before key generation)**

Ensure **rng-tools** is running and feed manual salt into the kernel pool.

~~~bash
# Start rngd if not already active
sudo systemctl enable --now rng-tools || sudo rngd -r /dev/urandom -o /dev/random -b

echo "Type random characters and move the mouse for 30 seconds, then press Ctrl+D"
sudo tee /dev/urandom >/dev/null
~~~

**Step 1.1: Harden GPG Configuration**

~~~bash
cat << EOF > "$GNUPGHOME/gpg.conf"
personal-cipher-preferences AES256 AES192 AES
personal-digest-preferences SHA512 SHA384 SHA256
personal-compress-preferences ZLIB BZIP2 ZIP Uncompressed
default-preference-list SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed
cert-digest-algo SHA512
s2k-digest-algo SHA512
s2k-cipher-algo AES256
s2k-count 65011712
EOF

echo "default-cache-ttl 7200" > "$GNUPGHOME/gpg-agent.conf"
echo "max-cache-ttl 7200" >> "$GNUPGHOME/gpg-agent.conf"
gpg-connect-agent reloadagent /bye
~~~

**Step 1.2: Generate Master Passphrase**

~~~bash
echo "------------------------------------------------"
echo "WRITE THIS DOWN (Your Master Key Passphrase):"
echo "------------------------------------------------"
shuf -n 6 /usr/share/dict/words | tr '\n' ' '
echo -e "\n------------------------------------------------"
~~~

Write the 6 words on your permanent paper storage card. Immediately re-type the 6 words exactly as written (silent, no clipboard) to confirm legibility; correct any mistakes on paper before moving on.

## **Phase 2: Master Key Generation**

**Goal:** Create the Certify-only Ed25519 master key.

**Step 2.1: Generate Key**

Ensure **Step 1.0** entropy hardening was completed immediately before this.

~~~bash
gpg --expert --full-gen-key
~~~

Interactive selections (unchanged):
1. Key type: (11) ECC (set your own capabilities)
2. Elliptic Curve: (1) Curve 25519
3. Key Usage: toggle Sign (`s`) OFF, toggle Encrypt (`e`) OFF, Certify only → `q`
4. Validity: 0 (no expiry)
5. Confirm: y
6. ID: Type **$MY_NAME** / **$MY_EMAIL** values (not literal variable names)
7. Passphrase: use the 6-word passphrase from Phase 1

**Step 2.2: Capture Key ID**

~~~bash
export KEYID=$(gpg --list-keys --with-colons | awk -F: '/^fpr:/ { print $10; exit }')
echo "Key ID Generated: $KEYID"

gpg --list-secret-keys "$KEYID" && echo "✅ Master key verified: $KEYID" || echo "❌ WARNING: Master key not found"
~~~

**Step 2.3: Add Secondary Identity (Optional)**

~~~bash
if [ -n "$MY_EMAIL_2" ]; then
  echo ">>> Adding secondary identity: $MY_EMAIL_2"
  gpg --quick-add-uid "$KEYID" "$MY_EMAIL_2"
  gpg --list-keys "$KEYID" | grep -q "$MY_EMAIL_2" && echo "✅ Secondary identity added" || echo "❌ WARNING: Secondary identity not found"
else
  echo ">>> Secondary identity skipped (MY_EMAIL_2 is empty)"
fi

echo ">>> Attempting to set trust to ultimate..."
echo -e "5\ny\n" | gpg --command-fd 0 --edit-key "$KEYID" trust quit

echo "If automatic trust failed, set it manually via gpg --edit-key $KEYID (trust → 5 → y → quit)."

echo ">>> Current key structure (verify trust shows [ultimate]):"
gpg --list-keys "$KEYID"
~~~

## **Phase 3: Physical & Digital Backups (Including Revocation)**

**Goal:** Create the triple redundancy backup and export the revocation certificate.

**Step 3.1: Generate Backup Artifacts**

~~~bash
cd "$GNUPGHOME"

gpg --export-secret-key "$KEYID" > master_secret.gpg

echo ">>> Generating Revocation Certificate (interactive)..."
echo "    Reason: 0 (No reason specified)"
echo "    Description: 'Backup Revocation' or blank"
echo "    Confirm: y"
gpg --gen-revoke "$KEYID" > revocation_cert.asc

ls -lh revocation_cert.asc

paperkey --secret-key master_secret.gpg --output master_paperkey.txt
sha256sum master_secret.gpg > master_checksum.txt
cat master_checksum.txt | qrencode -l M -o checksum_qr.png
cat revocation_cert.asc | qrencode -l M -o revocation_qr.png

ls -lh master_secret.gpg revocation_cert.asc master_paperkey.txt master_checksum.txt checksum_qr.png revocation_qr.png
~~~

**Step 3.2: Print Paper Backups**

~~~bash
echo ">>> Printing Paper Backups (QR Codes + ASCII)..."

lp checksum_qr.png
lp revocation_qr.png
lp master_checksum.txt
lp revocation_cert.asc
lp master_paperkey.txt

echo "✅ Paper backups printed. Store securely."
~~~

**Step 3.3: QR Scan Verification (Printed Media)**

~~~bash
echo ">>> TEST 1/2: Scan the CHECKSUM QR code"
zbarcam --raw > scanned_checksum.txt 2>/dev/null
if diff -w master_checksum.txt scanned_checksum.txt >/dev/null 2>&1; then
  echo "✅ Checksum QR scan successful"
else
  echo "❌ WARNING: Checksum QR scan failed or mismatch"
fi
rm -f scanned_checksum.txt

echo ">>> TEST 2/2: Scan the REVOCATION CERTIFICATE QR code"
zbarcam --raw > scanned_revocation.txt 2>/dev/null
if diff -w revocation_cert.asc scanned_revocation.txt >/dev/null 2>&1; then
  echo "✅ Revocation Certificate QR scan successful"
else
  echo "❌ WARNING: Revocation QR scan failed or mismatch"
fi
rm -f scanned_revocation.txt
~~~

**Step 3.4: Digital Integrity Check (Master Key)**

~~~bash
gpg --export "$KEYID" > pubkey_test.gpg
paperkey --pubring pubkey_test.gpg --secrets master_paperkey.txt --output test_secret.gpg
HASH_ORIG=$(sha256sum master_secret.gpg | awk '{print $1}')
HASH_RECONSTRUCT=$(sha256sum test_secret.gpg | awk '{print $1}')
echo "Original:      $HASH_ORIG"
echo "Reconstructed: $HASH_RECONSTRUCT"
[ "$HASH_ORIG" == "$HASH_RECONSTRUCT" ] && echo "✅ DIGITAL CHECK PASSED" || echo "❌ FAILURE: Hashes don't match"
rm -f pubkey_test.gpg test_secret.gpg
~~~

**Step 3.5: Additional Integrity Checks**

~~~bash
echo ">>> Generating comprehensive checksums for all backup files..."
sha256sum revocation_cert.asc master_paperkey.txt >> master_checksum.txt
~~~

**Step 3.6: Save to USB & SSD**

~~~bash
mkdir -p "$USB_BACKUP_PATH/$BACKUP_DIR_NAME" "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME"
for FILE in master_secret.gpg revocation_cert.asc master_checksum.txt master_paperkey.txt gpg.conf gpg-agent.conf; do
  cp "$FILE" "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
  cp "$FILE" "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"
done
sync

ls -lh "$USB_BACKUP_PATH/$BACKUP_DIR_NAME"
ls -lh "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME"
~~~

## **Phase 4: The "Clean Slate" Restoration Test**

**Goal:** Prove the backup works by wiping local keys and restoring.

**Step 4.1: Wipe Local GPG Home**

~~~bash
rm -rf "$GNUPGHOME/private-keys-v1.d"
rm "$GNUPGHOME/pubring.kbx" "$GNUPGHOME/trustdb.gpg"
echo "Local keys wiped."
~~~

**Step 4.2: Restore from USB**

~~~bash
gpg --import "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/master_secret.gpg"

echo ">>> Setting key trust level (interactive):"
echo "    trust → 5 (Ultimate) → y → quit"
gpg --edit-key "$KEYID"

gpg --list-keys "$KEYID" | grep -E "^uid.*\[ultimate\]" && echo "✅ Trust level verified: Ultimate" || echo "⚠️  Trust level check: Review output above"
gpg --list-secret-keys "$KEYID" | grep -q "sec" && echo "✅ RESTORE SUCCESS: Master key operational." || echo "❌ FAILURE: Could not import from USB."
~~~

## **Phase 5: Subkey Generation**

**Goal:** Generate the S/E/A subkeys and prepare public files.

**Step 5.1: Create Subkeys**

~~~bash
gpg --expert --edit-key "$KEYID"
~~~

At the `gpg>` prompt:
1. Signing Subkey: `addkey` → (10) ECC (sign only) → Curve 25519 → Expiry 1y → save
2. Encryption Subkey: `addkey` → (12) ECC (encrypt only) → Curve 25519 → Expiry 1y → save
3. Authentication Subkey: `addkey` → (11) ECC (set your own capabilities) → toggle Sign off (`s`), toggle Auth on (`a`), `q` → Curve 25519 → Expiry 1y → save

**Step 5.2: WKD Hash Calculation & Export**

~~~bash
cd "$GNUPGHOME"

gpg --export "$KEYID" --armor > public_key_bundle.asc

echo ">>> Extracting WKD hash for: $MY_EMAIL"
WKD_HASH=$(gpg --with-wkd-hash --list-keys "$MY_EMAIL" | grep -A1 "$MY_EMAIL" | grep -v "@" | awk '{print $1}')
if [ -z "$WKD_HASH" ]; then
  echo "❌ CRITICAL: Automatic WKD hash extraction failed for $MY_EMAIL"
  gpg --with-wkd-hash --list-keys "$MY_EMAIL"
  read -p "Paste the PRIMARY WKD hash here: " WKD_HASH
fi

if [ -n "$WKD_HASH" ]; then
  echo "✅ Primary WKD Hash: $WKD_HASH"
  gpg --export "$KEYID" > "$WKD_HASH"
  [ -f "$WKD_HASH" ] && echo "✅ Primary WKD binary file created" || echo "❌ CRITICAL: Failed to create WKD file '$WKD_HASH'"
fi

if [ -n "$MY_EMAIL_2" ]; then
  echo ">>> Extracting WKD hash for: $MY_EMAIL_2"
  WKD_HASH_2=$(gpg --with-wkd-hash --list-keys "$MY_EMAIL_2" | grep -A1 "$MY_EMAIL_2" | grep -v "@" | awk '{print $1}')
  if [ -z "$WKD_HASH_2" ]; then
    echo "❌ WARNING: Automatic WKD hash extraction failed for $MY_EMAIL_2"
    gpg --with-wkd-hash --list-keys "$MY_EMAIL_2"
    read -p "Paste the SECONDARY WKD hash here (or Enter to skip): " WKD_HASH_2
  fi
  if [ -n "$WKD_HASH_2" ]; then
    echo "✅ Secondary WKD Hash: $WKD_HASH_2"
    gpg --export "$KEYID" > "$WKD_HASH_2"
    [ -f "$WKD_HASH_2" ] && echo "✅ Secondary WKD binary file created" || echo "❌ WARNING: Failed to create WKD file '$WKD_HASH_2'"
  else
    echo "⚠️  Secondary WKD creation skipped (no hash provided)"
  fi
else
  echo ">>> Skipping secondary email WKD (not configured)"
fi

# Save public artifacts to backup media
cp public_key_bundle.asc "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
cp public_key_bundle.asc "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"

if [ -f "$WKD_HASH" ]; then
  cp "$WKD_HASH" "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
  cp "$WKD_HASH" "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"
  echo "$WKD_HASH" > "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/wkd_filename.txt"
  echo "$WKD_HASH" > "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/wkd_filename.txt"
fi

if [ -n "$MY_EMAIL_2" ] && [ -f "$WKD_HASH_2" ]; then
  cp "$WKD_HASH_2" "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
  cp "$WKD_HASH_2" "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"
  echo "$WKD_HASH_2" > "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/wkd_filename_secondary.txt"
  echo "$WKD_HASH_2" > "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/wkd_filename_secondary.txt"
fi

ls -lh "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/" | grep -E "(public_key_bundle|wkd_filename|^[a-z0-9]{32}$)"
sync
~~~

## **Phase 5.5: Finalize Master Key Backup with Subkeys (CRITICAL)**

**Goal:** Refresh physical backups to include S/E/A subkeys.

~~~bash
cd "$GNUPGHOME"

gpg --export-secret-key "$KEYID" > master_secret.gpg
sha256sum master_secret.gpg > master_checksum.txt
paperkey --secret-key master_secret.gpg --output master_paperkey.txt
cat master_paperkey.txt | qrencode -l M -o master_qr.png
cat master_checksum.txt | qrencode -l M -o checksum_qr.png

echo ">>> Printing Master Key Artifacts..."
lp master_qr.png
lp master_paperkey.txt
lp checksum_qr.png
lp master_checksum.txt

echo ">>> VERIFICATION: Scan the printed Master QR code now."
zbarcam --raw | tee scanned_output.txt

diff -w master_paperkey.txt scanned_output.txt >/dev/null && echo "✅ PHYSICAL BACKUP VERIFIED: Printed QR matches digital file." || echo "❌ FAILURE: Printed QR does not match."

cp master_secret.gpg "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
cp master_checksum.txt "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
cp master_secret.gpg "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"
cp master_checksum.txt "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"

rm scanned_output.txt master_qr.png checksum_qr.png
~~~

## **Phase 6: YubiKey Configuration (PINs & Touch)**

**Goal:** Secure both YubiKeys.

**Step 6.1: Set PINs**

~~~bash
gpg --card-status | grep -q "OpenPGP card" && echo "✅ YubiKey detected, proceeding with PIN setup..." || echo "❌ CRITICAL: YubiKey not detected. Insert one YubiKey and try again."

gpg --change-pin
~~~

User PIN: 6-8 digits (memorize). Admin PIN: 8+ characters (store securely).

**Step 6.2: Switch to CCID Mode (Required for Touch Policy)**

~~~bash
echo ">>> Switching YubiKey to CCID-only mode (required for OpenPGP)..."
ykman config mode ccid
echo "✅ CCID mode set. To enable FIDO2 later: ykman config mode OTP+FIDO+CCID"
~~~

**Step 6.3: Set Touch Policy**

~~~bash
echo ">>> Killing gpg-agent to clear card cache..."
gpgconf --kill gpg-agent

echo ">>> Re-plug the YubiKey and press Enter to continue..."
read

gpg --card-status | grep -q "OpenPGP card" && echo "✅ YubiKey detected after CCID mode switch" || echo "❌ CRITICAL: YubiKey not detected."

ykman openpgp keys set-touch sig ON
ykman openpgp keys set-touch aut ON
ykman openpgp keys set-touch enc ON
~~~

## **Phase 7: Loading Keys to Hardware**

**Goal:** Move subkeys to both YubiKeys (removes them from disk). The backup snapshot remains the recovery point.

**Step 7.1: Snapshot Keyring**

~~~bash
echo ">>> Creating backup snapshot of keyring before hardware transfer..."
cp -r "$GNUPGHOME" "$GNUPGHOME.bak"
ls -ld "$GNUPGHOME.bak" && echo "✅ Snapshot created: $GNUPGHOME.bak" || echo "❌ CRITICAL: Snapshot creation failed"
~~~

**Step 7.2: Load YubiKey #1 (Primary)**

~~~bash
echo ">>> Pre-flight checks for YubiKey #1..."
if ! gpg --card-status | grep -q "OpenPGP card"; then
  echo "❌ CRITICAL: YubiKey not detected. Insert YubiKey #1 and try again."
else
  echo "✅ YubiKey #1 detected"
fi
SUBKEY_COUNT=$(gpg --list-secret-keys "$KEYID" | grep -c "^ssb")
[ "$SUBKEY_COUNT" -ne 3 ] && echo "❌ CRITICAL: Expected 3 subkeys, found $SUBKEY_COUNT" || echo "✅ All 3 subkeys present (Sign, Encrypt, Auth)"

gpg --list-secret-keys --with-keygrip --with-subkey-fingerprint "$KEYID"
read -p "Confirm ordering matches expected (S,E,A). Press Enter to continue or Ctrl+C to abort..." _

cat << 'EOF'
⚠️  CRITICAL CHECKPOINT: POINT OF NO RETURN (YubiKey #1)
- Keys will move to YubiKey #1 and be recoverable only from the snapshot.
- Both YubiKeys will hold identical keys.
- Confirm snapshot and backups exist.
EOF
-read -p "Type 'YES' to proceed with keytocard on YubiKey #1: " CONFIRM
-[ "$CONFIRM" != "YES" ] && { echo "❌ Operation cancelled."; exit 1; } || echo "✅ Proceeding with keytocard for YubiKey #1..."
+read -p "Type 'YES' to proceed with keytocard on YubiKey #1: " CONFIRM
+if [ "$CONFIRM" != "YES" ]; then
+  echo "❌ Operation cancelled."
+  return 1 2>/dev/null || true
+else
+  echo "✅ Proceeding with keytocard for YubiKey #1..."
+fi

echo ">>> Starting GPG interactive session for YubiKey #1..."
cat << 'EOF'
At the gpg> prompt:
- key 1 → keytocard → 1 (Signature) → Admin PIN → key 1 (deselect)
- key 2 → keytocard → 2 (Encryption) → Admin PIN → key 2 (deselect)
- key 3 → keytocard → 3 (Authentication) → Admin PIN
- save
EOF
read -p "Press Enter to start the interactive session..." _

gpg --edit-key "$KEYID"

echo ">>> Verifying YubiKey #1 key transfer..."
gpgconf --kill gpg-agent; sleep 2

gpg --card-status | grep -q "Signature key" && echo "✅ Signature key detected on YubiKey #1" || echo "⚠️  Signature key not detected"
gpg --card-status | grep -q "Encryption key" && echo "✅ Encryption key detected on YubiKey #1" || echo "⚠️  Encryption key not detected"
gpg --card-status | grep -q "Authentication key" && echo "✅ Authentication key detected on YubiKey #1" || echo "⚠️  Authentication key not detected"

gpg --list-secret-keys "$KEYID"
-read -p "Remove YubiKey #1, then press Enter..." _
read -p "Remove YubiKey #1, then press Enter..." _
~~~

**Step 7.3: Load YubiKey #2 (Backup)**

~~~bash
echo ">>> Pre-flight checks for YubiKey #2..."
if ! gpg --card-status | grep -q "OpenPGP card"; then
  echo "❌ CRITICAL: YubiKey not detected. Insert YubiKey #2 and try again."
else
  echo "✅ YubiKey #2 detected"
fi
if gpg --card-status | grep -q "Signature key.*\[key1\]"; then
  echo "⚠️  WARNING: This YubiKey appears to already have keys. Ensure YubiKey #1 is removed."; read -p "Press Enter to continue if certain..." _
fi

echo ">>> Restoring keys to disk from backup snapshot..."
gpgconf --kill gpg-agent
rm -rf "$GNUPGHOME"
cp -r "$GNUPGHOME.bak" "$GNUPGHOME"

gpg --list-secret-keys "$KEYID" >/dev/null 2>&1 && echo "✅ Keys restored from snapshot" || echo "❌ CRITICAL: Key restoration from snapshot failed"
SUBKEY_COUNT=$(gpg --list-secret-keys "$KEYID" | grep -c "^ssb")
[ "$SUBKEY_COUNT" -ne 3 ] && echo "❌ CRITICAL: Expected 3 subkeys after restoration, found $SUBKEY_COUNT" || echo "✅ All 3 subkeys restored"

gpg --list-secret-keys --with-keygrip "$KEYID"

cat << 'EOF'
⚠️  CRITICAL CHECKPOINT: POINT OF NO RETURN (YubiKey #2)
- Subkeys will move to YubiKey #2.
- Recovery point is the snapshot at $GNUPGHOME.bak.
EOF
-read -p "Type 'YES' to proceed with keytocard on YubiKey #2: " CONFIRM
-[ "$CONFIRM" != "YES" ] && { echo "❌ Operation cancelled."; exit 1; } || echo "✅ Proceeding with keytocard for YubiKey #2..."
+read -p "Type 'YES' to proceed with keytocard on YubiKey #2: " CONFIRM
+if [ "$CONFIRM" != "YES" ]; then
+  echo "❌ Operation cancelled."
+  return 1 2>/dev/null || true
+else
+  echo "✅ Proceeding with keytocard for YubiKey #2..."
+fi

echo ">>> Starting GPG interactive session for YubiKey #2..."
cat << 'EOF'
At the gpg> prompt:
- key 1 → keytocard → 1 (Signature) → Admin PIN → key 1 (deselect)
- key 2 → keytocard → 2 (Encryption) → Admin PIN → key 2 (deselect)
- key 3 → keytocard → 3 (Authentication) → Admin PIN
- save
EOF
read -p "Press Enter to start the interactive session..." _

gpg --edit-key "$KEYID"

echo ">>> Verifying YubiKey #2 key transfer..."
gpgconf --kill gpg-agent; sleep 2

gpg --card-status | grep -q "Signature key" && echo "✅ Signature key detected on YubiKey #2" || echo "⚠️  Signature key not detected"
gpg --card-status | grep -q "Encryption key" && echo "✅ Encryption key detected on YubiKey #2" || echo "⚠️  Encryption key not detected"
gpg --card-status | grep -q "Authentication key" && echo "✅ Authentication key detected on YubiKey #2" || echo "⚠️  Authentication key not detected"

gpg --list-secret-keys "$KEYID"
~~~

## **Phase 8: Final Verification & Cleanup**

**Goal:** Verify hardware operation and wipe RAM.

**Step 8.1: Test YubiKey**

~~~bash
if ! gpg --card-status | grep -q "OpenPGP card"; then
  echo "❌ CRITICAL: YubiKey not detected for final testing"
else
  echo "✅ YubiKey detected for final testing"
fi

echo "Testing Signature..." | gpg --sign --armor > test_signature.asc
if gpg --verify test_signature.asc 2>&1 | grep -q "Good signature"; then
  echo "✅ Signature verification passed"
else
  echo "⚠️  Signature verification check: Review output above"
fi
rm test_signature.asc
~~~

**Step 8.2: Secure Wipe**

~~~bash
gpgconf --kill gpg-agent

echo ">>> Unmounting USB Backup..."
umount "$USB_BACKUP_PATH" 2>&1 || echo "⚠️  USB unmount failed (may already be unmounted)"

echo ">>> Unmounting SSD Backup..."
umount "$SSD_BACKUP_PATH" 2>&1 || echo "⚠️  SSD unmount failed (may already be unmounted)"

find "$GNUPGHOME" -type f -exec shred -u {} \;
find "$GNUPGHOME.bak" -type f -exec shred -u {} \;
rm -rf "$GNUPGHOME" "$GNUPGHOME.bak"
echo ">>> SETUP COMPLETE. POWER OFF."
~~~

## **Appendix A: Emergency Operations**

### **A.1: Restore from Digital Backup (USB/SSD)**

1. Boot into the clean environment (Phase 0).
2. Mount USB/SSD backup.
3. Import the master key:

~~~bash
gpg --import "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/master_secret.gpg"
~~~

4. Set trust to Ultimate:

~~~bash
gpg --edit-key "$KEYID"
# trust → 5 → y → quit
~~~

5. Verify: `gpg --list-secret-keys`
6. If replacing YubiKeys: go to Phase 5 (generate subkeys) or Phase 7 (load to hardware).

### **A.2: Restore from Paper Backup**

**Online prep:** Ensure **paperkey** and **zbar-tools** are installed. Download your public key (**public_key_bundle.asc**) from WKD/website/keyserver while online.

**Air-gap:** Disconnect network and verify isolation (same check as Phase 0.4).

**Reconstruction:**

~~~bash
zbarcam --raw > scanned_paperkey.txt   # or type manually
paperkey --pubring public_key_bundle.asc --secrets scanned_paperkey.txt --output restored_master.gpg
gpg --import restored_master.gpg
~~~

### **A.3: Revoking a Compromised Subkey**

1. Import master key (A.1 or A.2).
2. Edit keyring:

~~~bash
gpg --edit-key "$KEYID"
~~~

3. Select subkey (`key 1` or `key 2` or `key 3`), confirm `*` shows.
4. `revkey` → Reason: compromised → Description (e.g., "YubiKey #1 Lost") → confirm `y` → `save`.
5. Publish updated public key:

~~~bash
gpg --export "$KEYID" --armor > new_public_bundle.asc
~~~

Upload to WKD/website/keyserver (WKD filename hash is unchanged).

### **A.4: Recovering from Session Interruption**

1. Reopen a terminal.
2. Restore session vars:

~~~bash
source "$GNUPGHOME/session_vars.sh"
~~~

3. Verify variables:

~~~bash
echo "GNUPGHOME: $GNUPGHOME"
echo "Email: $MY_EMAIL"
echo "USB Path: $USB_BACKUP_PATH"
echo "SSD Path: $SSD_BACKUP_PATH"
~~~

4. If **$KEYID** is empty but the master key exists:

~~~bash
export KEYID=$(gpg --list-keys --with-colons "$MY_EMAIL" | awk -F: '/^fpr:/ { print $10; exit }')
echo "Key ID: $KEYID"
~~~

5. Resume the protocol at the appropriate phase.
