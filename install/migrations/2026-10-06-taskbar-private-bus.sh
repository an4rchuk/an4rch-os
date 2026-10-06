#!/usr/bin/env bash
# Lumen 2.3: the taskbar runs on its own D-Bus session (dbus-run-session), so
# it no longer joins the top bar's waybar and crashes a few minutes after
# login. Installs the tool if needed and restarts the taskbar.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
command -v dbus-run-session >/dev/null || sudo pacman -S --needed --noconfirm dbus || true
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  "$LUMEN_PATH/bin/lumen-taskbar" restart || true
fi
