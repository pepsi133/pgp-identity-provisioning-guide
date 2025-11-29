# Air-Gapped OpenPGP Root Identity & Hardware Provisioning Protocol

Version: 1.3 (Streamlined for Advanced Users)
Target System: Debian-based Live Linux ISO (e.g., Ubuntu, Debian, or Kali Live). Note: Scripts tested on Standard Kali Live.
Hardware Required:

* 2x **YubiKey 5C NFC** (Tier 2 "Identity" Keys)
* 1x **USB Flash Drive** (Encrypted Backup Target 1)
* 1x **SSD/HDD** (Encrypted Backup Target 2)
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

**Goal:** Verify tools, define variables, and ensure the printer is ready.

Step 0.1: Define Variables
Open your terminal. Edit the variables below to match your identity and storage paths. Copy and paste this block into your shell.

```bash
# --- USER IDENTITY ---
export MY_NAME="Test User"
export MY_EMAIL="testin@test.tst"
# Optional: Secondary email identity (leave empty if not needed)
export MY_EMAIL_2="secondary@test.tst"

# --- STORAGE PATHS (Check 'lsblk' or 'df -h' to confirm mount points) ---
# Ensure your USB/SSD are mounted before running this.
export USB_BACKUP_PATH="/media/kali/zielony_po_Lucjanku"
export SSD_BACKUP_PATH="/media/kali/ssd_for_backup"

# --- SYSTEM CONSTANTS (Do not change) ---
export GNUPGHOME=/tmp/tmp.gnupg_dpa_tmp
export BACKUP_DIR_NAME="PGP_Master_Backup"
mkdir /tmp/tmp.gnupg_dpa_tmp

# Save variables to a recovery file (optional but useful)
cat << EOF > $GNUPGHOME/session_vars.sh
export MY_NAME="$MY_NAME"
export MY_EMAIL="$MY_EMAIL"
export MY_EMAIL_2="$MY_EMAIL_2"
export USB_BACKUP_PATH="$USB_BACKUP_PATH"
export SSD_BACKUP_PATH="$SSD_BACKUP_PATH"
export GNUPGHOME="$GNUPGHOME"
EOF

echo "✅ Session variables saved to: $GNUPGHOME/session_vars.sh"
echo "   To recover after interruption: source $GNUPGHOME/session_vars.sh"
```

Step 0.2: Pre-Flight Tool Check
Run this snippet to ensure the necessary tools are available and install missing ones.

```bash
# List of required command-line tools (actual executable names)
REQUIRED_TOOLS=("gpg" "paperkey" "qrencode" "zbarimg" "zbarcam" "shuf" "sha256sum" "ykman" "lp")

# Corresponding packages that provide these tools
PACKAGES="gnupg paperkey qrencode zbar-tools coreutils yubikey-manager wamerican scdaemon pcscd cups-client"

echo ">>> Initial Tool Check..."
echo "════════════════════════════════════════════════════════════════"
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        echo "  ✅ $tool"
    else
        echo "  ❌ $tool (missing)"
    fi
done
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check network connectivity before attempting installation
echo ">>> Checking Internet Connectivity..."
if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
    echo "✅ Internet connected."
    NETWORK_OK=1
else
    echo "❌ No internet. Skipping installation."
    NETWORK_OK=0
fi
echo ""

# Only attempt installation if network is available
if [ $NETWORK_OK -eq 1 ]; then
    # Fix Kali Live repository (often broken or pointing to cdrom)
    if ! grep -q "http.*kali.org/kali" /etc/apt/sources.list 2>/dev/null; then
        echo ">>> Adding standard Kali repository..."
        echo "deb http://http.kali.org/kali kali-rolling main non-free contrib" | sudo tee -a /etc/apt/sources.list
    fi

    # Update and install (tolerate errors - Live systems can be flaky)
    echo ">>> Running apt-get update..."
    sudo apt-get update || true
    echo ""

    echo ">>> Installing packages..."
    sudo apt-get install -y $PACKAGES || sudo apt-get install -y --fix-missing $PACKAGES || true
    echo ""
fi

# Start pcscd service (required for YubiKey)
echo ">>> Starting pcscd service..."
sudo systemctl unmask pcscd || true
sudo systemctl start pcscd || true
echo ""

# Final verification
echo ">>> Final Tool Check..."
echo "════════════════════════════════════════════════════════════════"
MISSING_COUNT=0
for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        echo "  ✅ $tool"
    else
        echo "  ❌ $tool (missing)"
        MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
done
echo "════════════════════════════════════════════════════════════════"
echo ""

if [ $MISSING_COUNT -gt 0 ]; then
    echo "⚠️  $MISSING_COUNT tool(s) missing. Install manually: sudo apt-get install -y <package>"
else
    echo "✅ All tools available."
fi
```

**Step 0.3: Printer Setup (Network Required)**

* **Action:** Ensure you are still connected to the internet.
* **Action:** Open the System Settings -> Printers. Add your USB printer.
* **Why:** Linux may need to download drivers or CUPS dependencies to initialize the printer.
* **Verify:** Print a test page now to confirm functionality before disconnecting.

Step 0.4: Establish Air-Gap (CRITICAL)
* **Action:** Physically disconnect the Ethernet cable or disable the Wi-Fi adapter.
* **Verify:** Run the following command to ensure isolation:

```bash
echo ">>> Verifying Air-Gap Status..."
if ip route get 8.8.8.8 &>/dev/null; then
    echo "❌ CRITICAL: Default route exists. Network may still be reachable."
    ip route show
elif ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
    echo "❌ CRITICAL: Ping succeeded. Network is reachable."
else
    echo "✅ Air-gap verified: Network is unreachable"
fi
```

* **Warning:** Do not reconnect to the internet for the remainder of this session.

## **Phase 1: Secure Session Setup**

**Goal:** Create a hardened, RAM-based GPG environment.

Step 1.1: Harden GPG Configuration
Apply strong crypto preferences and S2K (String-to-Key) hardening.

```bash
cat << EOF > $GNUPGHOME/gpg.conf
personal-cipher-preferences AES256 AES192 AES
personal-digest-preferences SHA512 SHA384 SHA256
personal-compress-preferences ZLIB BZIP2 ZIP Uncompressed
default-preference-list SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed
cert-digest-algo SHA512
s2k-digest-algo SHA512
s2k-cipher-algo AES256
s2k-count 65011712
EOF

# Configure agent to prevent cache timeouts during this long session
echo "default-cache-ttl 7200" > $GNUPGHOME/gpg-agent.conf
echo "max-cache-ttl 7200" >> $GNUPGHOME/gpg-agent.conf
gpg-connect-agent reloadagent /bye
```

Step 1.2: Generate Master Passphrase
Do not invent a password. Let the entropy pool do it.

```bash
echo "------------------------------------------------"
echo "WRITE THIS DOWN (Your Master Key Passphrase):"
echo "------------------------------------------------"
shuf -n 6 /usr/share/dict/words | tr '\n' ' '
echo -e "\n------------------------------------------------"
```

* **Action:** Write these 6 words on your permanent paper storage card.
* **Verify:** Read it aloud to yourself.

## **Phase 2: Master Key Generation**

**Goal:** Create the "Certify" (C) only Master Key using Ed25519.

**Step 2.1: Generate Key**

```bash
gpg --expert --full-gen-key
```

**Interactive Selections:**

1. **Key type:** (11) ECC (set your own capabilities)
2. **Elliptic Curve:** (1) Curve 25519
3. **Key Usage:**
   * *Default is Sign & Certify. We want Certify ONLY.*
   * Toggle Sign: Type `s` \[Enter\]
   * Toggle Encrypt: Type `e` \[Enter\]
   * *Check:* Current allowed actions: Certify
   * Finish: Type `q` \[Enter\]
4. **Validity:** 0 (Key does not expire).
5. **Confirm:** y
6. **ID:** Type the actual values defined in Phase 0 (e.g., 'FirstName...'). Do not type the literal variable name $MY_NAME.
7. **Passphrase:** Enter the 6 words from Phase 1.

**Step 2.2: Capture Key ID**

```bash
export KEYID=$(gpg --list-keys --with-colons | awk -F: '/^fpr:/ { print $10; exit }')
echo "Key ID Generated: $KEYID"

# Verify key was created successfully
gpg --list-secret-keys "$KEYID" && echo "✅ Master key verified: $KEYID" || echo "❌ WARNING: Master key not found"
```

**Step 2.3: Add Secondary Identity (Optional)**

```bash
# Check if secondary email is configured
if [ -n "$MY_EMAIL_2" ]; then
    echo ">>> Adding secondary identity: $MY_EMAIL_2"
    gpg --quick-add-uid "$KEYID" "$MY_EMAIL_2"
    
    # Verify the new UID was added
    gpg --list-keys "$KEYID" | grep -q "$MY_EMAIL_2" && echo "✅ Secondary identity added" || echo "❌ WARNING: Secondary identity not found"
fi

# Set trust to ultimate (applies to all UIDs on the key)
echo ">>> Attempting to set trust to ultimate..."
echo -e "5\ny\n" | gpg --command-fd 0 --edit-key "$KEYID" trust quit

echo ""
echo "If automatic trust setting failed, set it manually:"
echo "  gpg --edit-key $KEYID"
echo "  > trust"
echo "  > 5"
echo "  > y"
echo "  > quit"
echo ""

# Display key with all identities (trust level will be visible)
echo ">>> Current key structure (verify trust shows [ultimate]):"
gpg --list-keys "$KEYID"
echo ""
```

## **Phase 3: Physical & Digital Backups (Including Revocation)**

**Goal:** Create the "Triple Redundancy" backup and export the critical Revocation Certificate.

**Step 3.1: Generate Backup Artifacts**

```bash
cd $GNUPGHOME

# 1. Export Secret Key
gpg --export-secret-key $KEYID > master_secret.gpg

# 2. Generate Revocation Certificate (CRITICAL STEP - Interactive Prompts Expected)
# This is your "break glass" file if you lose the master key.
echo ">>> Generating Revocation Certificate (You will be prompted)..."
echo "    Reason: Select '0' (No reason specified)"
echo "    Description: Type 'Backup Revocation' or leave blank"
echo "    Confirm: Type 'y'"
gpg --gen-revoke $KEYID > revocation_cert.asc

# Verify file was created
ls -lh revocation_cert.asc

# 3. Create Paperkey (Human/OCR readable text)
paperkey --secret-key master_secret.gpg --output master_paperkey.txt

# 4. Create Checksum (Critical for verification)
sha256sum master_secret.gpg > master_checksum.txt

# 5. Generate QR Codes (Using Medium error correction for better scan reliability)
cat master_checksum.txt | qrencode -l M -o checksum_qr.png
cat revocation_cert.asc | qrencode -l M -o revocation_qr.png

# Verify all artifacts were created
ls -lh master_secret.gpg revocation_cert.asc master_paperkey.txt master_checksum.txt checksum_qr.png revocation_qr.png
```

**Step 3.2: Print Paper Backups**

```bash
echo ">>> Printing Paper Backups (QR Codes + Raw ASCII for fallback)..."

# Print QR codes
lp checksum_qr.png
lp revocation_qr.png

# Print raw ASCII files (fallback if QR scanning fails later)
lp master_checksum.txt
lp revocation_cert.asc
lp master_paperkey.txt

echo "✅ Paper backups printed. Store in secure location."
```

**Step 3.3: Verification Tests**

**Part A: QR Code Scan Verification (CRITICAL - Do This First)**

Test that printed QR codes are actually scannable before proceeding. If they're too dense or printer quality is poor, you'll discover it now, not during emergency recovery.

```bash
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "⚠️  CRITICAL: QR CODE SCAN TEST"
echo "═══════════════════════════════════════════════════════════════"
echo "We must verify the printed QR codes are scannable NOW."
echo "If scanning fails, you have time to:"
echo "  - Adjust QR error correction level (try -l H for high)"
echo "  - Use a different printer"
echo "  - Split large QR codes into smaller chunks"
echo "  - Rely on raw ASCII printouts instead"
echo ""
echo "Testing THREE QR codes: Checksum, Revocation, and Master Paperkey"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Test 1: Checksum QR
echo ">>> TEST 1/3: Scan the CHECKSUM QR code (small, should be easy)"
echo "    Hold printed checksum_qr.png to camera. Press Ctrl+C if it fails."
zbarcam --raw > scanned_checksum.txt 2>/dev/null

if diff -w master_checksum.txt scanned_checksum.txt > /dev/null 2>&1; then
    echo "✅ Checksum QR scan successful"
else
    echo "❌ WARNING: Checksum QR scan failed or doesn't match"
    echo "    You can manually type from printed master_checksum.txt if needed"
fi
rm -f scanned_checksum.txt

# Test 2: Revocation Certificate QR
echo ""
echo ">>> TEST 2/3: Scan the REVOCATION CERTIFICATE QR code"
echo "    This may be large. Hold printed revocation_qr.png to camera."
zbarcam --raw > scanned_revocation.txt 2>/dev/null

if diff -w revocation_cert.asc scanned_revocation.txt > /dev/null 2>&1; then
    echo "✅ Revocation Certificate QR scan successful"
else
    echo "❌ WARNING: Revocation QR scan failed or doesn't match"
    echo "    You can use printed revocation_cert.asc (raw ASCII) instead"
fi
rm -f scanned_revocation.txt

# Test 3: Master Paperkey QR (if generated)
# Note: This test will be repeated in Phase 5.5 after subkeys are added
echo ""
echo ">>> Skipping Master Paperkey QR test for now (will test in Phase 5.5)"
echo "    After subkeys are added, we'll regenerate and test it."
echo ""
echo "✅ QR Code scan verification complete"
echo "   If any scans failed, you still have raw ASCII printouts as backup."
echo ""
read -p "Press Enter to continue to digital verification tests..."
```

**Part B: Digital Check (Master Key)**

Verify that the paperkey backup matches the master secret key purely in software.

```bash
# Need public key to reconstruct secret for verification
gpg --export $KEYID > pubkey_test.gpg

# Reconstruct secret key from paperkey text
paperkey --pubring pubkey_test.gpg --secrets master_paperkey.txt --output test_secret.gpg

# Compare Checksums
HASH_ORIG=$(sha256sum master_secret.gpg | awk '{print $1}')
HASH_RECONSTRUCT=$(sha256sum test_secret.gpg | awk '{print $1}')

echo "Original:      $HASH_ORIG"
echo "Reconstructed: $HASH_RECONSTRUCT"

[ "$HASH_ORIG" == "$HASH_RECONSTRUCT" ] && echo "✅ DIGITAL CHECK PASSED" || echo "❌ FAILURE: Hashes don't match"

# Clean up temporary test files
rm -f pubkey_test.gpg test_secret.gpg
```

**Part C: Additional Integrity Checks**

Generate and verify checksums for all backup artifacts.

```bash
echo ">>> Generating comprehensive checksums for all backup files..."
sha256sum revocation_cert.asc master_paperkey.txt >> master_checksum.txt

echo ">>> All verification tests complete."
echo "    Proceed to backup storage (Step 3.4)"
```

**Step 3.4: Save to USB & SSD**

```bash
# Create Folders
mkdir -p "$USB_BACKUP_PATH/$BACKUP_DIR_NAME"
mkdir -p "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME"

# Copy files
for FILE in master_secret.gpg revocation_cert.asc master_checksum.txt master_paperkey.txt gpg.conf gpg-agent.conf; do
    cp "$FILE" "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
    cp "$FILE" "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"
done

sync

# Verify backup contents (manual inspection)
echo ">>> USB Backup Contents:"
ls -lh "$USB_BACKUP_PATH/$BACKUP_DIR_NAME"
echo ""
echo ">>> SSD Backup Contents:"
ls -lh "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME"
echo ""
echo "⚠️  MANUAL CHECK: Ensure all files above match the expected list."
echo ""
echo "⚠️  MANUAL CHECK: Ensure all files above match the expected list."

echo ""
echo "✅ Master backup completed - essential files copied to both USB and SSD."
echo "📁 Master backup contents and purpose:"
echo "   🔑 master_secret.gpg - Exported master secret key (ESSENTIAL for restoration)"
echo "   🚨 revocation_cert.asc - Emergency revocation certificate (ESSENTIAL for key revocation)"
echo "   ✅ master_checksum.txt - SHA256 checksum for integrity verification (ESSENTIAL)"
echo "   📄 master_paperkey.txt - Human-readable text backup (can recreate master_secret.gpg)"
echo "   ⚙️  GPG configs - gpg.conf and gpg-agent.conf (hardened security preferences)"
echo ""
echo "Note: QR codes are generated and printed for paper backup only (not stored digitally)"
echo "Note: public_key_bundle.asc and WKD files will be created in Phase 5"
```

## **Phase 4: The "Clean Slate" Restoration Test**

**Goal:** Prove that the digital backup actually works by destroying the local key and restoring it.

**Step 4.1: Wipe Local GPG Home**

```bash
rm -rf $GNUPGHOME/private-keys-v1.d
rm $GNUPGHOME/pubring.kbx $GNUPGHOME/trustdb.gpg
echo "Local keys wiped."
```

**Step 4.2: Restore from USB**

```bash
# Import master key from backup
gpg --import "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/master_secret.gpg"

# Set trust to Ultimate (Interactive)
echo ">>> Setting key trust level (You will be prompted):"
echo "    1. Type: trust"
echo "    2. Select: 5 (Ultimate)"
echo "    3. Confirm: y"
echo "    4. Exit: quit"
gpg --edit-key $KEYID

# Verify trust was set
gpg --list-keys $KEYID | grep -E "^uid.*\[ultimate\]" && echo "✅ Trust level verified: Ultimate" || echo "⚠️  Trust level check: Review output above"

# Verify Import
gpg --list-secret-keys $KEYID | grep -q "sec" && echo "✅ RESTORE SUCCESS: Master key operational." || echo "❌ FAILURE: Could not import from USB."
```

## **Phase 5: Subkey Generation**

**Goal:** Generate the S/E/A subkeys and prepare public files.

**Step 5.1: Create Subkeys**

```bash
gpg --expert --edit-key $KEYID
```

*At the gpg> prompt:*

1. **Signing Subkey:**
   * `addkey` -> (10) ECC (sign only) -> Curve 25519 -> Expiry: 1y -> save
   * *Re-enter:* `gpg --expert --edit-key $KEYID`
2. **Encryption Subkey:**
   * `addkey` -> (12) ECC (encrypt only) -> Curve 25519 -> Expiry: 1y -> save
   * *Re-enter:* `gpg --expert --edit-key $KEYID`
3. **Authentication Subkey:**
   * `addkey` -> (11) ECC (set your own capabilities)
   * Toggle Sign `s` (OFF)
   * Toggle Auth `a` (ON)
   * Finish `q` -> Curve 25519 -> Expiry: 1y -> save

Step 5.2: WKD Hash Calculation & Export

We calculate the WKD filenames for primary and secondary emails now so you don't have to do it later.

```bash
cd $GNUPGHOME

# 1. Export Public Bundle (ASCII Armored) - For GitHub/Keyservers
gpg --export $KEYID --armor > public_key_bundle.asc

# 2. Extract Primary WKD Hash Automatically
echo ">>> Extracting WKD hash for: $MY_EMAIL"
WKD_HASH=$(gpg --with-wkd-hash --list-keys "$MY_EMAIL" | grep -A1 "$MY_EMAIL" | grep -v "@" | awk '{print $1}')

if [ -z "$WKD_HASH" ]; then
    echo "❌ CRITICAL: Automatic WKD hash extraction failed for $MY_EMAIL"
    echo "    Manual extraction required. Run the following command and observe the output:"
    echo ""
    gpg --with-wkd-hash --list-keys "$MY_EMAIL"
    echo ""
    echo "    Find the 32-character hash string under '$MY_EMAIL' (looks like: z4y9cea8...)"
    read -p "    Paste the PRIMARY WKD hash here: " WKD_HASH
    
    # Verify user provided a value
    if [ -z "$WKD_HASH" ]; then
        echo "❌ CRITICAL: No WKD hash provided. Cannot proceed."
        echo "    Set manually: export WKD_HASH=\"your_hash_here\""
    fi
fi

# Verify hash was captured (either automatically or manually)
if [ -n "$WKD_HASH" ]; then
    echo "✅ Primary WKD Hash: $WKD_HASH"
    gpg --export $KEYID > "$WKD_HASH"
    
    # Verify file was created
    [ -f "$WKD_HASH" ] && echo "✅ Primary WKD binary file created" || echo "❌ CRITICAL: Failed to create WKD file '$WKD_HASH'"
fi

# 3. Handle Secondary Email (if configured)
if [ -n "$MY_EMAIL_2" ]; then
    echo ""
    echo ">>> Extracting WKD hash for: $MY_EMAIL_2"
    WKD_HASH_2=$(gpg --with-wkd-hash --list-keys "$MY_EMAIL_2" | grep -A1 "$MY_EMAIL_2" | grep -v "@" | awk '{print $1}')

    if [ -z "$WKD_HASH_2" ]; then
        echo "❌ WARNING: Automatic WKD hash extraction failed for $MY_EMAIL_2"
        echo "    Manual extraction required. Run the following command and observe the output:"
        echo ""
        gpg --with-wkd-hash --list-keys "$MY_EMAIL_2"
        echo ""
        echo "    Find the 32-character hash string under '$MY_EMAIL_2' (looks like: z4y9cea8...)"
        read -p "    Paste the SECONDARY WKD hash here (or press Enter to skip): " WKD_HASH_2
        
        # User can skip secondary email if they want
        if [ -z "$WKD_HASH_2" ]; then
            echo "⚠️  WARNING: Secondary WKD hash not provided. Skipping."
            echo "    To set later: export WKD_HASH_2=\"your_hash_here\""
        fi
    fi

    # Create secondary WKD file only if hash was captured
    if [ -n "$WKD_HASH_2" ]; then
        echo "✅ Secondary WKD Hash: $WKD_HASH_2"
        gpg --export $KEYID > "$WKD_HASH_2"
        
        # Verify file was created
        [ -f "$WKD_HASH_2" ] && echo "✅ Secondary WKD binary file created" || echo "❌ WARNING: Failed to create WKD file '$WKD_HASH_2'"
    fi
else
    echo ">>> Skipping secondary email WKD (not configured)"
fi

# 4. Save to backup media
echo ""
echo ">>> Saving public key exports to backup media..."

# Copy the ASCII bundle (always created)
cp public_key_bundle.asc "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
cp public_key_bundle.asc "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"

# Copy the primary WKD Binary File (only if it exists)
if [ -f "$WKD_HASH" ]; then
    cp "$WKD_HASH" "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
    cp "$WKD_HASH" "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"
    
    # Save hash string to text file for reference
    echo "$WKD_HASH" > "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/wkd_filename.txt"
    echo "$WKD_HASH" > "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/wkd_filename.txt"
fi

# Copy the secondary WKD Binary File (only if it exists)
if [ -n "$MY_EMAIL_2" ] && [ -f "$WKD_HASH_2" ]; then
    cp "$WKD_HASH_2" "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
    cp "$WKD_HASH_2" "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"
    
    # Save hash string to text file for reference
    echo "$WKD_HASH_2" > "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/wkd_filename_secondary.txt"
    echo "$WKD_HASH_2" > "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/wkd_filename_secondary.txt"
fi

# Verify backup contents
echo ""
echo ">>> Verifying public key backups:"
ls -lh "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/" | grep -E "(public_key_bundle|wkd_filename|^[a-z0-9]{32}$)"

sync

echo ""
echo "✅ Public keys saved:"
echo "   📄 public_key_bundle.asc - ASCII armored public key for GitHub/Keyservers"
if [ -f "$WKD_HASH" ]; then
    echo "   🌐 $WKD_HASH - WKD binary for $MY_EMAIL (upload to .well-known/openpgpkey/hu/)"
fi
if [ -n "$MY_EMAIL_2" ] && [ -f "$WKD_HASH_2" ]; then
    echo "   🌐 $WKD_HASH_2 - WKD binary for $MY_EMAIL_2 (upload to .well-known/openpgpkey/hu/)"
fi
echo ""
echo "📝 Manual Override Commands (if needed):"
echo "   export WKD_HASH=\"your_primary_hash_here\""
echo "   export WKD_HASH_2=\"your_secondary_hash_here\""
```

## **Phase 5.5: Finalize Master Key Backup with Subkeys (CRITICAL)**

**Goal:** Update the physical backups to include the newly generated S/E/A subkeys and print the complete Master Key artifacts.

**Step 5.5.1: Re-Export, Print, and Verify**

```bash
cd $GNUPGHOME

# 1. Export Secret Keys AGAIN (Now includes Master + Subkeys)
gpg --export-secret-key $KEYID > master_secret.gpg

# 2. Update Checksum (CRITICAL: Key content changed, so hash changed)
sha256sum master_secret.gpg > master_checksum.txt

# 3. Regenerate Print Artifacts (Paperkey & QRs)
paperkey --secret-key master_secret.gpg --output master_paperkey.txt
# Generate QR for Master Key (Using Medium error correction for better scan reliability)
cat master_paperkey.txt | qrencode -l M -o master_qr.png
# Generate QR for Checksum (For paper verification only)
cat master_checksum.txt | qrencode -l M -o checksum_qr.png

# 4. PRINT BACKUPS (Paperkey + QR + Checksum)
echo ">>> Printing Master Key Artifacts..."
lp master_qr.png
echo ">>> Printing Master Key Paper Backup..."
lp master_paperkey.txt

echo ">>> Printing Checksum (Keep this with your paper key)..."
lp checksum_qr.png
lp master_checksum.txt

# 5. Physical Loopback Verification
echo ">>> VERIFICATION: Scan the printed Master QR code now."
zbarcam --raw | tee scanned_output.txt

# Verify against digital file
diff -w master_paperkey.txt scanned_output.txt > /dev/null && echo "✅ PHYSICAL BACKUP VERIFIED: Printed QR matches digital file." || echo "❌ FAILURE: Printed QR does not match."

# 6. Update Digital Backups (USB & SSD)
# NOTE: We do NOT copy QR codes to disk. They are for paper only.
echo ">>> Updating USB Backup..."
cp master_secret.gpg "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"
cp master_checksum.txt "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/"

echo ">>> Updating SSD Backup..."
cp master_secret.gpg "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"
cp master_checksum.txt "$SSD_BACKUP_PATH/$BACKUP_DIR_NAME/"

# 7. Cleanup Temporary Files
rm scanned_output.txt master_qr.png checksum_qr.png
echo "🧹 Cleanup complete."
```

## **Phase 6: YubiKey Configuration (PINs & Touch)**

**Goal:** Secure the hardware keys. *Perform for BOTH YubiKeys.*

**Step 6.1: Set PINs (Mandatory)**

* **User PIN:** 6-8 digits (Memorize). Default: 123456
* **Admin PIN:** 8+ chars (Store in Safe). Default: 12345678

```bash
# Ensure only ONE key is plugged in
# Verify YubiKey is detected before proceeding
gpg --card-status | grep -q "OpenPGP card" && echo "✅ YubiKey detected, proceeding with PIN setup..." || echo "❌ CRITICAL: YubiKey not detected. Insert one YubiKey and try again."

gpg --change-pin
```

1. Select (1) Change PIN
2. Select (3) Change Admin PIN

**Step 6.2: Switch to CCID Mode (Required for Touch Policy)**

**Background:** YubiKeys support multiple USB interface modes (OTP, FIDO2, CCID). OpenPGP requires CCID (Smart Card) mode. This setting is **changeable at any time** and does not affect stored cryptographic keys.

**Note:** We're using CCID-only mode for maximum compatibility during this air-gapped session. You can switch to combined mode (`OTP+FIDO+CCID`) later without affecting your OpenPGP keys.

```bash
echo ">>> Switching YubiKey to CCID-only mode (required for OpenPGP)..."
ykman config mode ccid
echo "✅ CCID mode set."
echo "   To enable FIDO2/U2F later: ykman config mode OTP+FIDO+CCID"
```

**Step 6.3: Set Touch Policy**

```bash
# Kill gpg-agent to clear card cache after mode switch
echo ">>> Killing gpg-agent to clear card cache..."
gpgconf --kill gpg-agent

echo ">>> Re-plug the YubiKey and press Enter to continue..."
read

# Verify YubiKey is detected after re-insertion
gpg --card-status | grep -q "OpenPGP card" && echo "✅ YubiKey detected after CCID mode switch" || echo "❌ CRITICAL: YubiKey not detected. Check connection and try again."

# Require touch for operations
ykman openpgp keys set-touch sig ON
ykman openpgp keys set-touch aut ON
ykman openpgp keys set-touch enc ON
```

## **Phase 7: Loading Keys to Hardware**

**Goal:** Move subkeys to YubiKeys. **WARNING:** Removes them from disk.

**Step 7.1: Snapshot Keyring**

Before making any irreversible changes, create a backup snapshot of the current GPG home directory.

```bash
echo ">>> Creating backup snapshot of keyring before hardware transfer..."
cp -r $GNUPGHOME $GNUPGHOME.bak

# Verify snapshot was created
ls -ld $GNUPGHOME.bak && echo "✅ Snapshot created: $GNUPGHOME.bak" || echo "❌ CRITICAL: Snapshot creation failed"
```

---

**Step 7.2: Load YubiKey #1 (Primary)**

**Pre-Flight Checks:**

```bash
echo ">>> Pre-flight checks for YubiKey #1..."

# 1. Verify YubiKey is detected
if ! gpg --card-status | grep -q "OpenPGP card"; then
    echo "❌ CRITICAL: YubiKey not detected. Insert YubiKey #1 and try again."
    echo "    Debug: Run 'gpg --card-status' manually to see card state"
else
    echo "✅ YubiKey #1 detected"
fi

# 2. Verify all three subkeys exist (should be key 1, 2, 3)
SUBKEY_COUNT=$(gpg --list-secret-keys "$KEYID" | grep -c "^ssb")
if [ "$SUBKEY_COUNT" -ne 3 ]; then
    echo "❌ CRITICAL: Expected 3 subkeys, found $SUBKEY_COUNT"
    echo "    Run 'gpg --list-secret-keys $KEYID' to verify"
else
    echo "✅ All 3 subkeys present (Sign, Encrypt, Auth)"
fi

# 3. Display current key structure with capabilities for reference
echo ""
echo ">>> Current key structure (VERIFY ORDERING BEFORE TRANSFER):"
echo "    The list below shows which key index maps to which capability."
echo "    During transfer, you'll select keys by NUMBER (key 1, key 2, key 3)."
echo ""
gpg --list-secret-keys --with-keygrip --with-subkey-fingerprint "$KEYID"
echo ""
echo "Expected ordering (verify above matches this):"
echo "  ssb   [S]  = Signing (key 1)"
echo "  ssb   [E]  = Encryption (key 2)"
echo "  ssb   [A]  = Authentication (key 3)"
echo ""
read -p "Confirm ordering matches expected? Press Enter to continue or Ctrl+C to abort..."
```

---

**CRITICAL CHECKPOINT: Point of No Return**

```bash
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "⚠️  CRITICAL CHECKPOINT: POINT OF NO RETURN (YubiKey #1)"
echo "═══════════════════════════════════════════════════════════════"
echo "The next operation will PERMANENTLY move subkeys to YubiKey #1."
echo "After this, they can ONLY be recovered from the backup snapshot."
echo ""
echo "IMPORTANT: Both YubiKey #1 and YubiKey #2 will receive IDENTICAL keys."
echo "This creates redundancy - if one YubiKey fails, the other is a backup."
echo ""
echo "Before proceeding, verify:"
echo "  1. YubiKey #1 is inserted and detected (check above)"
echo "  2. Backup snapshot exists at: $GNUPGHOME.bak"
echo "  3. Digital backups are confirmed at:"
echo "     - USB: $USB_BACKUP_PATH/$BACKUP_DIR_NAME"
echo "     - SSD: $SSD_BACKUP_PATH/$BACKUP_DIR_NAME"
echo "  4. You have the Admin PIN for this YubiKey ready"
echo ""
read -p "Type 'YES' to proceed with YubiKey #1 keytocard operation: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "❌ Operation cancelled by user."
    echo "   You may re-run this phase when ready."
    echo "   To restart: gpg --edit-key $KEYID"
else
    echo "✅ Proceeding with keytocard for YubiKey #1..."
fi
```

---

**Interactive Key Transfer:**

```bash
echo ""
echo ">>> Starting GPG interactive session for YubiKey #1..."
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "INSTRUCTIONS FOR GPG INTERACTIVE SESSION (YubiKey #1)"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "You will see a 'gpg>' prompt. Follow these steps EXACTLY:"
echo ""
echo "--- STEP 1: Transfer Signing Subkey (S) ---"
echo "  1. Type: key 1"
echo "     (You should see 'ssb*' next to the signing key - asterisk means selected)"
echo "  2. Type: keytocard"
echo "  3. Select: 1 (Signature key)"
echo "  4. Enter Admin PIN when prompted"
echo "  5. Type: key 1"
echo "     (This DESELECTS the key - asterisk should disappear)"
echo ""
echo "--- STEP 2: Transfer Encryption Subkey (E) ---"
echo "  1. Type: key 2"
echo "     (You should see 'ssb*' next to the encryption key)"
echo "  2. Type: keytocard"
echo "  3. Select: 2 (Encryption key)"
echo "  4. Enter Admin PIN when prompted"
echo "  5. Type: key 2"
echo "     (This DESELECTS the key)"
echo ""
echo "--- STEP 3: Transfer Authentication Subkey (A) ---"
echo "  1. Type: key 3"
echo "     (You should see 'ssb*' next to the authentication key)"
echo "  2. Type: keytocard"
echo "  3. Select: 3 (Authentication key)"
echo "  4. Enter Admin PIN when prompted"
echo "  5. NO NEED to deselect (we're done)"
echo ""
echo "--- STEP 4: Save and Exit ---"
echo "  1. Type: save"
echo "     (This commits the changes and exits)"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Press Enter to start the interactive session..."
read

gpg --edit-key $KEYID
```

---

**Post-Transfer Verification (YubiKey #1):**

```bash
echo ""
echo ">>> Verifying YubiKey #1 key transfer..."

# Kill and restart agent to refresh card state
gpgconf --kill gpg-agent
sleep 2

# Check if keys are now on the card
if ! gpg --card-status | grep -q "Signature key"; then
    echo "⚠️  WARNING: Signature key not detected on YubiKey #1"
    echo "    Run 'gpg --card-status' manually to inspect"
else
    echo "✅ Signature key detected on YubiKey #1"
fi

if ! gpg --card-status | grep -q "Encryption key"; then
    echo "⚠️  WARNING: Encryption key not detected on YubiKey #1"
else
    echo "✅ Encryption key detected on YubiKey #1"
fi

if ! gpg --card-status | grep -q "Authentication key"; then
    echo "⚠️  WARNING: Authentication key not detected on YubiKey #1"
else
    echo "✅ Authentication key detected on YubiKey #1"
fi

# Verify local subkeys are now stubs (indicated by '>' in gpg --list-secret-keys)
echo ""
echo ">>> Local keyring status (subkeys should now show as stubs):"
gpg --list-secret-keys "$KEYID"
echo ""
echo "✅ YubiKey #1 loading complete"
echo "   Remove YubiKey #1 before proceeding to YubiKey #2"
echo ""
read -p "Press Enter after removing YubiKey #1..."
```

---

**Step 7.3: Load YubiKey #2 (Backup)**

**Pre-Flight Checks:**

```bash
echo ""
echo ">>> Pre-flight checks for YubiKey #2..."

# 1. Verify YubiKey #2 is detected and is a DIFFERENT card
if ! gpg --card-status | grep -q "OpenPGP card"; then
    echo "❌ CRITICAL: YubiKey not detected. Insert YubiKey #2 and try again."
    echo "    Debug: Run 'gpg --card-status' manually to see card state"
else
    echo "✅ YubiKey #2 detected"
fi

# 2. Warn if YubiKey #2 appears to be the same card (has keys already)
if gpg --card-status | grep -q "Signature key.*\[key1\]"; then
    echo "⚠️  WARNING: This YubiKey appears to already have keys loaded."
    echo "    Ensure you removed YubiKey #1 and inserted YubiKey #2."
    echo "    Press Ctrl+C to abort if this is YubiKey #1."
    read -p "Press Enter to continue if you are certain this is YubiKey #2..."
fi
```

---

**Restore Keys to Disk:**

Before loading YubiKey #2, we must restore the subkeys to disk from the backup snapshot (since YubiKey #1 already removed them).

```bash
echo ">>> Restoring keys to disk from backup snapshot..."

# Kill agent to ensure clean state
gpgconf --kill gpg-agent

# Remove current GPG home (which has stubs pointing to YubiKey #1)
rm -rf $GNUPGHOME

# Restore from snapshot
cp -r $GNUPGHOME.bak $GNUPGHOME

# Verify restoration worked
if ! gpg --list-secret-keys "$KEYID" &>/dev/null; then
    echo "❌ CRITICAL: Key restoration from snapshot failed"
    echo "    Snapshot path: $GNUPGHOME.bak"
    echo "    Run 'gpg --list-secret-keys' to debug"
else
    echo "✅ Keys restored from snapshot"
fi

# Verify all three subkeys exist again (should NOT be stubs)
SUBKEY_COUNT=$(gpg --list-secret-keys "$KEYID" | grep -c "^ssb")
if [ "$SUBKEY_COUNT" -ne 3 ]; then
    echo "❌ CRITICAL: Expected 3 subkeys after restoration, found $SUBKEY_COUNT"
    echo "    Run 'gpg --list-secret-keys $KEYID' to verify"
else
    echo "✅ All 3 subkeys restored (ready for YubiKey #2)"
fi

# Display current key structure for reference
echo ""
echo ">>> Current key structure (for reference during keytocard):"
gpg --list-secret-keys --with-keygrip "$KEYID"
echo ""
```

---

**CRITICAL CHECKPOINT: Point of No Return (YubiKey #2)**

```bash
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "⚠️  CRITICAL CHECKPOINT: POINT OF NO RETURN (YubiKey #2)"
echo "═══════════════════════════════════════════════════════════════"
echo "The next operation will PERMANENTLY move subkeys to YubiKey #2."
echo "This is the FINAL hardware transfer. After this:"
echo "  - Subkeys will exist ONLY on YubiKey #1 and YubiKey #2"
echo "  - The backup snapshot ($GNUPGHOME.bak) is your last recovery point"
echo ""
echo "Before proceeding, verify:"
echo "  1. YubiKey #2 is inserted and detected (check above)"
echo "  2. YubiKey #1 has been removed"
echo "  3. Keys were successfully restored from snapshot (check above)"
echo "  4. You have the Admin PIN for YubiKey #2 ready"
echo ""
read -p "Type 'YES' to proceed with YubiKey #2 keytocard operation: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "❌ Operation cancelled by user."
    echo "   You may re-run this phase when ready."
    echo "   To restart: gpg --edit-key $KEYID"
else
    echo "✅ Proceeding with keytocard for YubiKey #2..."
fi
```

---

**Interactive Key Transfer (YubiKey #2):**

```bash
echo ""
echo ">>> Starting GPG interactive session for YubiKey #2..."
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "INSTRUCTIONS FOR GPG INTERACTIVE SESSION (YubiKey #2)"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "You will see a 'gpg>' prompt. Follow these steps EXACTLY:"
echo ""
echo "--- STEP 1: Transfer Signing Subkey (S) ---"
echo "  1. Type: key 1"
echo "  2. Type: keytocard"
echo "  3. Select: 1 (Signature key)"
echo "  4. Enter Admin PIN when prompted"
echo "  5. Type: key 1 (deselect)"
echo ""
echo "--- STEP 2: Transfer Encryption Subkey (E) ---"
echo "  1. Type: key 2"
echo "  2. Type: keytocard"
echo "  3. Select: 2 (Encryption key)"
echo "  4. Enter Admin PIN when prompted"
echo "  5. Type: key 2 (deselect)"
echo ""
echo "--- STEP 3: Transfer Authentication Subkey (A) ---"
echo "  1. Type: key 3"
echo "  2. Type: keytocard"
echo "  3. Select: 3 (Authentication key)"
echo "  4. Enter Admin PIN when prompted"
echo ""
echo "--- STEP 4: Save and Exit ---"
echo "  1. Type: save"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Press Enter to start the interactive session..."
read

gpg --edit-key $KEYID
```

---

**Post-Transfer Verification (YubiKey #2):**

```bash
echo ""
echo ">>> Verifying YubiKey #2 key transfer..."

# Kill and restart agent to refresh card state
gpgconf --kill gpg-agent
sleep 2

# Check if keys are now on the card
if ! gpg --card-status | grep -q "Signature key"; then
    echo "⚠️  WARNING: Signature key not detected on YubiKey #2"
    echo "    Run 'gpg --card-status' manually to inspect"
else
    echo "✅ Signature key detected on YubiKey #2"
fi

if ! gpg --card-status | grep -q "Encryption key"; then
    echo "⚠️  WARNING: Encryption key not detected on YubiKey #2"
else
    echo "✅ Encryption key detected on YubiKey #2"
fi

if ! gpg --card-status | grep -q "Authentication key"; then
    echo "⚠️  WARNING: Authentication key not detected on YubiKey #2"
else
    echo "✅ Authentication key detected on YubiKey #2"
fi

# Verify local subkeys are now stubs
echo ""
echo ">>> Local keyring status (subkeys should now show as stubs):"
gpg --list-secret-keys "$KEYID"
echo ""
echo "✅ YubiKey #2 loading complete"
echo "   Both YubiKeys now contain identical subkeys"
echo ""
```

## **Phase 8: Final Verification & Cleanup**

**Goal:** Ensure keys work and wipe RAM.

**Step 8.1: Test YubiKey**

```bash
# Verify YubiKey is still detected and operational
if ! gpg --card-status | grep -q "OpenPGP card"; then
    echo "❌ CRITICAL: YubiKey not detected for final testing"
else
    echo "✅ YubiKey detected for final testing"
fi

# Test signature creation
echo "Testing Signature..." | gpg --sign --armor > test_signature.asc
# Should ask for User PIN and Touch

# Verify the signature
if gpg --verify test_signature.asc 2>&1 | grep -q "Good signature"; then
    echo "✅ Signature verification passed"
else
    echo "⚠️  Signature verification check: Review output above"
fi

rm test_signature.asc

echo "✅ YubiKey signature test completed successfully"
```

**Step 8.2: Secure Wipe**

```bash
# Kill gpg-agent first to ensure clean shutdown
gpgconf --kill gpg-agent

# Unmount backups with error handling
echo ">>> Unmounting USB Backup..."
umount "$USB_BACKUP_PATH" 2>&1 || echo "⚠️  USB unmount failed (may already be unmounted)"

echo ">>> Unmounting SSD Backup..."
umount "$SSD_BACKUP_PATH" 2>&1 || echo "⚠️  SSD unmount failed (may already be unmounted)"

# Securely wipe and remove local temporary files
find $GNUPGHOME -type f -exec shred -u {} \;
find $GNUPGHOME.bak -type f -exec shred -u {} \;

# Remove the temporary directories to ensure /tmp is clean
rm -rf $GNUPGHOME $GNUPGHOME.bak
echo ">>> SETUP COMPLETE. POWER OFF."
```

## **Appendix A: Emergency Operations**

Use this section if you are recovering from disaster (Total Loss of Keys) or Compromise (Lost YubiKey).

### **A.1: Restore from Digital Backup (USB/SSD)**
*Use this if your YubiKeys are lost but you have your USB/SSD backup.*

1. Boot into the clean environment (Phase 0).
2. Mount your USB/SSD backup.
3. **Import the Master Key:**
   ```bash
   gpg --import "$USB_BACKUP_PATH/$BACKUP_DIR_NAME/master_secret.gpg"
   ```
4. **Set Trust Level:** Like Phase 4, set the key trust level to Ultimate.
   ```bash
   gpg --edit-key $KEYID
   # Type 'trust' -> Select '5' (Ultimate) -> Confirm 'y' -> Type 'quit'
   ```
6. **Verify Import:** `gpg --list-secret-keys`
7. **Next Steps:**
   - If replacing YubiKeys: Go to **Phase 5** (Generate Subkeys) or **Phase 7** (Load to Hardware).

### **A.2: Restore from Paper Backup**
*Use this ONLY if digital backups (USB/SSD) are destroyed or corrupted.*

**Step 1: Online Preparation (Tools & Public Key)**

* **Action:** Ensure you are still connected to the internet.
* **Install Tools:** Ensure `paperkey` and `zbar-tools` are installed (see Phase 0.2).
* **CRITICAL: Download Public Key:** While connected to the internet, download your current public key (`public_key_bundle.asc`) from your WKD, website, or keyserver. Without digital backups, this online source is likely your only copy of the public data.
* **Note:** You CANNOT restore from paper without the public key.

**Step 2: Establish Air-Gap**

* **Action:** Physically disconnect the Ethernet cable or disable the Wi-Fi adapter.
* **Verify:** Run the following command to ensure isolation:

```bash
ping -c 2 8.8.8.8
# Output must be "Network is unreachable" or 100% packet loss.
```

* **Warning:** Do not reconnect to the internet for the remainder of this restoration session.

**Step 3: Secret Reconstruction**

* **Scan Paper Key:**
   ```bash
   zbarcam --raw > scanned_paperkey.txt
   # (Or type the text manually if camera fails)
   ```
* **Reconstruct Secret Key:**
   ```bash
   paperkey --pubring public_key_bundle.asc --secrets scanned_paperkey.txt --output restored_master.gpg
   ```
* **Import:** `gpg --import restored_master.gpg`

### **A.3: Revoking a Compromised Subkey**
*Use this if a YubiKey is lost/stolen. This invalidates the old specific key while keeping your Master Identity safe.*

1. **Import Master Key:** (See A.1 or A.2).
2. **Edit Keyring:**
   ```bash
   gpg --edit-key $KEYID
   ```
3. **Select Subkey:**
   - Type `key 1` (or 2, 3) to select the compromised subkey.
   - Look for the `*` marker next to the selected key (e.g., `ssb*`).
4. **Revoke:**
   - Type `revkey`.
   - **Reason:** Select "Key has been compromised".
   - **Description:** e.g., "YubiKey #1 Lost".
   - Confirm with `y`.
5. **Save:** Type `save`.
6. **Publish Revocation (CRITICAL):**
   - You must update your public key online so others know to stop using that subkey.
   ```bash
   gpg --export $KEYID --armor > new_public_bundle.asc
   ```
   - **Upload:** Overwrite the existing file on your WKD/GCS.
   - *Note: Your WKD Filename (Hash) DOES NOT CHANGE. It is based on your email, not the key content.*
7. **Next:** Go to **Phase 5** to generate a fresh subkey to replace the one you just revoked.

### **A.4: Recovering from Session Interruption**
*Use this if your terminal session crashes or is accidentally closed before completing the protocol.*

If your terminal session crashes or is accidentally closed before completing the protocol, you can recover your environment variables:

1. Reopen a terminal
2. Run:
   ```bash
   source /tmp/tmp.gnupg_dpa_tmp/session_vars.sh
   ```
3. Verify variables are restored:
   ```bash
   echo "GNUPGHOME: $GNUPGHOME"
   echo "Email: $MY_EMAIL"
   echo "USB Path: $USB_BACKUP_PATH"
   echo "SSD Path: $SSD_BACKUP_PATH"
   ```
4. If `KEYID` is empty but you already created the master key, recapture it:
   ```bash
   export KEYID=$(gpg --list-keys --with-colons "$MY_EMAIL" | awk -F: '/^fpr:/ { print $10; exit }')
   echo "Key ID: $KEYID"
   ```
5. Resume the protocol from where you left off.

**Note:** The session recovery file is created automatically in Phase 0.1 and contains all your environment variables except `KEYID` (which is captured later in Phase 2.2).

