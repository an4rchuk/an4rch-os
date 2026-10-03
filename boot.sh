#!/usr/bin/env bash
# Lumen bootstrap. On a fresh Arch install, logged in as your user:
#
#   curl -fsSL https://raw.githubusercontent.com/twil09/linux/main/boot.sh | bash
#
# Clones Lumen to ~/.local/share/lumen and starts the installer. Any
# arguments are passed on, e.g. `… | bash -s -- --yes --browser chromium`.
set -euo pipefail

repo="${LUMEN_REPO:-https://github.com/twil09/linux.git}"
ref="${LUMEN_REF:-main}"
dest="$HOME/.local/share/lumen"

[[ -f /etc/arch-release ]] || { echo "Lumen needs Arch Linux."; exit 1; }
[[ $EUID -ne 0 ]] || { echo "Run this as your normal user, not root."; exit 1; }

echo "Getting Lumen…"
command -v git >/dev/null || sudo pacman -Sy --needed --noconfirm git

if [[ -d "$dest/.git" ]]; then
  git -C "$dest" fetch --quiet origin "$ref"
  git -C "$dest" checkout --quiet "$ref"
  git -C "$dest" pull --quiet --ff-only origin "$ref"
else
  rm -rf "$dest"
  git clone --quiet --branch "$ref" "$repo" "$dest"
fi

# The installer asks questions, so give it the terminal even when piped.
exec bash "$dest/install.sh" "$@" </dev/tty
