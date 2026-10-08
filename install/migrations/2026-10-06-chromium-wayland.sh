#!/usr/bin/env bash
# an4rch 2.3: Chromium, Brave and Chrome run as native Wayland apps (they
# could fail to open without an X display, and look blurry when scaled).
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
for f in chromium brave chrome; do
  dest="${XDG_CONFIG_HOME:-$HOME/.config}/$f-flags.conf"
  [[ -e "$dest" ]] || cp "$LUMEN_PATH/config/$f-flags.conf" "$dest"
done
