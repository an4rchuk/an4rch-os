#!/usr/bin/env bash
# Turn on the multilib repository (32-bit libraries for Steam, Wine and
# Proton) and refresh the package lists. Run as root. Safe to run again.
#
# Uncomments the stock "#[multilib]" section when there is one, and adds the
# section when the file has none (some images ship a trimmed pacman.conf).
set -euo pipefail
conf=/etc/pacman.conf
# an4rch OS installing offline from its USB stick switches the online repos
# off with this marker (and back on afterwards).
mark='#lumen-offline-only#'
if ! grep -qE "^($mark)?\[multilib\]" "$conf"; then
  sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$conf"
  grep -q '^\[multilib\]' "$conf" || printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>"$conf"
fi
if grep -q "^$mark" "$conf"; then
  sed -i -E "/^\[multilib\]\$/,/^\$/ s/^/$mark/" "$conf"
fi
pacman -Sy --noconfirm >/dev/null
