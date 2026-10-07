#!/usr/bin/env bash
# an4rch 2.1: title bars with close/maximise/minimise buttons (hyprbars plugin,
# on unless LUMEN_TITLEBARS=no) and minimise/restore support.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
source "$LUMEN_PATH/lib/lumen.sh"
"$LUMEN_PATH/bin/lumen-session" autostart >/dev/null 2>&1 || true
[[ "${LUMEN_TITLEBARS:-yes}" == yes ]] || exit 0
echo "  Building window title bars (one-time, a few minutes; turn off with: anarch titlebars off)"
LUMEN_YES=1 "$LUMEN_PATH/bin/lumen-titlebars" setup
"$LUMEN_PATH/bin/lumen-titlebars" load
