#!/usr/bin/env bash
# an4rch 2.2: a graphical login screen (ReGreet) in your theme and wallpaper,
# replacing the text one, on systems that use an4rch's greetd setup.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
conf=/etc/greetd/config.toml
grep -q "Welcome to an4rch" "$conf" 2>/dev/null || exit 0
echo "  Setting up the new login screen (your theme and wallpaper)"
"$LUMEN_PATH/bin/anarch-login" setup
