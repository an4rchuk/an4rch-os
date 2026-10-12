#!/usr/bin/env bash
# An4rch OS 1.1.2: KDE Connect through the firewall however it was installed
# (phones couldn't find the computer when it came from the App Store), and
# mDNS for the iPhone app's discovery.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
source "$LUMEN_PATH/lib/lumen.sh"

[[ -f /usr/share/lumen/os-release ]] || exit 0
sudo install -Dm755 "$LUMEN_PATH/share/phone/kdeconnect-firewall" /usr/local/lib/lumen/kdeconnect-firewall || exit 0
sudo tee /etc/pacman.d/hooks/90-an4rch-kdeconnect.hook >/dev/null <<'HOOK' || true
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = kdeconnect

[Action]
Description = Letting KDE Connect through the firewall...
When = PostTransaction
Exec = /usr/local/lib/lumen/kdeconnect-firewall
HOOK
if pacman -Q kdeconnect >/dev/null 2>&1; then
  sudo /usr/local/lib/lumen/kdeconnect-firewall || true
  echo "  Fixed: your phone can now find this computer in KDE Connect."
fi
true
