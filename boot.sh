#!/usr/bin/env bash
# An4rch bootstrap. On a fresh Arch install, logged in as your user:
#
#   curl -fsSL https://raw.githubusercontent.com/an4rchuk/an4rch-os/HEAD/boot.sh | bash
#
# Clones An4rch to ~/.local/share/lumen and starts the installer. Any
# arguments are passed on, e.g. `… | bash -s -- --yes --browser chromium`.
set -euo pipefail

repo="${LUMEN_REPO:-https://github.com/an4rchuk/an4rch-os.git}"
ref="${LUMEN_REF:-}" # branch or tag; empty: the repository's default branch
dest="$HOME/.local/share/lumen"

[[ -f /etc/arch-release ]] || { echo "An4rch needs Arch Linux."; exit 1; }
[[ $EUID -ne 0 ]] || { echo "Run this as your normal user, not root."; exit 1; }

echo "Getting An4rch…"
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
  # Fall back to the project's name before the An4rch rename.
  git clone --quiet ${ref:+--branch "$ref"} "$repo" "$dest" 2>/dev/null ||
    GIT_TERMINAL_PROMPT=0 git clone --quiet ${ref:+--branch "$ref"} https://github.com/an4rchuk/lumen-os.git "$dest"
fi

# The installer asks questions, so give it the terminal even when piped.
exec bash "$dest/install.sh" "$@" </dev/tty
