#!/usr/bin/env bash
# An4rch OS: CachyOS-style performance defaults (sysctls, I/O schedulers,
# NTSYNC, quick shutdowns). Re-applies the system layer, which is idempotent.
# Plain Arch installs without the An4rch OS layer are left alone.
set -euo pipefail
[[ -f /usr/share/lumen/os-release ]] || exit 0
echo "  Applying An4rch OS performance defaults"
sudo LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}" bash "${LUMEN_PATH:-$HOME/.local/share/lumen}/install/distro.sh" >/dev/null
