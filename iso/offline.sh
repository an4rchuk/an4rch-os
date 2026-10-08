#!/usr/bin/env bash
# Called by build.sh. Puts what an install needs on the ISO, so installing
# copies from the USB stick instead of downloading:
#
#   /opt/lumen-repo     every package an install uses (with dependencies),
#                       plus yay and the cursor theme prebuilt from the AUR,
#                       as a pacman repository ("lumen-offline")
#   /usr/lib/lumen/hyprbars.so   the title bar plugin, compiled for the
#                       Hyprland in the repository (stamp: /var/lib/lumen)
#
# The installer puts lumen-offline first in pacman's list while it installs,
# so packages come from the stick; anything else (another browser, gaming) is
# downloaded as before. The live system is built from the same repository,
# so it runs the same versions (and can use the prebuilt plugin too).
#
#   iso/offline.sh ROOT PROFILE WORK
#
# LUMEN_STRICT=1 makes a failed plugin build fail the ISO build (CI).
set -euo pipefail

root="$1" profile="$2" work="$3"
repo="$profile/airootfs/opt/lumen-repo"
builder="$work/builder"
dbpath="$work/offline-db"
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=install/packages.sh
source "$root/install/packages.sh"

mkdir -p "$repo" "$dbpath"

# --- 1. The packages ------------------------------------------------------------
# Everything anarch-os-install and install.sh install by default, for any CPU
# and GPU, plus the build tools the title bars need on a Hyprland update.
# From install/distro.sh: plymouth zram-generator pacman-contrib
# arch-install-scripts snapper snap-pac.
want=(
  "${PKGS_BASE[@]}" intel-ucode amd-ucode grub
  "${PKGS_AUDIO[@]}" "${PKGS_DESKTOP[@]}" "${PKGS_SYSTEM[@]}" wpa_supplicant
  "${PKGS_TOOLS[@]}" "${PKGS_FONTS[@]}" "${PKGS_LOOK[@]}" "${PKGS_OPTIONAL[@]}"
  "${PKGS_GPU_INTEL[@]}" "${PKGS_GPU_AMD[@]}" "${PKGS_GPU_NVIDIA[@]}" linux-headers linux-lts-headers
  "${PKG_FOR[firefox]}" "${PKG_FOR[ghostty]}" "${PKG_FOR[code]}"
  "${PKGS_TITLEBARS[@]}" "${PKGS_SERVER[@]}" "${PKGS_SERVER_OPTIONAL[@]}" fish bash-completion
  plymouth zram-generator pacman-contrib arch-install-scripts snapper snap-pac
)
pacman --dbpath "$dbpath" --logfile /dev/null -Sy >/dev/null
mapfile -t available < <(pacman --dbpath "$dbpath" -Sql)
declare -A in_repos=()
for p in "${available[@]}"; do in_repos[$p]=1; done
repo_pkgs=() aur_pkgs=()
for p in $(printf '%s\n' "${want[@]}" | sort -u); do
  if [[ -n "${in_repos[$p]:-}" ]]; then repo_pkgs+=("$p"); else aur_pkgs+=("$p"); fi
done
aur_pkgs+=(yay-bin)

echo "==> Offline packages: downloading ${#repo_pkgs[@]} packages with their dependencies"
# A fresh database (dbpath) means nothing counts as installed, so pacman
# fetches every dependency. Audio first in the list so "jack" resolves to
# pipewire-jack, as install.sh does.
# Mirrors sometimes drop connections; files already downloaded stay in the
# cache, so another try only fetches what's missing.
for try in 1 2 3 4; do
  pacman --dbpath "$dbpath" --cachedir "$repo" --logfile /dev/null -Sw --noconfirm \
    pipewire-jack "${repo_pkgs[@]}" >/dev/null && break
  ((try < 4)) || { echo "Downloading the offline packages failed 4 times" >&2; exit 1; }
  echo "==> Download interrupted (try $try of 4); trying again in $((try * 15))s"
  rm -f "$repo"/*.part
  sleep $((try * 15))
done
rm -f "$repo"/*.part
repo-add -q "$repo/lumen-offline.db.tar.gz" "$repo"/*.pkg.tar.zst

# pacman settings that use the repository, and only it.
offline_conf="$work/offline-pacman.conf"
cat >"$offline_conf" <<EOF
[options]
Architecture = auto
CacheDir = $repo/
SigLevel = Optional TrustAll
[lumen-offline]
Server = file://$repo
EOF

# --- 2. A throwaway build system, from the same packages ---------------------------
echo "==> Offline packages: build system for AUR packages and the title bar plugin"
rm -rf "$builder"
mkdir -p "$builder"
pacstrap -C "$offline_conf" -c "$builder" base base-devel git sudo hyprland "${PKGS_TITLEBARS[@]}" >/dev/null
cp /etc/resolv.conf "$builder/etc/resolv.conf"
arch-chroot "$builder" useradd -m lumenbuild
echo 'lumenbuild ALL=(ALL) NOPASSWD: ALL' >"$builder/etc/sudoers.d/lumenbuild"

# AUR packages, built once here instead of on every install.
built_aur=()
for p in "${aur_pkgs[@]}"; do
  echo "  building $p (AUR)"
  if arch-chroot "$builder" runuser -u lumenbuild -- bash -c "
      set -e; cd ~ && rm -rf '$p' && git clone -q --depth 1 'https://aur.archlinux.org/$p.git' && cd '$p' &&
      [[ -f PKGBUILD ]] && makepkg --nodeps --noconfirm >/dev/null 2>&1"; then
    for f in "$builder/home/lumenbuild/$p"/*.pkg.tar.zst; do
      [[ -f "$f" ]] && cp "$f" "$repo/" && built_aur+=("$repo/${f##*/}")
    done
  else
    echo "  (could not build $p; installs will fetch it from the AUR)"
  fi
done
if ((${#built_aur[@]})); then
  repo-add -q "$repo/lumen-offline.db.tar.gz" "${built_aur[@]}"
fi
rm -f "$repo"/*.old

# --- 3. The title bar plugin ----------------------------------------------------------
# Compiled once here; the live system and every install use this copy.
echo "==> Title bars: building the hyprbars plugin for $(arch-chroot "$builder" pacman -Q hyprland)"
install -D -m755 "$root/bin/anarch-hyprbars-build" "$builder/usr/local/bin/anarch-hyprbars-build"
if arch-chroot "$builder" /usr/local/bin/anarch-hyprbars-build /root/hyprbars.so >"$work/hyprbars.log" 2>&1; then
  install -D -m755 "$builder/root/hyprbars.so" "$profile/airootfs/usr/lib/lumen/hyprbars.so"
  arch-chroot "$builder" pacman -Q hyprland | awk '{print $2}' |
    install -D -m644 /dev/stdin "$profile/airootfs/var/lib/lumen/hyprbars-hyprland"
  echo "  ✓ $(grep -m1 'building hyprbars' "$work/hyprbars.log")"
else
  echo "  ✗ the plugin didn't build; installs will try themselves. Last lines:"
  tail -n 40 "$work/hyprbars.log" | sed 's/^/    /'
  [[ "${LUMEN_STRICT:-0}" == 1 ]] && exit 1
fi

# --- 4. The live system uses the same versions ---------------------------------------
sed -i "0,/^\[core\]/s||[lumen-offline]\nSigLevel = Optional TrustAll\nServer = file://$repo\n\n[core]|" "$profile/pacman.conf"

rm -rf "$builder" "$dbpath"
echo "  ✓ $(find "$repo" -name '*.pkg.tar.zst' | wc -l) packages, $(du -sh "$repo" | cut -f1)"
