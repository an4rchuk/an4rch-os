#!/usr/bin/env bash
# Lumen OS system layer. Run as root (the ISO installer runs it inside the new
# system; `install.sh --distro` runs it on an existing Arch install).
#
#   - brands the OS (os-release, console greeting, fastfetch logo) and keeps
#     the branding across `filesystem` package upgrades
#   - boot splash (Plymouth), compressed RAM swap (zram), multilib for games
#   - performance defaults: sysctls, I/O schedulers, NTSYNC, quick shutdowns
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
HOME_URL="https://github.com/an4rchuk/lumen-os"
DOCUMENTATION_URL="https://github.com/an4rchuk/lumen-os/tree/HEAD/docs"
SUPPORT_URL="https://github.com/an4rchuk/lumen-os/issues"
BUG_REPORT_URL="https://github.com/an4rchuk/lumen-os/issues"
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
bash "$LUMEN_PATH/install/enable-multilib.sh"
pacman -S --needed --noconfirm plymouth zram-generator pacman-contrib arch-install-scripts >/dev/null

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

# --- Performance (CachyOS-style defaults) ------------------------------------------------
# Low-risk tweaks only; the opt-in ones (sched-ext schedulers, the zen kernel,
# mirror ranking) are in `lumen tune`.
cat >/etc/sysctl.d/91-lumen-performance.conf <<'SYSCTL'
# Keep directory and inode caches longer: snappier file browsing.
vm.vfs_cache_pressure = 50
# Write dirty pages out in smaller, steadier batches (no multi-second stalls
# when copying big files to slow USB sticks).
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864
vm.dirty_writeback_centisecs = 1500
# Games: the split-lock "penalty" slows down some Windows games under Proton,
# and many games need lots of memory maps.
kernel.split_lock_mitigate = 0
vm.max_map_count = 2147483642
# Desktops don't need the NMI watchdog; turning it off saves a little power.
kernel.nmi_watchdog = 0
# Faster networking under load.
net.core.netdev_max_backlog = 4096
net.ipv4.tcp_fastopen = 3
SYSCTL

# Best I/O scheduler per disk type: none for NVMe, mq-deadline for SATA SSDs,
# BFQ for spinning disks.
cat >/etc/udev/rules.d/60-lumen-ioschedulers.rules <<'UDEV'
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
UDEV

# NTSYNC: Windows-style sync primitives in the kernel (Linux 6.14+), used by
# Wine and Proton for smoother games. Harmless when unused.
echo ntsync >/etc/modules-load.d/lumen-ntsync.conf
echo 'KERNEL=="ntsync", MODE="0644"' >/etc/udev/rules.d/60-lumen-ntsync.rules

# Don't wait 90 s for a stuck service at shutdown, and keep the journal small.
install -d /etc/systemd/system.conf.d /etc/systemd/user.conf.d /etc/systemd/journald.conf.d
printf '[Manager]\nDefaultTimeoutStopSec=15s\n' >/etc/systemd/system.conf.d/90-lumen.conf
printf '[Manager]\nDefaultTimeoutStopSec=15s\n' >/etc/systemd/user.conf.d/90-lumen.conf
printf '[Journal]\nSystemMaxUse=200M\n' >/etc/systemd/journald.conf.d/90-lumen.conf

# Out of memory: instead of the whole computer freezing, systemd-oomd closes
# the app that is using up memory (Fedora's defaults).
install -d "/etc/systemd/system/-.slice.d" /etc/systemd/system/user@.service.d
printf '[Slice]\nManagedOOMSwap=kill\n' >"/etc/systemd/system/-.slice.d/90-lumen-oomd.conf"
printf '[Service]\nManagedOOMMemoryPressure=kill\nManagedOOMMemoryPressureLimit=50%%\n' \
  >/etc/systemd/system/user@.service.d/90-lumen-oomd.conf
systemctl enable systemd-oomd >/dev/null 2>&1 || true

# A kernel update no longer breaks USB sticks etc. until the next restart.
bash "$LUMEN_PATH/install/keep-modules.sh"

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
