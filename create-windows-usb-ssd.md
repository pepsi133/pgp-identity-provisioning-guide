# Running Windows 11 from External USB SSD

This guide covers creating a portable Windows 11 installation on an external USB SSD for air-gapped cryptographic operations. Examples are based on **ThinkPad T480**, but the process applies to most modern laptops.

## **Why External USB SSD?**

| Advantage | Description |
|-----------|-------------|
| **Air-gap isolation** | Completely separate from your daily OS |
| **Portable** | Use on any compatible machine |
| **No internal drive modification** | Keep your main system untouched |
| **Better performance** | USB 3.0+ SSD is fast enough for this workflow |
| **Reusable** | Pre-configure once, use for future key ceremonies |

---

## **Hardware Requirements**

### Required
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **External SSD** | 64GB USB 3.0 | 128GB+ NVMe in USB enclosure |
| **USB Port** | USB 3.0 (blue port) | USB 3.1/Thunderbolt |
| **RAM** | 4GB | 8GB+ |
| **UEFI Firmware** | Required | Required |

### ThinkPad T480 Specifics
- **USB-C ports**: Both support bootable USB (left side preferred)
- **USB-A port**: Works, but slower than USB-C
- **Thunderbolt 3**: Full speed NVMe enclosure support

### Recommended SSD Options
| Type | Example | Speed | Notes |
|------|---------|-------|-------|
| **Budget** | Samsung T7 500GB | ~500 MB/s | USB 3.2, reliable |
| **Performance** | NVMe + enclosure | ~1000 MB/s | Best experience |
| **Basic** | SanDisk Extreme Portable | ~400 MB/s | Compact |

> **Avoid:** USB flash drives (too slow), spinning HDDs (fragile)

---

## **Creating Windows 11 on USB SSD**

### Method 1: Rufus (Recommended)

**Requirements:**
- Windows 11 ISO ([microsoft.com/software-download/windows11](https://www.microsoft.com/software-download/windows11))
- Rufus 4.0+ ([rufus.ie](https://rufus.ie))
- External SSD connected

**Steps:**

1. **Download Windows 11 ISO** from Microsoft

2. **Run Rufus** as Administrator

3. **Configure Rufus:**
   ```
   Device:              [Your external SSD]
   Boot selection:      [Windows 11 ISO]
   Image option:        "Windows To Go"  ← IMPORTANT
   Partition scheme:    GPT
   Target system:       UEFI (non CSM)
   File system:         NTFS
   ```

4. **Bypass Windows 11 Checks** (if prompted):
   - ✅ Remove requirement for 4GB+ RAM, Secure Boot and TPM 2.0
   - ✅ Remove requirement for an online Microsoft account
   - ✅ Disable data collection

5. **Click START** and wait (~20-45 minutes)

6. **First Boot Configuration:**
   - Boot from USB SSD (see BIOS section below)
   - Complete Windows Out-of-Box Experience (OOBE)
   - Create local account (no Microsoft account needed)

### Method 2: WinToUSB (Alternative)

If Rufus doesn't show "Windows To Go" option:

1. Download **WinToUSB** ([easyuefi.com](https://www.easyuefi.com/wintousb/))
2. Select Windows 11 ISO
3. Choose external SSD as destination
4. Select "Windows To Go" mode
5. Choose GPT + UEFI
6. Complete installation

### Method 3: Manual Installation

For advanced users who want a clean install:

1. Boot from Windows 11 installation USB
2. At disk selection, choose external SSD
3. Install Windows normally
4. Boot from internal drive, then configure external for portable use

---

## **BIOS/UEFI Configuration**

### Accessing BIOS

| Manufacturer | Key | Notes |
|--------------|-----|-------|
| **Lenovo ThinkPad** | **F1** or **Enter** | Press at Lenovo logo |
| Dell | F2 | At Dell logo |
| HP | F10 | At HP logo |
| ASUS | F2 or Del | At ASUS logo |
| Acer | F2 | At Acer logo |

### ThinkPad T480 BIOS Settings

**Enter BIOS:** Press **F1** at Lenovo logo (or **Enter** → F1)

#### 1. Security Settings
```
Security → Secure Boot
  └── Secure Boot: [Enabled] ← Keep enabled for Windows 11
  
Security → Security Chip
  └── Security Chip: [Enabled] ← TPM 2.0 for Windows 11
```

#### 2. Boot Configuration
```
Startup → Boot
  └── Boot Mode: [UEFI Only]  ← Required
  └── Boot Priority Order:
       1. USB HDD: [Your SSD Name]
       2. [Other devices...]
       
Startup → Boot
  └── USB Boot: [Enabled]
```

#### 3. USB Configuration (if SSD not detected)
```
Config → USB
  └── USB UEFI BIOS Support: [Enabled]
  └── Always On USB: [Enabled] ← Helps with power delivery
```

#### 4. Thunderbolt (for USB-C/TB3 enclosures)
```
Config → Thunderbolt 3
  └── Thunderbolt BIOS Assist Mode: [Disabled]
  └── Security Level: [No Security] or [User Authorization]
  └── Support in Pre Boot Environment:
       └── Thunderbolt Device: [Enabled]
```

#### 5. Save and Exit
```
F10 → Save and Exit
```

### One-Time Boot Menu (Recommended)

Instead of changing boot order permanently:

**ThinkPad T480:** Press **F12** at Lenovo logo → Select USB SSD

| Manufacturer | Boot Menu Key |
|--------------|---------------|
| **Lenovo** | **F12** |
| Dell | F12 |
| HP | F9 |
| ASUS | Esc or F8 |
| Acer | F12 |

---

## **First Boot: Initial Configuration**

### 1. Complete Windows Setup

- Region/Language: Select yours
- Keyboard: Select yours
- Network: **Skip** (click "I don't have internet")
- Account: Create **local account** (no Microsoft account)
- Privacy: Disable all telemetry options

### 2. Install Required Software (While Online)

Before air-gapping, install all tools:

```powershell
# Run PowerShell as Administrator

# Install Gpg4win (GPG suite)
winget install --id GnuPG.Gpg4win -e

# Install YubiKey Manager
winget install --id Yubico.YubiKeyManager -e

# Install Python 3
winget install --id Python.Python.3.12 -e

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Install Python packages
pip install qrcode pillow pyzbar
```

### 3. Download Additional Files

Save to Desktop or Documents:

1. **EFF Wordlist** for passphrase generation:
   ```powershell
   Invoke-WebRequest -Uri "https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt" -OutFile "$env:USERPROFILE\Downloads\eff_large_wordlist.txt"
   ```

2. **(Optional) WSL2** for paperkey support:
   ```powershell
   wsl --install -d Debian
   # Restart required, then:
   wsl -d Debian -e bash -c "sudo apt update && sudo apt install -y paperkey qrencode zbar-tools"
   ```

### 4. Verify Installation

```powershell
Write-Host "=== Verification ===" -ForegroundColor Cyan

# GPG
gpg --version | Select-Object -First 1

# YubiKey Manager
ykman --version

# Python
python --version
python -c "import qrcode, PIL, pyzbar; print('Python packages: OK')"

# Wordlist
if (Test-Path "$env:USERPROFILE\Downloads\eff_large_wordlist.txt") {
    Write-Host "Wordlist: OK" -ForegroundColor Green
}
```

### 5. Create System Restore Point

```powershell
# Create restore point before air-gapping
Checkpoint-Computer -Description "Pre-AirGap Clean State" -RestorePointType "MODIFY_SETTINGS"
```

---

## **Air-Gapping the System**

### Disable All Network Adapters

```powershell
# Disable all network adapters
Get-NetAdapter | Disable-NetAdapter -Confirm:$false

# Verify
Get-NetAdapter | Format-Table Name, Status
# All should show "Disabled"
```

### Physical Verification

1. **Wi-Fi LED** should be off (ThinkPad: Fn+F8 to toggle)
2. **Ethernet** cable disconnected
3. **Bluetooth** disabled in Settings

### Test Air-Gap

```powershell
$test = Test-NetConnection 8.8.8.8 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
if ($test.PingSucceeded) {
    Write-Host "❌ NETWORK STILL ACTIVE - Check adapters" -ForegroundColor Red
} else {
    Write-Host "✅ AIR-GAP VERIFIED" -ForegroundColor Green
}
```

---

## **Troubleshooting & FAQ**

### Boot Issues

#### Q: External SSD not appearing in boot menu?

**Solutions:**
1. **Check USB port:** Use USB 3.0 (blue) or USB-C port directly on laptop
2. **Avoid USB hubs:** Boot directly from laptop port
3. **Check BIOS settings:**
   ```
   Config → USB → USB UEFI BIOS Support: [Enabled]
   Startup → Boot → USB Boot: [Enabled]
   ```
4. **Try different port:** USB-A vs USB-C
5. **Reseat connection:** Unplug, wait 5 seconds, replug

#### Q: "No bootable device found"?

**Solutions:**
1. **Verify GPT/UEFI:** Rufus must use GPT + UEFI (not MBR)
2. **Check Secure Boot compatibility:** Some SSDs need Secure Boot disabled temporarily
3. **Recreate with Rufus:** Ensure "Windows To Go" mode selected

#### Q: Boot loops or BSOD?

**Solutions:**
1. **Driver issue:** Try different USB port/enclosure
2. **USB power:** Use powered USB hub or Thunderbolt port
3. **Disable Fast Startup:**
   ```powershell
   powercfg /h off
   ```

### ThinkPad T480 Specific Issues

#### Q: USB-C SSD not detected at boot?

**Solutions:**
1. **Use left USB-C port** (Thunderbolt 3)
2. **Update BIOS:** Download from [Lenovo Support](https://pcsupport.lenovo.com/products/laptops-and-netbooks/thinkpad-t-series-laptops/thinkpad-t480-type-20l5-20l6)
3. **Thunderbolt settings:**
   ```
   Config → Thunderbolt 3 → Support in Pre Boot Environment → [Enabled]
   ```

#### Q: SSD disconnects during use?

**Solutions:**
1. **Disable USB selective suspend:**
   ```powershell
   powercfg /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
   powercfg /SETDCVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
   powercfg /SETACTIVE SCHEME_CURRENT
   ```
2. **Use USB-A port:** More stable power delivery on some enclosures
3. **Check enclosure quality:** Cheap enclosures may have power issues

#### Q: Slow performance on USB?

**Solutions:**
1. **Use USB 3.0+ port** (not USB 2.0)
2. **Use NVMe SSD in enclosure** (not SATA)
3. **Check USB mode in Device Manager:**
   - Should show "USB 3.0" or "USB 3.1"
   - If "USB 2.0", try different port

### Windows Issues

#### Q: Windows activation prompts?

**Answer:** Windows To Go installations don't require activation for basic use. Dismiss the watermark - it doesn't affect functionality for this purpose.

#### Q: "Windows isn't activated" watermark?

**Answer:** Ignore it. For air-gapped key generation, activation is unnecessary.

#### Q: Windows Update trying to run?

**Solutions:**
1. **Air-gap handles this** - no network = no updates
2. **Disable update service** (if network temporarily needed):
   ```powershell
   Stop-Service wuauserv
   Set-Service wuauserv -StartupType Disabled
   ```

### YubiKey Issues

#### Q: YubiKey not detected?

**Solutions:**
1. **Check Device Manager:** Should appear under "Smart Card Readers"
2. **Install YubiKey drivers:**
   ```powershell
   winget install Yubico.YubiKeyManager
   ```
3. **Restart smart card service:**
   ```powershell
   Restart-Service SCardSvr
   ```
4. **Try different USB port**

#### Q: gpg --card-status shows nothing?

**Solutions:**
1. **Kill and restart gpg-agent:**
   ```powershell
   gpgconf --kill gpg-agent
   gpg --card-status
   ```
2. **Check if ykman sees the key:**
   ```powershell
   ykman list
   ykman openpgp info
   ```

### Printer Issues

#### Q: Printer not working without internet?

**Answer:** Windows needs drivers. Solutions:
1. **Pre-install drivers while online** before air-gapping
2. **Download driver package** and install offline
3. **Use generic driver:** Right-click printer → Properties → Advanced → New Driver → "Microsoft Print to PDF" (for testing)

#### Q: Printing QR codes looks wrong?

**Solutions:**
1. **Print at 100% scale** (no fit-to-page)
2. **Use high quality print setting**
3. **Print on white paper** (not colored)

---

## **Security Considerations**

### SSD Security

| Aspect | Recommendation |
|--------|----------------|
| **Encryption** | Enable BitLocker on the external SSD |
| **Storage** | Keep SSD in secure location when not in use |
| **Disposal** | Secure wipe before disposal |

### Enable BitLocker (Optional)

```powershell
# Enable BitLocker on external SSD
# Replace E: with your SSD drive letter
Enable-BitLocker -MountPoint "E:" -EncryptionMethod Aes256 -UsedSpaceOnly -PasswordProtector

# Store recovery key securely!
```

### After Key Ceremony

1. **Verify backups** are on separate USB/SSD
2. **Secure wipe working directory:**
   ```powershell
   cipher /w:$env:TEMP
   ```
3. **Consider wiping entire Windows installation** if SSD won't be reused:
   ```powershell
   # DESTRUCTIVE - erases entire SSD
   # Format in Disk Management or:
   Clear-Disk -Number X -RemoveData -Confirm:$false
   ```

---

## **Quick Reference: ThinkPad T480**

| Action | Key/Method |
|--------|------------|
| Enter BIOS | **F1** at Lenovo logo |
| Boot Menu | **F12** at Lenovo logo |
| Toggle Wi-Fi | **Fn + F8** |
| Best USB port | Left USB-C (Thunderbolt 3) |
| BIOS Update | [Lenovo Support](https://pcsupport.lenovo.com/products/laptops-and-netbooks/thinkpad-t-series-laptops/thinkpad-t480-type-20l5-20l6) |

---

## **Pre-Flight Checklist**

Before starting the key ceremony:

- [ ] External SSD boots successfully
- [ ] Windows configured with local account
- [ ] Gpg4win installed and `gpg --version` works
- [ ] YubiKey Manager installed and `ykman list` shows device
- [ ] Python installed with qrcode, pillow, pyzbar packages
- [ ] EFF wordlist downloaded
- [ ] Printer tested and working
- [ ] Network adapters disabled
- [ ] Air-gap verified (ping fails)
- [ ] USB backup drives ready and formatted
- [ ] Paper and pen ready for passphrase

---

## **Next Steps**

Once your environment is ready, proceed to:
→ [Windows OpenPGP Provisioning Guide](openpgp-airgapped-provisioning-windows.md)

---

## **License**

This guide is provided under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
