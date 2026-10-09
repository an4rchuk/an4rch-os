#!/usr/bin/env bash
# an4rch OS 1.1.1: widgets on the top bar (anarch widget). Add the widget slot
# to your top bar config, unless you've changed that part of it.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
source "$LUMEN_PATH/lib/lumen.sh"

echo "  New: widgets on the top bar: anarch widget (weather, CPU temperature, countdown… or make your own)"
"$LUMEN_PATH/bin/anarch-widget" sync >/dev/null 2>&1 || true
bar="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc"
if [[ -f "$bar" ]] && ! grep -q 'lumen/widgets.jsonc' "$bar" && grep -q '"reload_style_on_change": true,' "$bar" && grep -q '^    "group/status",' "$bar"; then
  cp "$bar" "$bar.before-widgets"
  sed -i -e 's|^  "reload_style_on_change": true,$|&\n  // Your widgets (anarch widget): written to this file, shown as "group/widgets".\n  "include": ["~/.config/lumen/widgets.jsonc"],|' \
    -e 's|^    "group/status",$|    "group/widgets",\n&|' "$bar"
  pkill -SIGUSR2 -x waybar 2>/dev/null || true
fi
true
