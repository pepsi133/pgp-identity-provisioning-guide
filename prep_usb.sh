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

# Directory for ISO assets
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

echo "[✓] Preparation Complete. ISO ready in: $PGP_LIVE_ASSETS_DIR"
