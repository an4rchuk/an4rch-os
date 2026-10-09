#!/usr/bin/env bash
# The an4rch boot screen (Plymouth): the logo on black with a slow red glow,
# and the disk password asked for in the same style. Run as root.
#
#   install/plymouth.sh            install the theme and make it the default;
#                                  rebuilds the initramfs if anything changed
#   install/plymouth.sh --root DIR install into a system mounted at DIR (the
#                                  ISO installer, before it builds the initramfs)
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
LUMEN_PATH="${LUMEN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
root=""
[[ "${1:-}" == --root ]] && root="${2:?--root needs a directory}"

src="$LUMEN_PATH/share/plymouth/an4rch"
dest="$root/usr/share/plymouth/themes/an4rch"
conf="$root/etc/plymouth/plymouthd.conf"

before=$( { cat "$dest"/* "$conf" 2>/dev/null || true; } | md5sum)
install -d "$dest" "$root/etc/plymouth"
install -m644 "$src"/* "$dest/"
cat >"$conf" <<'PLY'
[Daemon]
Theme=an4rch
ShowDelay=0
DeviceTimeout=8
PLY
# Hand over to the login screen smoothly: once the animation has played, and
# keeping the last frame on screen until the login screen draws (no black gap).
install -Dm755 "$LUMEN_PATH/share/plymouth/splash-wait" "$root/usr/local/lib/lumen/splash-wait"
install -d "$root/etc/systemd/system/plymouth-quit.service.d"
cat >"$root/etc/systemd/system/plymouth-quit.service.d/an4rch.conf" <<'UNIT'
# an4rch: let the boot animation finish, and keep its last frame until the
# login screen (or desktop) draws over it.
[Service]
ExecStartPre=-/usr/local/lib/lumen/splash-wait
ExecStart=
ExecStart=-/usr/bin/plymouth quit --retain-splash
UNIT
after=$( { cat "$dest"/* "$conf" 2>/dev/null || true; } | md5sum)

# The theme is copied into the initramfs, so a change needs a rebuild (only
# on a running system that uses the plymouth hook; the ISO installer builds
# the initramfs itself afterwards).
if [[ -z "$root" && "$before" != "$after" ]] && command -v mkinitcpio >/dev/null &&
  grep -qsE '^[[:space:]]*HOOKS=.*\bplymouth\b' /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d/*.conf; then
  mkinitcpio -P >/dev/null 2>&1 || echo "  ! Couldn't rebuild the initramfs: the new boot screen shows after the next kernel update." >&2
fi
