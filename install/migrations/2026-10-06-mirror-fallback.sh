#!/usr/bin/env bash
# An4rch 2.3: an install on a slow connection could end up with no active
# mirror (ranking timed out), so nothing could be downloaded or updated.
# Give such a system Arch's worldwide mirrors.
set -euo pipefail
f=/etc/pacman.d/mirrorlist
grep -q '^[[:space:]]*Server' "$f" 2>/dev/null && exit 0
# shellcheck disable=SC2016 # $repo and $arch are pacman's
printf '%s\n' '# Arch Linux worldwide mirrors (An4rch OS fallback; run reflector to rank local ones)' \
  'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' \
  'Server = https://fastly.mirror.pkgbuild.com/$repo/os/$arch' \
  'Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch' \
  'Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch' | sudo tee "$f" >/dev/null
