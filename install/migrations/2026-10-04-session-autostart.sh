#!/usr/bin/env bash
# Start the An4rch session from XDG autostart too, not only from Hyprland's
# start hook, so the bar and wallpaper always come up.
set -euo pipefail
"${LUMEN_PATH:-$HOME/.local/share/lumen}/bin/anarch-session" autostart
