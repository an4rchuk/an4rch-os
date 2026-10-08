#!/usr/bin/env bash
# an4rch OS 1.1.0: the system's name (os-release), console greeting and logo.
set -euo pipefail
LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
[[ -f /usr/share/lumen/os-release ]] || exit 0 # desktop-only install on plain Arch
sudo bash "$LUMEN_PATH/install/branding.sh"
