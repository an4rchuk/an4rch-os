#!/usr/bin/env bash
# Lumen 2.2: a graphical login screen (ReGreet) in your theme and wallpaper,
# replacing the text one, on systems that use Lumen's greetd setup.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
conf=/etc/greetd/config.toml
grep -q "Welcome to Lumen" "$conf" 2>/dev/null || exit 0
echo "  Setting up the new login screen (your theme and wallpaper)"
"$LUMEN_PATH/bin/lumen-login" setup
