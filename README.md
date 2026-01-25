# OpenPGP Air-Gapped Identity Provisioning Guide

A comprehensive protocol for generating and securing OpenPGP master keys with hardware token (YubiKey) provisioning in an air-gapped environment.

## Overview

This repository provides step-by-step guides for:
- Generating an Ed25519/cv25519 OpenPGP master key
- Creating secure backups (digital + paper)
- Provisioning subkeys to YubiKey hardware tokens
- Establishing a "root of trust" for your digital identity

## Choose Your Platform

| Platform | Environment Setup | Provisioning Guide |
|----------|-------------------|-------------------|
| **Linux** | [Create Live Linux USB](create-live-linux-usb.md) | [OpenPGP Provisioning (Linux)](openpgp-airgapped-provisioning.md) |
| **Windows** | [Create Windows USB SSD](create-windows-usb-ssd.md) | [OpenPGP Provisioning (Windows)](openpgp-airgapped-provisioning-windows.md) |

## Quick Start

### Linux (Recommended)
1. Follow [Create Live Linux USB](create-live-linux-usb.md) to prepare a Debian Live bootable USB
2. Boot into the live environment
3. Complete [OpenPGP Provisioning Guide](openpgp-airgapped-provisioning.md)

### Windows
1. Follow [Create Windows USB SSD](create-windows-usb-ssd.md) to prepare a portable Windows 11 installation
2. Boot from the external SSD
3. Complete [OpenPGP Provisioning (Windows)](openpgp-airgapped-provisioning-windows.md)

## Hardware Requirements

- **2x YubiKey 5 series** (5C NFC recommended) - Primary + Backup
- **USB Flash Drive** - Digital backup
- **SSD/HDD** - Secondary backup
- **USB Printer** - Paper backup
- **Bootable USB/SSD** - Air-gapped environment

## Key Features

- **Air-gapped operation** - Network isolated for maximum security
- **Triple redundancy** - USB, SSD, and paper backups
- **Hardware tokens** - Keys stored on YubiKey, not disk
- **Touch policy** - Physical confirmation for cryptographic operations
- **Verification steps** - Restore tests before finalizing

## Additional Resources

- [YubiKey Troubleshooting](yubikey-troubleshooting.md)
- [Offline Bundle (Linux)](appendix-offline-bundle.md) - For fully offline installations
- [GnuPG Manual](https://gnupg.org/documentation/manuals/gnupg/)
- [drduh YubiKey Guide](https://github.com/drduh/YubiKey-Guide)

## Security Model

```
┌─────────────────────────────────────────────────────────────┐
│                    Master Key (Certify)                     │
│                    Ed25519 · No Expiry                      │
│              Stored: USB + SSD + Paper Backup               │
└─────────────────────┬───────────────────────────────────────┘
                      │ Signs
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
   ┌─────────┐   ┌─────────┐   ┌─────────┐
   │  Sign   │   │ Encrypt │   │  Auth   │
   │ Ed25519 │   │ cv25519 │   │ Ed25519 │
   │  1 Year │   │  1 Year │   │  1 Year │
   └────┬────┘   └────┬────┘   └────┬────┘
        │             │             │
        └─────────────┴─────────────┘
                      │
              Stored on YubiKey
```

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome! Please open an issue or pull request for:
- Bug fixes
- Clarifications
- Platform-specific improvements
- Translation to other languages
