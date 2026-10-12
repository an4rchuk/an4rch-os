#!/usr/bin/env bash
# An4rch OS 1.1.0: the final artwork. The An4rch logo on the boot screen, the
# logo icon and console colours, and the An4rch theme in black and red (the
# old violet look gave way to the anarchism themes in 1.1.1).
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
source "$LUMEN_PATH/lib/lumen.sh"

echo "  New: the An4rch logo on the boot screen, and the An4rch theme in black and red"

# The An4rch theme's painted wallpapers were violet: paint them again in red,
# and show the new logo wallpaper if an An4rch wallpaper was in use.
old="$LUMEN_WALLPAPERS/an4rch"
if [[ -d "$old" ]]; then
  current=$(readlink "$LUMEN_CURRENT/wallpaper" 2>/dev/null || true)
  rm -rf "$old"
  if [[ "$current" == "$old"/* ]]; then
    new="$LUMEN_PATH/themes/an4rch/backgrounds/1-an4rch-corner.png"
    ln -sfn "$new" "$LUMEN_CURRENT/wallpaper"
    mkdir -p "$LUMEN_STATE" && printf '%s\n' "$new" >"$LUMEN_STATE/wallpaper-an4rch"
  fi
fi
if ! is_server && [[ "$(theme_current)" == an4rch && -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  "$LUMEN_PATH/bin/anarch-wallpaper" theme >/dev/null 2>&1 || true
fi

# The boot screen and branding (best-effort: never stop an update over it).
if [[ -f /usr/share/lumen/os-release ]]; then
  sudo LUMEN_PATH="$LUMEN_PATH" bash "$LUMEN_PATH/install/branding.sh" || true
  echo "  Updating the boot screen (this takes a moment)"
  sudo LUMEN_PATH="$LUMEN_PATH" bash "$LUMEN_PATH/install/plymouth.sh" || true
fi
