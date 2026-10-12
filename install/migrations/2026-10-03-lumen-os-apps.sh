#!/usr/bin/env bash
# An4rch 2.0: the Start menu, App Store and Welcome apps need Python GTK 4 and
# libadwaita; gtk4-layer-shell makes Start a proper overlay.
set -euo pipefail
need=()
for p in python-gobject gtk4 libadwaita gtk4-layer-shell flatpak; do
  pacman -Q "$p" >/dev/null 2>&1 || need+=("$p")
done
if [[ ${#need[@]} -gt 0 ]]; then
  echo "  Installing ${need[*]} for the Start menu and App Store"
  sudo pacman -S --needed --noconfirm "${need[@]}"
fi
# Skip the first-boot tour for people upgrading: they know their way around.
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/lumen"
touch "${XDG_STATE_HOME:-$HOME/.local/state}/lumen/welcome-done"
