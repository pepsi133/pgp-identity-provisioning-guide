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
# KEEP TERMINAL OPEN: Pause on exit (success or failure) so user can read output
trap 'echo "Press Enter to exit..."; read' EXIT

# ==========================================
# CONFIGURATION
# ==========================================
# ISO & Validations
ISO_URL="https://laotzu.ftp.acc.umu.se/debian-cd/current-live/amd64/iso-hybrid/"
CHECKSUM_FILE="SHA512SUMS"

# Directory for all offline assets
PGP_LIVE_ASSETS_DIR="./pgp_live_assets"

# ==========================================

# 1. PREPARE DIRECTORY
echo "[+] Setting up assets directory at: $PGP_LIVE_ASSETS_DIR"
mkdir -p "$PGP_LIVE_ASSETS_DIR" 
cd "$PGP_LIVE_ASSETS_DIR"

# 2. RESOLVE & DOWNLOAD ISO
echo "[+] Querying $ISO_URL for latest GNOME image..."
# Dynamically fetch the latest version matching the pattern
ISO_NAME=$(curl -sL "$ISO_URL" | grep -oP 'debian-live-\d+\.\d+\.\d+-amd64-gnome\.iso' | head -1)

if [ -z "$ISO_NAME" ]; then
    echo "❌ ERROR: Could not resolve ISO filename from $ISO_URL"
    exit 1
fi
echo "[+] Latest Version Found: $ISO_NAME"

echo "[+] Fetching Image..."
wget -c "${ISO_URL}${ISO_NAME}"
wget -O "${CHECKSUM_FILE}" "${ISO_URL}${CHECKSUM_FILE}"

# 3. INTEGRITY CHECK
echo "[+] Verifying Integrity..."
grep -P "\s$ISO_NAME$" "$CHECKSUM_FILE" | sha512sum -c -

echo "[✓] Preparation Complete. Assets ready in: $PGP_LIVE_ASSETS_DIR"
```

---

## Phase 2: Image Writing (Choose Option A or B)

### Option A: Windows Native (Rufus)
1. **Tool:** Open [Rufus](https://rufus.ie/).
2. **Device:** Select your **USB Flash Drive**.
3. **Boot Selection:** Select the downloaded **debian-live-*-amd64-gnome.iso**.
4. **Flash Mode:** Click **START**. When the "ISOHybrid" prompt appears, **YOU MUST SELECT "Write in DD Image mode"**.
5. **Payload:** Once finished, copy the **pgp_live_assets** folder to the root of a second USB drive (or a separate partition if you are an advanced user).

### Option B: Linux Native (Advanced)
If you are on a native Linux host (not WSL), you can write the image directly.

1.  **Identify USB Device:**
    ```bash
    lsblk
    # Identify your USB drive letter (e.g., /dev/sdX). Do NOT use the wrong drive!
    ```
2.  **Write Image:**
    ```bash
    # Replace /dev/sdX with your actual USB device
    sudo dd if=debian-live-*-amd64-gnome.iso of=/dev/sdX bs=4M status=progress conv=fsync oflag=direct
    ```

---

## Phase 3: Persistence & Payload Setup (Live Session)

Boot the target air-gapped laptop from the USB. In the boot menu, select **"Debian Live with Persistence"**.

### 3.1 Partitioning for Package Persistence
Once the desktop loads, open a terminal:

```bash
# 1. Identify USB Device (e.g., /dev/sda)
lsblk

# 2. visual Partitioning (Robust)
# Run cfdisk: Select 'Free Space' -> 'New' -> 'Write' -> 'Quit'
sudo cfdisk /dev/sda

# 3. Format the New Partition
# Check lsblk again to find the new partition (e.g., sda3)
lsblk
# Replace /dev/sda3 below with your actual new partition name
sudo mkfs.ext4 -L persistence /dev/sda3

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

## Phase 4: Ready for Provisioning
The USB is now ready. 
1. Boot the target laptop.
2. Select "Debian Live with Persistence".
3. Proceed immediately to the **Main Provisioning Protocol** document (`openpgp-airgapped-provisioning.md`).
   - You will perform the "System Preparation (Online)" step there to install tools and drivers.

---

## Ready for Provisioning
The system is now hardened, air-gapped, and equipped with all necessary tools. You may now proceed to the **Main Provisioning Protocol** to generate your Root CA and provision YubiKeys.

**Security Reminder:** Upon power-off, all data in `/tmp` and `/home/user` will be permanently lost. Only the software tools and drivers in `/var` are preserved on the USB.