#!/usr/bin/env bash
# An4rch OS 1.1.0: privacy and safety tools. "Remove hidden data" in the file
# manager, the daily health check, drive monitoring and the monthly btrfs scrub.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
source "$LUMEN_PATH/lib/lumen.sh"

echo "  New: anarch privacy, vault, sandbox, scrub, panic (⊞ ⇧ Esc), carry, health, a11y, focus"
is_server || "$LUMEN_PATH/bin/anarch-scrub" setup >/dev/null
"$LUMEN_PATH/bin/anarch-health" timer >/dev/null 2>&1 || true

# Drive monitoring and the scrub (best-effort: never stop an update over it).
if [[ -f /usr/share/lumen/os-release ]]; then
  sudo pacman -S --needed --noconfirm smartmontools gocryptfs mat2 >/dev/null 2>&1 || true
  if pacman -Q smartmontools >/dev/null 2>&1; then
    sudo bash "$LUMEN_PATH/install/smartd.sh" || true
    sudo systemctl enable --now smartd.service >/dev/null 2>&1 || true
  fi
  if [[ "$(findmnt -no FSTYPE /)" == btrfs ]]; then
    sudo systemctl enable --now btrfs-scrub@-.timer >/dev/null 2>&1 || true
  fi
fi
