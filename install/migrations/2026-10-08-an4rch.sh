#!/usr/bin/env bash
# an4rch OS 1.1.0: the rename from Lumen OS. The system name, the signature
# theme (lumen → an4rch) and the new wallpapers (gradients as well as the
# abstract ones). Commands, folders and settings stay where they are.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
source "$LUMEN_PATH/lib/lumen.sh"

echo "  Lumen OS is now an4rch OS (the 'anarch' command; 'lumen' still works)"

# The signature theme's new name.
if [[ "$(cat "$LUMEN_CURRENT/theme.name" 2>/dev/null)" == lumen && ! -f "$LUMEN_CONFIG/themes/lumen/theme.conf" ]]; then
  printf '%s\n' an4rch >"$LUMEN_CURRENT/theme.name"
fi
if [[ -f "$LUMEN_STATE/wallpaper-lumen" && ! -e "$LUMEN_STATE/wallpaper-an4rch" ]]; then
  mv "$LUMEN_STATE/wallpaper-lumen" "$LUMEN_STATE/wallpaper-an4rch"
fi

# Painted wallpapers: the current theme's are repainted now (new styles,
# new numbering); every other theme's on first use. Only an4rch's own
# painted files (NN-style.jpg) are removed.
for d in "$LUMEN_WALLPAPERS"/*/; do
  [[ -d "$d" ]] || continue
  find "$d" -maxdepth 1 -type f -regex '.*/[0-9][0-9]-[a-z]+\.jpg' -delete
  rmdir "$d" 2>/dev/null || true
done
theme=$(theme_current)
if python3 -c 'import PIL' 2>/dev/null; then
  echo "  Painting this theme's new wallpapers"
  python3 "$LUMEN_PATH/bin/anarch-wallgen" --theme "$theme" --out "$LUMEN_WALLPAPERS" >/dev/null 2>&1 || true
fi
# The remembered wallpaper may have been one of the old ones.
if [[ -f "$LUMEN_STATE/wallpaper-$theme" && ! -f "$(cat "$LUMEN_STATE/wallpaper-$theme")" ]]; then
  rm -f "$LUMEN_STATE/wallpaper-$theme"
fi
if [[ -L "$LUMEN_CURRENT/wallpaper" && ! -e "$LUMEN_CURRENT/wallpaper" ]]; then
  rm -f "$LUMEN_CURRENT/wallpaper"
fi
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  "$LUMEN_PATH/bin/anarch-wallpaper" theme >/dev/null 2>&1 || true
fi
