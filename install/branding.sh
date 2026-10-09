#!/usr/bin/env bash
# an4rch OS branding: os-release (kept across `filesystem` upgrades), the
# console greeting, the fastfetch logo and the logo icon. Run as root; safe to
# run again (install/distro.sh runs it, and so does the rename migration).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
LUMEN_PATH="${LUMEN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERSION=$(cat "$LUMEN_PATH/VERSION" 2>/dev/null || echo rolling)

install -d /usr/share/lumen
cat >/usr/share/lumen/os-release <<OSR
NAME="an4rch OS"
PRETTY_NAME="an4rch OS"
ID=an4rch
ID_LIKE=arch
BUILD_ID=rolling
VERSION_ID=$VERSION
ANSI_COLOR="38;2;224;27;36"
HOME_URL="https://github.com/an4rchuk/an4rch-os"
DOCUMENTATION_URL="https://github.com/an4rchuk/an4rch-os/tree/HEAD/docs"
SUPPORT_URL="https://github.com/an4rchuk/an4rch-os/issues"
BUG_REPORT_URL="https://github.com/an4rchuk/an4rch-os/issues"
LOGO=lumen-logo
OSR
rm -f /etc/os-release
cp /usr/share/lumen/os-release /etc/os-release

# `filesystem` owns /etc/os-release and would put Arch's back on upgrade.
install -d /etc/pacman.d/hooks
cat >/etc/pacman.d/hooks/90-lumen-os-release.hook <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = filesystem

[Action]
Description = Keeping the an4rch OS release information...
When = PostTransaction
Exec = /usr/bin/sh -c 'rm -f /etc/os-release && cp /usr/share/lumen/os-release /etc/os-release'
HOOK

printf '\n  \e[38;2;224;27;36man4rch OS\e[0m  ·  \\l\n\n' >/etc/issue
install -m644 "$LUMEN_PATH/system/logo.txt" /usr/share/lumen/logo.txt
install -Dm644 "$LUMEN_PATH/system/fastfetch/config.jsonc" /etc/xdg/fastfetch/config.jsonc
install -Dm644 "$LUMEN_PATH/share/icons/hicolor/scalable/apps/lumen-logo.svg" /usr/share/icons/hicolor/scalable/apps/lumen-logo.svg
gtk-update-icon-cache -q -t /usr/share/icons/hicolor 2>/dev/null || true
