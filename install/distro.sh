#!/usr/bin/env bash
# Lumen OS system layer. Run as root (the ISO installer runs it inside the new
# system; `install.sh --distro` runs it on an existing Arch install).
#
#   - brands the OS (os-release, console greeting, fastfetch logo) and keeps
#     the branding across `filesystem` package upgrades
#   - boot splash (Plymouth), compressed RAM swap (zram), multilib for games
#   - snapshots: snapper on btrfs with snap-pac, readable by the wheel group,
#     old packages kept for rollbacks
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
LUMEN_PATH="${LUMEN_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERSION=$(cat "$LUMEN_PATH/VERSION" 2>/dev/null || echo rolling)

# --- Branding ---------------------------------------------------------------------
install -d /usr/share/lumen
cat >/usr/share/lumen/os-release <<OSR
NAME="Lumen OS"
PRETTY_NAME="Lumen OS"
ID=lumen
ID_LIKE=arch
BUILD_ID=rolling
VERSION_ID=$VERSION
ANSI_COLOR="38;2;157;140;255"
HOME_URL="https://github.com/twil09/linux"
DOCUMENTATION_URL="https://github.com/twil09/linux/tree/main/docs"
SUPPORT_URL="https://github.com/twil09/linux/issues"
BUG_REPORT_URL="https://github.com/twil09/linux/issues"
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
Description = Keeping the Lumen OS release information...
When = PostTransaction
Exec = /usr/bin/sh -c 'rm -f /etc/os-release && cp /usr/share/lumen/os-release /etc/os-release'
HOOK

printf '\n  \e[38;2;157;140;255mLumen OS\e[0m  ·  \\l\n\n' >/etc/issue
install -m644 "$LUMEN_PATH/system/logo.txt" /usr/share/lumen/logo.txt
install -Dm644 "$LUMEN_PATH/system/fastfetch/config.jsonc" /etc/xdg/fastfetch/config.jsonc
install -Dm644 "$LUMEN_PATH/share/icons/hicolor/scalable/apps/lumen-logo.svg" /usr/share/icons/hicolor/scalable/apps/lumen-logo.svg
gtk-update-icon-cache -q -t /usr/share/icons/hicolor 2>/dev/null || true

# --- Packages for the OS layer ------------------------------------------------------
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
  sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
fi
pacman -Sy --needed --noconfirm plymouth zram-generator pacman-contrib arch-install-scripts >/dev/null

# --- Boot splash --------------------------------------------------------------------
# bgrt shows the firmware's logo with a spinner and handles disk passwords.
install -d /etc/plymouth
cat >/etc/plymouth/plymouthd.conf <<'PLY'
[Daemon]
Theme=bgrt
ShowDelay=0
DeviceTimeout=8
PLY

# --- Memory ---------------------------------------------------------------------------
cat >/etc/systemd/zram-generator.conf <<'ZRAM'
# Compressed swap in RAM: faster than disk swap, nothing to set up.
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
ZRAM
cat >/etc/sysctl.d/90-lumen.conf <<'SYSCTL'
# zram works best with eager swapping and no read-ahead.
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
SYSCTL

# Keep three versions of each package: rollbacks reinstall kernels from here.
systemctl enable paccache.timer >/dev/null 2>&1 || true

# --- Snapshots ------------------------------------------------------------------------
if [[ "$(findmnt -no FSTYPE /)" == btrfs ]]; then
  pacman -S --needed --noconfirm snapper snap-pac >/dev/null
  if [[ ! -f /etc/snapper/configs/root ]]; then
    # snapper wants to create /.snapshots itself; Lumen OS mounts the @snapshots
    # subvolume there instead, so step aside while the config is created.
    if mountpoint -q /.snapshots; then
      umount /.snapshots
      rmdir /.snapshots
      snapper --no-dbus -c root create-config /
      btrfs subvolume delete /.snapshots >/dev/null
      mkdir /.snapshots
      mount /.snapshots
    else
      snapper --no-dbus -c root create-config /
    fi
  fi
  snapper --no-dbus -c root set-config \
    ALLOW_GROUPS=wheel SYNC_ACL=yes \
    TIMELINE_CREATE=no NUMBER_LIMIT=30 NUMBER_LIMIT_IMPORTANT=10 \
    NUMBER_CLEANUP=yes
  chmod 750 /.snapshots
  chown :wheel /.snapshots
  systemctl enable snapper-cleanup.timer >/dev/null 2>&1 || true
  echo "Snapshots: on (snapper + snap-pac)"
else
  echo "Snapshots: skipped (root filesystem is not btrfs)"
fi

echo "Lumen OS system layer applied."
