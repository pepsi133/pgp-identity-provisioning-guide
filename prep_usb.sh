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

# Printer Support Selection (Set to "true" to include)
INCLUDE_IPP_USB="true"  # Modern Driverless (AirPrint/IPP-Everywhere) - RECOMMENDED
INCLUDE_BROTHER="true"  # Legacy Brother DCP-J725DW (requires 32-bit libs)
INCLUDE_HP="false"      # HP Printers (HPLIP)
INCLUDE_GENERIC="true"  # Universal metapackage (Canon, Epson, etc.)

# Base Toolset (Required)
# Note: 'rng-tools5' is the current package on Kali/Debian, replacing 'rng-tools'
BASE_PACKAGES="qrencode zbar-tools paperkey pcscd scdaemon system-config-printer rng-tools5"

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
    
    wget "https://download.brother.com/pub/com/linux/linux/dlf/dcpj725dwlpr-3.0.1-1.i386.deb"
    wget "https://download.brother.com/pub/com/linux/linux/dlf/dcpj725dwcupswrapper-3.0.0-1.i386.deb"
fi

echo "[✓] Preparation Complete. Assets ready in: $PGP_LIVE_ASSETS_DIR"
