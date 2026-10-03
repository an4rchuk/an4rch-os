#!/usr/bin/env bash
# Lumen OS: CachyOS-style performance defaults (sysctls, I/O schedulers,
# NTSYNC, quick shutdowns). Re-applies the system layer, which is idempotent.
# Plain Arch installs without the Lumen OS layer are left alone.
set -euo pipefail
[[ -f /usr/share/lumen/os-release ]] || exit 0
echo "  Applying Lumen OS performance defaults"
sudo LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}" bash "${LUMEN_PATH:-$HOME/.local/share/lumen}/install/distro.sh" >/dev/null
