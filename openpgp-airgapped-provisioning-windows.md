# Air-Gapped OpenPGP Root Identity & Hardware Provisioning Protocol (Windows)

Version: 1.0 (Windows 11 Native with Gpg4win)
Target System: Windows 11 with Gpg4win, YubiKey Manager, and Python 3

> **Note:** This guide is a Windows-native adaptation of the [Linux version](openpgp-airgapped-provisioning.md). Most cryptographic operations use Gpg4win (PowerShell), with optional WSL2 steps for paperkey-based QR backups.

## **Prerequisites**

### Required Software (Download Before Air-Gapping)
| Tool | Purpose | Download |
|------|---------|----------|
| **Gpg4win** | GPG operations (includes Kleopatra GUI) | [gpg4win.org](https://gpg4win.org) |
| **YubiKey Manager** | YubiKey configuration | [yubico.com](https://www.yubico.com/support/download/yubikey-manager/) |
| **Python 3** | QR code generation/scanning | [python.org](https://www.python.org/downloads/) |
| **EFF Large Wordlist** | Passphrase generation | [eff.org](https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt) |
| **(Optional) WSL2 + Debian** | For paperkey-based minimal backups | `wsl --install -d Debian` |

### Required Hardware
* 2x **YubiKey 5C NFC** (or other OpenPGP-compatible model)
* 1x **USB Flash Drive** (Primary backup)
* 1x **SSD/HDD** (Secondary backup)
* 1x **USB Printer** (For paper backups)

### Python Packages (Install Before Air-Gapping)
```powershell
pip install qrcode pillow pyzbar
```

---

## **Index**

1. [Phase 0: Environment Preparation](#phase-0-environment-preparation)
2. [Phase 1: Secure Session Setup](#phase-1-secure-session-setup)
3. [Phase 2: Master Key Generation](#phase-2-master-key-generation)
4. [Phase 3: Physical & Digital Backups](#phase-3-physical--digital-backups)
5. [Phase 4: The "Clean Slate" Restoration Test](#phase-4-the-clean-slate-restoration-test)
6. [Phase 5: Subkey Generation](#phase-5-subkey-generation)
7. [Phase 5.5: Finalize Master Key Backup](#phase-55-finalize-master-key-backup-with-subkeys)
8. [Phase 6: YubiKey Configuration](#phase-6-yubikey-configuration-pins--touch)
9. [Phase 7: Loading Keys to Hardware](#phase-7-loading-keys-to-hardware)
10. [Phase 8: Final Verification & Cleanup](#phase-8-final-verification--cleanup)
11. [Appendix A: Emergency Operations](#appendix-a-emergency-operations)
12. [Appendix B: Optional Paperkey Workflow (WSL2)](#appendix-b-optional-paperkey-workflow-wsl2)

---

## **Phase 0: Environment Preparation**

**Goal:** Install tools, define variables, ready the printer, verify YubiKey detection.

### **Step 0.1: Define Variables**

Open PowerShell as Administrator. Set session variables:

```powershell
# --- USER IDENTITY ---
$MY_NAME = "Your Full Name"
$MY_EMAIL = "your.email@example.com"
$MY_EMAIL_2 = "secondary@example.com"  # Optional, leave empty if not needed

# --- STORAGE PATHS (adjust drive letters as needed) ---
$USB_BACKUP_PATH = "E:\PGP_Master_Backup"
$SSD_BACKUP_PATH = "F:\PGP_Master_Backup"

# --- WORKING DIRECTORY (temporary, will be deleted) ---
$env:GNUPGHOME = "$env:TEMP\gnupg_airgap"
New-Item -ItemType Directory -Path $env:GNUPGHOME -Force | Out-Null

# --- PATHS ---
$WORDLIST_PATH = "$env:USERPROFILE\Downloads\eff_large_wordlist.txt"
$DESKTOP = "$env:USERPROFILE\Desktop"

# Save variables for session recovery
@"
`$MY_NAME = "$MY_NAME"
`$MY_EMAIL = "$MY_EMAIL"
`$MY_EMAIL_2 = "$MY_EMAIL_2"
`$USB_BACKUP_PATH = "$USB_BACKUP_PATH"
`$SSD_BACKUP_PATH = "$SSD_BACKUP_PATH"
`$env:GNUPGHOME = "$env:GNUPGHOME"
"@ | Out-File "$env:GNUPGHOME\session_vars.ps1"

Write-Host "✅ Session variables saved to: $env:GNUPGHOME\session_vars.ps1" -ForegroundColor Green
```

### **Step 0.2: Verify Tools**

```powershell
Write-Host ">>> Verifying installed tools..." -ForegroundColor Cyan

# Check GPG
if (Get-Command gpg -ErrorAction SilentlyContinue) {
    Write-Host "  ✅ gpg: $(gpg --version | Select-Object -First 1)" -ForegroundColor Green
} else {
    Write-Host "  ❌ gpg not found - Install Gpg4win" -ForegroundColor Red
}

# Check YubiKey Manager
if (Get-Command ykman -ErrorAction SilentlyContinue) {
    Write-Host "  ✅ ykman: $(ykman --version)" -ForegroundColor Green
} else {
    Write-Host "  ❌ ykman not found - Install YubiKey Manager" -ForegroundColor Red
}

# Check Python
if (Get-Command python -ErrorAction SilentlyContinue) {
    Write-Host "  ✅ python: $(python --version)" -ForegroundColor Green
    # Check Python packages
    $packages = python -c "import qrcode, PIL, pyzbar; print('qrcode, pillow, pyzbar')" 2>$null
    if ($packages) {
        Write-Host "  ✅ Python packages: $packages" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Python packages missing - Run: pip install qrcode pillow pyzbar" -ForegroundColor Red
    }
} else {
    Write-Host "  ❌ python not found" -ForegroundColor Red
}

# Check wordlist
if (Test-Path $WORDLIST_PATH) {
    Write-Host "  ✅ Wordlist found: $WORDLIST_PATH" -ForegroundColor Green
} else {
    Write-Host "  ❌ Wordlist not found - Download from eff.org" -ForegroundColor Red
}
```

### **Step 0.3: Printer Setup**

1. Connect USB printer
2. Open **Settings → Bluetooth & devices → Printers & scanners**
3. Add printer and set as default
4. Print a test page to confirm functionality

### **Step 0.4: YubiKey Diagnostic**

```powershell
Write-Host ">>> YubiKey Detection Test..." -ForegroundColor Cyan

# Check with ykman
$ykinfo = ykman list 2>$null
if ($ykinfo) {
    Write-Host "  ✅ YubiKey detected: $ykinfo" -ForegroundColor Green
} else {
    Write-Host "  ❌ No YubiKey detected - Insert YubiKey and retry" -ForegroundColor Red
}

# Check OpenPGP applet
$cardstatus = gpg --card-status 2>$null
if ($cardstatus -match "OpenPGP") {
    Write-Host "  ✅ OpenPGP applet accessible" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  OpenPGP applet not responding - May need to reset YubiKey" -ForegroundColor Yellow
}
```

### **Step 0.5: Establish Air-Gap (CRITICAL)**

**Disconnect from all networks before proceeding.**

```powershell
Write-Host ">>> Disabling network adapters..." -ForegroundColor Cyan

# Disable all network adapters
Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Disable-NetAdapter -Confirm:$false

# Verify air-gap
$connected = Test-NetConnection 8.8.8.8 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
if ($connected.PingSucceeded) {
    Write-Host "❌ CRITICAL: Network still reachable! Manually disable Wi-Fi/Ethernet." -ForegroundColor Red
} else {
    Write-Host "✅ Air-gap verified: Network unreachable" -ForegroundColor Green
}
```

---

## **Phase 1: Secure Session Setup**

**Goal:** Configure GPG and generate master passphrase.

### **Step 1.1: Configure GPG**

```powershell
# Create gpg.conf with secure defaults
@"
personal-cipher-preferences AES256 AES192 AES
personal-digest-preferences SHA512 SHA384 SHA256
personal-compress-preferences ZLIB BZIP2 ZIP Uncompressed
default-preference-list SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed
cert-digest-algo SHA512
s2k-digest-algo SHA512
s2k-cipher-algo AES256
s2k-count 65011712
"@ | Out-File -Encoding ASCII "$env:GNUPGHOME\gpg.conf"

@"
default-cache-ttl 7200
max-cache-ttl 7200
"@ | Out-File -Encoding ASCII "$env:GNUPGHOME\gpg-agent.conf"

# Reload gpg-agent
gpgconf --kill gpg-agent
gpg-connect-agent reloadagent /bye 2>$null

Write-Host "✅ GPG configured with secure defaults" -ForegroundColor Green
```

### **Step 1.2: Generate Master Passphrase**

```powershell
Write-Host "`n================================================" -ForegroundColor Yellow
Write-Host "WRITE THIS DOWN (Your Master Key Passphrase):" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow

# Generate 6 random words from EFF wordlist
$words = Get-Content $WORDLIST_PATH | ForEach-Object { ($_ -split "`t")[1] }
$passphrase = (Get-Random -InputObject $words -Count 6) -join " "
Write-Host $passphrase -ForegroundColor White
Write-Host "================================================`n" -ForegroundColor Yellow

Write-Host "Write these 6 words on paper. Re-type them to confirm legibility." -ForegroundColor Cyan
```

> **IMPORTANT:** Write the passphrase on your permanent paper storage. Verify you can read your handwriting before proceeding.

---

## **Phase 2: Master Key Generation**

**Goal:** Create the Certify-only Ed25519 master key.

### **Step 2.1: Generate Key**

```powershell
gpg --expert --full-gen-key
```

**Interactive selections:**
1. Key type: **(11) ECC (set your own capabilities)**
2. Toggle: `S` (disable Sign), `E` (disable Encrypt) → Only **Certify** remains → `Q`
3. Elliptic Curve: **(1) Curve 25519**
4. Validity: **0** (no expiry)
5. Confirm: **y**
6. Real name: Enter `$MY_NAME` value
7. Email: Enter `$MY_EMAIL` value
8. Comment: Leave blank or add identifier
9. Passphrase: Enter the 6-word passphrase from Phase 1

> **Note:** When selecting "Curve 25519", GPG uses **Ed25519** for signing/authentication and **cv25519 (X25519)** for encryption keys automatically.

### **Step 2.2: Capture Key ID**

```powershell
$KEYID = (gpg --list-keys --with-colons | Select-String "^fpr:" | Select-Object -First 1).ToString().Split(":")[9]
Write-Host "Key ID Generated: $KEYID" -ForegroundColor Green

# Verify
gpg --list-secret-keys $KEYID
```

### **Step 2.3: Add Secondary Identity (Optional)**

```powershell
if ($MY_EMAIL_2) {
    Write-Host ">>> Adding secondary identity: $MY_EMAIL_2" -ForegroundColor Cyan
    gpg --quick-add-uid $KEYID "$MY_NAME <$MY_EMAIL_2>"
    
    # Verify
    gpg --list-keys $KEYID | Select-String $MY_EMAIL_2
    Write-Host "✅ Secondary identity added" -ForegroundColor Green
}

# Set trust to ultimate
Write-Host ">>> Setting trust level to Ultimate..." -ForegroundColor Cyan
Write-Host "At the gpg> prompt: trust → 5 → y → quit" -ForegroundColor Yellow
gpg --edit-key $KEYID
```

---

## **Phase 3: Physical & Digital Backups**

**Goal:** Create triple-redundancy backup (USB, SSD, Paper).

### **Step 3.1: Generate Backup Artifacts**

```powershell
Set-Location $env:GNUPGHOME

# Export secret key
gpg --export-secret-keys --armor $KEYID | Out-File -Encoding ASCII master_secret.asc

# Generate revocation certificate
Write-Host ">>> Generating Revocation Certificate..." -ForegroundColor Cyan
Write-Host "    Reason: 0 (No reason specified)" -ForegroundColor Yellow
Write-Host "    Description: 'Backup Revocation' or leave blank" -ForegroundColor Yellow
gpg --gen-revoke $KEYID | Out-File -Encoding ASCII revocation_cert.asc

# Generate checksum
$hash = (Get-FileHash -Algorithm SHA256 master_secret.asc).Hash
$hash | Out-File -Encoding ASCII checksum.txt

# Generate QR codes for small files
python -c "import qrcode; qrcode.make(open('checksum.txt').read().strip()).save('checksum_qr.png')"
python -c "import qrcode; qrcode.make(open('revocation_cert.asc').read()).save('revocation_qr.png')"

Write-Host "✅ Backup artifacts generated:" -ForegroundColor Green
Get-ChildItem master_secret.asc, revocation_cert.asc, checksum.txt, checksum_qr.png, revocation_qr.png | Format-Table Name, Length
```

### **Step 3.2: Print Paper Backups**

Print the following files (right-click → Print, or open and print):

1. **checksum_qr.png** - QR code for verifying digital backup integrity
2. **revocation_qr.png** - QR code for emergency revocation
3. **checksum.txt** - Human-readable checksum
4. **revocation_cert.asc** - Human-readable revocation certificate
5. **master_secret.asc** - Full ASCII-armored key (last-resort recovery)

```powershell
# Copy to Desktop for easy printing
Copy-Item checksum_qr.png, revocation_qr.png, checksum.txt, revocation_cert.asc, master_secret.asc $DESKTOP

Write-Host "✅ Files copied to Desktop for printing" -ForegroundColor Green
Write-Host "   Print each file before proceeding." -ForegroundColor Yellow
```

### **Step 3.3: QR Verification**

Verify printed QR codes are scannable:

```powershell
Write-Host ">>> Take a photo of each printed QR code and save to Desktop" -ForegroundColor Cyan
Write-Host "    Then run verification below..." -ForegroundColor Yellow

# Verify checksum QR
$scanned = python -c "from pyzbar.pyzbar import decode; from PIL import Image; print(decode(Image.open('$DESKTOP\checksum_photo.jpg'))[0].data.decode())" 2>$null
$expected = Get-Content checksum.txt
if ($scanned.Trim() -eq $expected.Trim()) {
    Write-Host "✅ Checksum QR verified" -ForegroundColor Green
} else {
    Write-Host "❌ Checksum QR mismatch - Reprint and retry" -ForegroundColor Red
    Write-Host "Expected: $expected" -ForegroundColor Yellow
    Write-Host "Scanned:  $scanned" -ForegroundColor Yellow
}
```

### **Step 3.4: Save to USB & SSD**

```powershell
# Create backup directories
New-Item -ItemType Directory -Path $USB_BACKUP_PATH -Force | Out-Null
New-Item -ItemType Directory -Path $SSD_BACKUP_PATH -Force | Out-Null

# Copy backup files
$backupFiles = @("master_secret.asc", "revocation_cert.asc", "checksum.txt", "gpg.conf", "gpg-agent.conf")
foreach ($file in $backupFiles) {
    Copy-Item $file $USB_BACKUP_PATH
    Copy-Item $file $SSD_BACKUP_PATH
}

Write-Host "✅ Backups saved to USB and SSD:" -ForegroundColor Green
Get-ChildItem $USB_BACKUP_PATH | Format-Table Name, Length
```

---

## **Phase 4: The "Clean Slate" Restoration Test**

**Goal:** Verify backup by wiping and restoring.

### **Step 4.1: Wipe Local Keys**

```powershell
Write-Host ">>> Wiping local GPG keyring..." -ForegroundColor Yellow
Remove-Item "$env:GNUPGHOME\private-keys-v1.d\*" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:GNUPGHOME\pubring.kbx" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:GNUPGHOME\trustdb.gpg" -Force -ErrorAction SilentlyContinue
Write-Host "Local keys wiped." -ForegroundColor Green
```

### **Step 4.2: Restore from USB**

```powershell
gpg --import "$USB_BACKUP_PATH\master_secret.asc"

Write-Host ">>> Set trust level: trust → 5 → y → quit" -ForegroundColor Yellow
gpg --edit-key $KEYID

# Verify restoration
$restored = gpg --list-secret-keys $KEYID 2>$null
if ($restored) {
    Write-Host "✅ RESTORE SUCCESS: Master key operational" -ForegroundColor Green
} else {
    Write-Host "❌ RESTORE FAILED: Check backup file" -ForegroundColor Red
}
```

---

## **Phase 5: Subkey Generation**

**Goal:** Create Sign, Encrypt, and Authenticate subkeys.

### **Step 5.1: Create Subkeys**

```powershell
gpg --expert --edit-key $KEYID
```

At the `gpg>` prompt, create three subkeys:

**1. Signing Subkey:**
- `addkey` → **(10) ECC (sign only)** → Curve 25519 → Expiry **1y** → Confirm

**2. Encryption Subkey:**
- `addkey` → **(12) ECC (encrypt only)** → Curve 25519 → Expiry **1y** → Confirm

**3. Authentication Subkey:**
- `addkey` → **(11) ECC (set your own capabilities)** → Toggle `S` off, `A` on → `Q` → Curve 25519 → Expiry **1y** → Confirm

- `save`

### **Step 5.2: Export Public Key**

```powershell
Set-Location $env:GNUPGHOME

gpg --export --armor $KEYID | Out-File -Encoding ASCII public_key.asc

# Save to backup media
Copy-Item public_key.asc $USB_BACKUP_PATH
Copy-Item public_key.asc $SSD_BACKUP_PATH

Write-Host "✅ Public key exported and backed up" -ForegroundColor Green
```

---

## **Phase 5.5: Finalize Master Key Backup with Subkeys**

**Goal:** Update backups to include subkeys.

```powershell
Set-Location $env:GNUPGHOME

# Re-export with subkeys
gpg --export-secret-keys --armor $KEYID | Out-File -Encoding ASCII master_secret.asc

# Update checksum
$hash = (Get-FileHash -Algorithm SHA256 master_secret.asc).Hash
$hash | Out-File -Encoding ASCII checksum.txt

# Regenerate QR
python -c "import qrcode; qrcode.make(open('checksum.txt').read().strip()).save('checksum_qr.png')"

# Update backups
Copy-Item master_secret.asc, checksum.txt $USB_BACKUP_PATH -Force
Copy-Item master_secret.asc, checksum.txt $SSD_BACKUP_PATH -Force

Write-Host "✅ Backups updated with subkeys" -ForegroundColor Green
Write-Host ">>> Reprint checksum_qr.png and checksum.txt" -ForegroundColor Yellow
Copy-Item checksum_qr.png, checksum.txt $DESKTOP -Force
```

---

## **Phase 6: YubiKey Configuration (PINs & Touch)**

**Goal:** Secure YubiKeys with PINs and touch policies.

### **Step 6.1: Set PINs**

```powershell
Write-Host ">>> Changing YubiKey PINs..." -ForegroundColor Cyan
Write-Host "    User PIN: 6-8 digits (memorize)" -ForegroundColor Yellow
Write-Host "    Admin PIN: 8+ characters (store securely)" -ForegroundColor Yellow

gpg --change-pin
```

**Menu options:**
1. Change PIN (User PIN)
2. Unblock PIN
3. Change Admin PIN
4. Set Reset Code

### **Step 6.2: Set CCID Mode**

```powershell
Write-Host ">>> Setting YubiKey to CCID-only mode..." -ForegroundColor Cyan
ykman config mode ccid

Write-Host "✅ CCID mode set" -ForegroundColor Green
Write-Host "   To re-enable FIDO2 later: ykman config mode OTP+FIDO+CCID" -ForegroundColor Yellow
```

### **Step 6.3: Set Touch Policy**

```powershell
Write-Host ">>> Setting touch policy (requires physical touch for operations)..." -ForegroundColor Cyan

ykman openpgp keys set-touch sig on
ykman openpgp keys set-touch aut on
ykman openpgp keys set-touch enc on

Write-Host "✅ Touch policy enabled for all key slots" -ForegroundColor Green
```

---

## **Phase 7: Loading Keys to Hardware**

**Goal:** Move subkeys to YubiKeys (removes them from disk).

### **Step 7.1: Create Snapshot**

```powershell
Write-Host ">>> Creating backup snapshot before hardware transfer..." -ForegroundColor Cyan
$snapshotPath = "$env:GNUPGHOME.bak"
Copy-Item -Recurse $env:GNUPGHOME $snapshotPath -Force
Write-Host "✅ Snapshot created: $snapshotPath" -ForegroundColor Green
```

### **Step 7.2: Load YubiKey #1 (Primary)**

```powershell
Write-Host @"

⚠️  CRITICAL: POINT OF NO RETURN
- Subkeys will MOVE to YubiKey (deleted from disk)
- Recovery only possible from snapshot or USB backup
- Confirm snapshot exists before proceeding

"@ -ForegroundColor Yellow

$confirm = Read-Host "Type 'YES' to proceed with keytocard"
if ($confirm -ne "YES") {
    Write-Host "Operation cancelled." -ForegroundColor Red
    return
}

Write-Host @"

At the gpg> prompt:
- key 1 → keytocard → 1 (Signature) → Admin PIN → key 1 (deselect)
- key 2 → keytocard → 2 (Encryption) → Admin PIN → key 2 (deselect)
- key 3 → keytocard → 3 (Authentication) → Admin PIN
- save

"@ -ForegroundColor Yellow

gpg --edit-key $KEYID

# Verify
gpgconf --kill gpg-agent
Start-Sleep 2

$cardStatus = gpg --card-status
if ($cardStatus -match "Signature key") { Write-Host "✅ Signature key on card" -ForegroundColor Green }
if ($cardStatus -match "Encryption key") { Write-Host "✅ Encryption key on card" -ForegroundColor Green }
if ($cardStatus -match "Authentication key") { Write-Host "✅ Authentication key on card" -ForegroundColor Green }

Write-Host "`n>>> Remove YubiKey #1 and press Enter..." -ForegroundColor Yellow
Read-Host
```

### **Step 7.3: Load YubiKey #2 (Backup)**

```powershell
Write-Host ">>> Restoring keys for YubiKey #2..." -ForegroundColor Cyan

gpgconf --kill gpg-agent
Remove-Item -Recurse $env:GNUPGHOME -Force
Copy-Item -Recurse $snapshotPath $env:GNUPGHOME -Force

Write-Host ">>> Insert YubiKey #2 and press Enter..." -ForegroundColor Yellow
Read-Host

# Verify different YubiKey
$ykSerial = ykman list
Write-Host "Detected: $ykSerial" -ForegroundColor Cyan

$confirm = Read-Host "Type 'YES' to proceed with keytocard on YubiKey #2"
if ($confirm -ne "YES") {
    Write-Host "Operation cancelled." -ForegroundColor Red
    return
}

gpg --edit-key $KEYID

# Verify
gpgconf --kill gpg-agent
Start-Sleep 2

$cardStatus = gpg --card-status
if ($cardStatus -match "Signature key") { Write-Host "✅ Signature key on card" -ForegroundColor Green }
if ($cardStatus -match "Encryption key") { Write-Host "✅ Encryption key on card" -ForegroundColor Green }
if ($cardStatus -match "Authentication key") { Write-Host "✅ Authentication key on card" -ForegroundColor Green }
```

---

## **Phase 8: Final Verification & Cleanup**

**Goal:** Test YubiKey operation and securely wipe working files.

### **Step 8.1: Test Signature**

```powershell
Write-Host ">>> Testing signature with YubiKey..." -ForegroundColor Cyan
Write-Host "    Touch YubiKey when prompted" -ForegroundColor Yellow

"Test message" | gpg --sign --armor | Out-File test_sig.asc
$verify = gpg --verify test_sig.asc 2>&1

if ($verify -match "Good signature") {
    Write-Host "✅ Signature test PASSED" -ForegroundColor Green
} else {
    Write-Host "⚠️  Signature verification - check output above" -ForegroundColor Yellow
}

Remove-Item test_sig.asc -Force
```

### **Step 8.2: Secure Cleanup**

```powershell
Write-Host ">>> Secure cleanup..." -ForegroundColor Cyan

gpgconf --kill gpg-agent

# Safely eject backup drives
Write-Host ">>> Safely remove USB and SSD drives via Windows" -ForegroundColor Yellow

# Delete working directories
Remove-Item -Recurse "$env:GNUPGHOME" -Force
Remove-Item -Recurse "$snapshotPath" -Force

# Delete temporary files from Desktop
Remove-Item "$DESKTOP\checksum*", "$DESKTOP\revocation*", "$DESKTOP\master_secret.asc" -Force -ErrorAction SilentlyContinue

# Wipe free space (optional - takes time)
# cipher /w:$env:TEMP

Write-Host @"

✅ SETUP COMPLETE

Your keys are now:
- Master key: Backed up to USB, SSD, and paper
- Subkeys: Loaded on both YubiKeys
- Working directory: Securely deleted

POWER OFF the computer now.

"@ -ForegroundColor Green
```

---

## **Appendix A: Emergency Operations**

### **A.1: Restore from Digital Backup**

```powershell
# Set GNUPGHOME
$env:GNUPGHOME = "$env:TEMP\gnupg_restore"
New-Item -ItemType Directory -Path $env:GNUPGHOME -Force

# Import from USB
gpg --import "E:\PGP_Master_Backup\master_secret.asc"

# Set trust
gpg --edit-key <KEYID>
# trust → 5 → y → quit

# Verify
gpg --list-secret-keys
```

### **A.2: Revoke Compromised Key**

```powershell
# Import master key (see A.1)

# Apply revocation certificate
gpg --import revocation_cert.asc

# Export revoked public key
gpg --export --armor <KEYID> > revoked_public.asc

# Publish to keyservers/WKD
```

### **A.3: Recover Session**

If PowerShell session is interrupted:

```powershell
# Restore session variables
. "$env:TEMP\gnupg_airgap\session_vars.ps1"

# Recover KEYID
$KEYID = (gpg --list-keys --with-colons | Select-String "^fpr:" | Select-Object -First 1).ToString().Split(":")[9]

Write-Host "Recovered KEYID: $KEYID"
```

---

## **Appendix B: Optional Paperkey Workflow (WSL2)**

> **When to use:** If you want minimal paper backups with single-QR secret key recovery. Requires WSL2 with Debian/Ubuntu.

### **B.1: Install WSL2 and Paperkey (Before Air-Gapping)**

```powershell
# Windows: Install WSL2
wsl --install -d Debian

# WSL2: Install paperkey
wsl -d Debian -e bash -c "sudo apt update && sudo apt install -y paperkey qrencode"
```

### **B.2: Generate Paperkey Backup**

```powershell
# Export key to WSL-accessible path
$wslPath = "/mnt/c/Users/$env:USERNAME/Desktop"
gpg --export-secret-keys $KEYID | Out-File -Encoding Byte "$DESKTOP\master_secret.gpg"

# Generate paperkey output via WSL
wsl -d Debian -e bash -c "paperkey --secret-key $wslPath/master_secret.gpg --output $wslPath/master_paperkey.txt"

# Generate QR from paperkey output
wsl -d Debian -e bash -c "cat $wslPath/master_paperkey.txt | qrencode -l M -o $wslPath/master_paperkey_qr.png"

Write-Host "✅ Paperkey backup generated:" -ForegroundColor Green
Get-ChildItem "$DESKTOP\master_paperkey*"
```

### **B.3: Restore from Paperkey**

```powershell
# Take photo of printed paperkey QR, save as paperkey_scan.jpg

# Decode QR
wsl -d Debian -e bash -c "zbarimg --raw $wslPath/paperkey_scan.jpg > $wslPath/scanned_paperkey.txt"

# Reconstruct secret key (requires public key)
wsl -d Debian -e bash -c "paperkey --pubring $wslPath/public_key.asc --secrets $wslPath/scanned_paperkey.txt --output $wslPath/restored_secret.gpg"

# Import restored key
gpg --import "$DESKTOP\restored_secret.gpg"
```

---

## **Quick Reference: Windows Commands**

| Operation | Command |
|-----------|---------|
| List keys | `gpg --list-keys` |
| List secret keys | `gpg --list-secret-keys` |
| Card status | `gpg --card-status` |
| Kill gpg-agent | `gpgconf --kill gpg-agent` |
| YubiKey list | `ykman list` |
| YubiKey info | `ykman openpgp info` |
| File hash | `Get-FileHash -Algorithm SHA256 file.txt` |
| Disable network | `Get-NetAdapter \| Disable-NetAdapter` |
| Enable network | `Get-NetAdapter \| Enable-NetAdapter` |

---

## **License**

This guide is provided under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). 
Adapted from the Linux version for Windows environments.
