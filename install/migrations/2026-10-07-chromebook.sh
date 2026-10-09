#!/usr/bin/env bash
# An4rch 2.3: Chromebook top-row keys and touchpad (does nothing on other computers).
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
bash "$LUMEN_PATH/install/chromebook.sh" --check || exit 0
sudo bash "$LUMEN_PATH/install/chromebook.sh"
