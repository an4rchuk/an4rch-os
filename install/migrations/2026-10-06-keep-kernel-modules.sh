#!/usr/bin/env bash
# Lumen 2.3: USB sticks (exFAT, NTFS) kept failing to open after a kernel
# update until a restart; the running kernel's modules are now kept until
# then. Also the tools for exFAT, NTFS and FAT drives.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
sudo bash "$LUMEN_PATH/install/keep-modules.sh"
sudo pacman -S --needed --noconfirm exfatprogs ntfs-3g dosfstools || true
