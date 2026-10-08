#!/usr/bin/env bash
# an4rch 2.3: a Task Manager (Ctrl + Shift + Esc), a text editor and a camera
# app; systemd-oomd closes a runaway app instead of letting the whole
# computer freeze when memory runs out.
set -euo pipefail
need=()
for p in gnome-system-monitor gnome-text-editor snapshot; do
  pacman -Q "$p" >/dev/null 2>&1 || need+=("$p")
done
if [[ ${#need[@]} -gt 0 ]]; then
  echo "  Installing ${need[*]} (Task Manager, text editor, camera)"
  sudo pacman -S --needed --noconfirm "${need[@]}"
fi
if [[ ! -e /etc/systemd/system/user@.service.d/90-lumen-oomd.conf ]]; then
  echo "  Turning on memory protection (systemd-oomd)"
  sudo install -d "/etc/systemd/system/-.slice.d" /etc/systemd/system/user@.service.d
  printf '[Slice]\nManagedOOMSwap=kill\n' | sudo tee "/etc/systemd/system/-.slice.d/90-lumen-oomd.conf" >/dev/null
  printf '[Service]\nManagedOOMMemoryPressure=kill\nManagedOOMMemoryPressureLimit=50%%\n' |
    sudo tee /etc/systemd/system/user@.service.d/90-lumen-oomd.conf >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable --now systemd-oomd >/dev/null 2>&1 || true
fi
