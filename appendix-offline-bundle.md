# Offline Air-Gapped Bundle Preparation (Optional)

This document describes how to prepare an offline package bundle for environments requiring **maximum hardening** where the Debian Live system **cannot temporarily connect to the internet** during Phase 0.

> [!NOTE]
> Most users can skip this document. The main guide assumes temporary internet access during Phase 0 for initial package installation, which is then followed by establishing a proper air-gap before any key generation.

## When to Use This Approach

Use offline bundles if:
- Your security policy prohibits **any** network connection on the provisioning system
- You are working in a physically isolated environment (Faraday cage, etc.)
- You need to provision keys on a machine that has never had network hardware installed

## Overview

The offline bundle approach requires two steps:
1. **Preparation** (on a separate online Debian Stable machine): Download all required packages
2. **Installation** (on the air-gapped Debian Live system): Install packages from the bundle

## Step 1: Create Offline Bundle (Online Machine)

On a **separate** Debian Stable machine with internet access:

~~~bash
# Create a local pool of .deb files for required packages
mkdir -p /tmp/pgp_bundle && cd /tmp/pgp_bundle

# Update repositories
sudo apt-get update

# Download all required packages and their dependencies
apt-get download gnupg paperkey qrencode zbar-tools coreutils \
  yubikey-manager wamerican scdaemon pcscd cups-client rng-tools5 \
  system-config-printer ipp-usb

# Verify downloads
ls -lh
echo "✅ Bundle created. Total size:"
du -sh .
~~~

## Step 2: Transfer to Air-Gapped Media

Copy the `/tmp/pgp_bundle` directory to your USB backup drive or SSD that will be used with the air-gapped Debian Live system.

## Step 3: Install on Air-Gapped System

On the air-gapped Debian Live system:

~~~bash
# Navigate to the bundle directory on your mounted media
cd /media/user/usb_backup/pgp_bundle  # adjust path as needed

# Install all packages
sudo dpkg -i *.deb

# Fix any dependency issues (this uses locally cached packages only)
sudo apt-get -f install -y

# Verify installation (run the tool verification from Step 0.2.5 of main guide)
REQUIRED_TOOLS=("gpg" "paperkey" "qrencode" "zbarimg" "zbarcam" "shuf" "sha256sum" "ykman" "lp")
MISSING_COUNT=0

for tool in "${REQUIRED_TOOLS[@]}"; do
  if command -v "$tool" >/dev/null; then
    echo "  ✅ $tool"
  else
    echo "  ❌ $tool (missing)"; MISSING_COUNT=$((MISSING_COUNT + 1))
  fi
done

# Check rngd separately (may be in /usr/sbin)
if command -v rngd >/dev/null || [ -x /usr/sbin/rngd ]; then
  echo "  ✅ rngd"
else
  echo "  ❌ rngd (missing)"; MISSING_COUNT=$((MISSING_COUNT + 1))
fi

[ $MISSING_COUNT -gt 0 ] && echo "⚠️  $MISSING_COUNT tool(s) missing." || echo "✅ All tools available."
~~~

## Troubleshooting

### Missing Dependencies

If `dpkg -i` reports missing dependencies:

1. The `apt-get -f install -y` command should resolve most issues using locally cached data
2. If persistent errors occur, you may need to download additional dependencies on the online machine:

~~~bash
# On the online machine, get dependencies recursively
cd /tmp/pgp_bundle
apt-get download $(apt-cache depends gnupg paperkey qrencode zbar-tools \
  coreutils yubikey-manager wamerican scdaemon pcscd cups-client \
  rng-tools5 system-config-printer ipp-usb | grep Depends | \
  awk '{print $2}' | sort -u)
~~~

### Debian Version Mismatch

Ensure the online machine is running the **same Debian version** as your Debian Live ISO (both Debian Stable/Bookworm, etc.). Mixing versions can cause package incompatibilities.

## After Installation

Once packages are installed successfully, return to the main guide at **Step 0.3 (Printer Setup)** and continue from there.
