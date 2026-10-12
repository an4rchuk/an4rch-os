#!/usr/bin/env bash
# An4rch OS 1.1.1: the anarchism themes come with An4rch, with An4rch Light;
# the old palettes (Cachy, Tokyo Night, Catppuccin, Gruvbox, Nord, Rosé Pine,
# Everforest, Kanagawa, the violet an4rch) are retired.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
source "$LUMEN_PATH/lib/lumen.sh"

echo "  New: the anarchism themes and An4rch Light come with An4rch (SUPER + CTRL + T)."

# Copies of the anarchism pack's themes: the bundled ones replace them.
for f in "$LUMEN_CONFIG"/themes/*/.pack; do
  [[ -f "$f" && "$(cat "$f")" == anarchism ]] || continue
  rm -rf "$(dirname "$f")"
done

# Retired themes: switch to the replacement (theme_renamed), and drop their
# painted wallpapers. Themes of your own by those names are left alone.
retired=(an4rch-violet cachy catppuccin-mocha catppuccin-latte tokyo-night gruvbox nord rose-pine everforest kanagawa)
cur=$(cat "$LUMEN_CURRENT/theme.name" 2>/dev/null || echo "$DEFAULT_THEME")
for t in "${retired[@]}"; do
  [[ -f "$LUMEN_CONFIG/themes/$t/theme.conf" ]] && continue
  rm -rf "${LUMEN_WALLPAPERS:?}/$t"
  if [[ "$cur" == "$t" ]]; then
    echo "  The $t theme is retired: switching to $(theme_renamed "$t")."
    "$LUMEN_PATH/bin/anarch-theme" set "$(theme_renamed "$t")" >/dev/null 2>&1 || true
  fi
done

# anarch auto: retired light/dark choices.
auto="$LUMEN_CONFIG/auto.conf"
if [[ -f "$auto" ]]; then
  for key in LIGHT DARK; do
    v=$(sed -n "s/^$key=//p" "$auto" | head -n1)
    [[ -n "$v" && "$(theme_renamed "$v")" != "$v" ]] && sed -i "s/^$key=.*/$key=$(theme_renamed "$v")/" "$auto"
  done
fi
true
