# Debian 13 Live USB Preparation Guide for PGP Provisioning

This manual covers the technical preparation of a "bulletproof" Live USB environment. It focuses on setting up **Debian 13 (Trixie)** with automated package persistence and offline driver support for the **Brother DCP-J725DW** printer.

---

## Phase 1: Environment Preparation (Internet-Connected WSL 2)

Perform these steps in your Kali/Ubuntu WSL terminal to gather all necessary assets.

### 1.1 Automated Acquisition & Verification
Create a script named `prep_usb.sh` to download the ISO and all offline dependencies.

```bash
#!/bin/bash
# FAIL-FAST: Exit immediately if a command exits with a non-zero status
set -e

# ==========================================
# CONFIGURATION
# ==========================================
# ISO & Validations
ISO_URL="https://laotzu.ftp.acc.umu.se/debian-cd/current-live/amd64/iso-hybrid/"
ISO_NAME="debian-live-13.2.0-amd64-gnome.iso"
CHECKSUM_FILE="SHA512SUMS"

# Directory for all offline assets
PGP_LIVE_ASSETS_DIR="./pgp_live_assets"

# Printer Support Selection (Set to "true" to include)
INCLUDE_IPP_USB="true"  # Modern Driverless (AirPrint/IPP-Everywhere) - RECOMMENDED
INCLUDE_BROTHER="true"  # Legacy Brother DCP-J725DW (requires 32-bit libs)
INCLUDE_HP="false"      # HP Printers (HPLIP)
INCLUDE_GENERIC="true"  # Universal metapackage (Canon, Epson, etc.)

# Base Toolset (Required)
BASE_PACKAGES="qrencode zbar-tools paperkey pcscd scdaemon setup-config-printer rng-tools-debian"

# ==========================================

# 1. PREPARE DIRECTORY
echo "[+] Setting up assets directory at: $PGP_LIVE_ASSETS_DIR"
mkdir -p "$PGP_LIVE_ASSETS_DIR" 
cd "$PGP_LIVE_ASSETS_DIR"

# 2. DOWNLOAD ISO & HASHES
echo "[+] Fetching Debian 13 Image..."
wget -c "${ISO_URL}${ISO_NAME}"
wget "${ISO_URL}${CHECKSUM_FILE}"

# 3. INTEGRITY CHECK
echo "[+] Verifying Integrity..."
grep "$ISO_NAME" "$CHECKSUM_FILE" | sha512sum -c -

# 4. DOWNLOAD PACKAGES
echo "[+] Downloading Base Toolset..."
apt-get download $BASE_PACKAGES

if [ "$INCLUDE_GENERIC" = "true" ]; then
    echo "[+] Downloading Generic Printer Drivers..."
    apt-get download printer-driver-all printer-driver-gutenprint
fi

if [ "$INCLUDE_IPP_USB" = "true" ]; then
    echo "[+] Downloading IPP-USB (Driverless)..."
    apt-get download ipp-usb
fi

if [ "$INCLUDE_HP" = "true" ]; then
    echo "[+] Downloading HP Printer Drivers (HPLIP)..."
    apt-get download hplip printer-driver-hpcups
fi

# 5. BROTHER LEGACY DRIVERS
if [ "$INCLUDE_BROTHER" = "true" ]; then
    echo "[+] Fetching Brother DCP-J725DW Drivers & 32-bit libs..."
    # 32-bit lib info: lib32stdc++6 is often needed for older Brother drivers
    apt-get download lib32stdc++6 printer-driver-brlaser
    
    wget "https://download.brother.com/welcome/dlf006159/dcpj725dwlpr-3.0.1-1.i386.deb"
    wget "https://download.brother.com/welcome/dlf006161/dcpj725dwcupswrapper-3.0.0-1.i386.deb"
fi

echo "[✓] Preparation Complete. Assets ready in: $PGP_LIVE_ASSETS_DIR"
```

---

## Phase 2: Image Writing (Choose Option A or B)

### Option A: Windows Native (Rufus)
1. **Tool:** Open [Rufus](https://rufus.ie/).
2. **Device:** Select your **USB Flash Drive**.
3. **Boot Selection:** Select the downloaded **debian-live-13.2.0-amd64-gnome.iso**.
4. **Flash Mode:** Click **START**. When the "ISOHybrid" prompt appears, **YOU MUST SELECT "Write in DD Image mode"**.
5. **Payload:** Once finished, copy the **pgp_live_assets** folder to the root of a second USB drive (or a separate partition if you are an advanced user).

### Option B: WSL 2 Native (usbipd-win)
1. **PowerShell (Admin):**
   ```powershell
   usbipd list
   # Replace <BUSID> with the ID from the list (e.g., 2-1)
   usbipd attach --wsl --busid <BUSID>
   ```
2. **WSL Terminal:**
   ```bash
   # Identify USB (check size to confirm, e.g., /dev/sdX)
   lsblk
   # Perform Native DD
   sudo dd if=debian-live-13.2.0-amd64-gnome.iso of=/dev/sdX bs=4M status=progress conv=fsync oflag=direct
   ```

---

## Phase 3: Persistence & Payload Setup (Live Session)

Boot the target air-gapped laptop from the USB. In the boot menu, select **"Debian Live with Persistence"**.

### 3.1 Partitioning for Package Persistence
Once the desktop loads, open a terminal:

```bash
# 1. Identify USB Device (e.g., /dev/sda)
lsblk

# 2. Create Persistence Partition in the remaining space
# We start at 4GB to avoid overwriting the ISO system partitions
sudo parted /dev/sda mkpart primary ext4 4GB 100%
sudo mkfs.ext4 -L persistence /dev/sda2

# 3. Configure Persistence (Packages Only)
sudo mkdir -p /mnt/persist
sudo mount -L persistence /mnt/persist

# IMPORTANT: We only persist APT directories. 
# /home/user is NOT included, ensuring keys remain ephemeral (RAM-only).
echo "/var/cache/apt union" | sudo tee /mnt/persist/persistence.conf
echo "/var/lib/apt union" | sudo tee -a /mnt/persist/persistence.conf

# 4. Inject Payload for Offline Access
# Mount your second USB/Source containing pgp_live_assets and copy it here
sudo cp -r /path/to/pgp_live_assets /mnt/persist/
sudo umount /mnt/persist

# 5. REBOOT and select "Live with Persistence" again to activate
```

---

## Phase 4: Offline Hardening & Toolchain Installation

**Ensure all Networking hardware is physically disabled or blocked in BIOS.**

### 4.1 Driver & Tool Installation
Run these commands to prepare the environment.

**Strategy:**
1.  **Install Base Tools & IPP-USB first.** Try printing.
2.  **Only if that fails:** Install the legacy drivers (requires enabling 32-bit architecture).

```bash
# 1. Install Base Tools & Driverless Support
cd /lib/live/mount/persistence/*/pgp_live_assets
sudo dpkg -i ipp-usb*.deb 2>/dev/null || true
sudo dpkg -i qrencode*.deb zbar-tools*.deb paperkey*.deb pcscd*.deb scdaemon*.deb setup-config-printer*.deb rng-tools*.deb
sudo apt install -f # Fix dependencies

# 2. Check if Printer works (Driverless)
# Connect USB. If using ipp-usb, the printer appears as a Network Printer (localhost).
# SYSTEM SETTINGS -> PRINTERS -> ADD -> Network Printer

# ==========================================================
# OPTIONAL: Legacy 32-bit Brother Drivers (Fallback Only)
# Use this ONLY if ipp-usb does not work for your specific model.
# ==========================================================
# sudo dpkg --add-architecture i386
# sudo apt update
# sudo dpkg -i lib32stdc++6*.deb printer-driver-brlaser*.deb
# sudo dpkg -i dcpj725dw*.deb
# sudo apt install -f
```

### 4.2 Entropy Priming
```bash
# Saturate the kernel entropy pool for high-quality key generation
sudo rngd -r /dev/urandom
# Manually move the mouse and mash the keyboard for 60 seconds.
```

---

## Ready for Provisioning
The system is now hardened, air-gapped, and equipped with all necessary tools. You may now proceed to the **Main Provisioning Protocol** to generate your Root CA and provision YubiKeys.

**Security Reminder:** Upon power-off, all data in `/tmp` and `/home/user` will be permanently lost. Only the software tools and drivers in `/var` are preserved on the USB.