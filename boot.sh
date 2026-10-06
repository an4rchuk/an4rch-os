#!/usr/bin/env bash
# Lumen bootstrap. On a fresh Arch install, logged in as your user:
#
#   curl -fsSL https://raw.githubusercontent.com/an4rchuk/lumen-os/HEAD/boot.sh | bash
#
# Clones Lumen to ~/.local/share/lumen and starts the installer. Any
# arguments are passed on, e.g. `… | bash -s -- --yes --browser chromium`.
set -euo pipefail

repo="${LUMEN_REPO:-https://github.com/an4rchuk/lumen-os.git}"
ref="${LUMEN_REF:-}" # branch or tag; empty: the repository's default branch
dest="$HOME/.local/share/lumen"

[[ -f /etc/arch-release ]] || { echo "Lumen needs Arch Linux."; exit 1; }
[[ $EUID -ne 0 ]] || { echo "Run this as your normal user, not root."; exit 1; }

echo "Getting Lumen…"
command -v git >/dev/null || sudo pacman -Sy --needed --noconfirm git

if [[ -d "$dest/.git" ]]; then
  if [[ -n "$ref" ]]; then
    git -C "$dest" fetch --quiet origin "$ref"
    git -C "$dest" checkout --quiet "$ref"
    git -C "$dest" pull --quiet --ff-only origin "$ref"
  else
    git -C "$dest" pull --quiet --ff-only
  fi
else
  rm -rf "$dest"
  git clone --quiet ${ref:+--branch "$ref"} "$repo" "$dest"
fi

# The installer asks questions, so give it the terminal even when piped.
exec bash "$dest/install.sh" "$@" </dev/tty
