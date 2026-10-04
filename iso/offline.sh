#!/usr/bin/env bash
# Called by build.sh. Puts what an install needs on the ISO, so installing
# copies from the USB stick instead of downloading:
#
#   /opt/lumen-repo     every package an install uses (with dependencies),
#                       plus yay and the cursor theme prebuilt from the AUR,
#                       as a pacman repository ("lumen-offline")
#   /opt/lumen-hyprpm   the title bar plugin (hyprbars), already built by
#                       hyprpm for the Hyprland version in the repository
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
hyprpm_out="$profile/airootfs/opt/lumen-hyprpm"
builder="$work/builder"
dbpath="$work/offline-db"
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=install/packages.sh
source "$root/install/packages.sh"

mkdir -p "$repo" "$dbpath"

# --- 1. The packages ------------------------------------------------------------
# Everything lumen-os-install and install.sh install by default, for any CPU
# and GPU, plus the build tools the title bars need on a Hyprland update.
# From install/distro.sh: plymouth zram-generator pacman-contrib
# arch-install-scripts snapper snap-pac.
want=(
  "${PKGS_BASE[@]}" intel-ucode amd-ucode
  "${PKGS_AUDIO[@]}" "${PKGS_DESKTOP[@]}" "${PKGS_SYSTEM[@]}" wpa_supplicant
  "${PKGS_TOOLS[@]}" "${PKGS_FONTS[@]}" "${PKGS_LOOK[@]}" "${PKGS_OPTIONAL[@]}"
  "${PKGS_GPU_INTEL[@]}" "${PKGS_GPU_AMD[@]}" "${PKGS_GPU_NVIDIA[@]}" linux-headers linux-lts-headers
  "${PKG_FOR[firefox]}" "${PKG_FOR[ghostty]}" "${PKG_FOR[code]}"
  "${PKGS_TITLEBARS[@]}"
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
pacman --dbpath "$dbpath" --cachedir "$repo" --logfile /dev/null -Sw --noconfirm \
  pipewire-jack "${repo_pkgs[@]}" >/dev/null
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
for p in "${aur_pkgs[@]}"; do
  echo "  building $p (AUR)"
  if arch-chroot "$builder" runuser -u lumenbuild -- bash -c "
      set -e; cd ~ && rm -rf '$p' && git clone -q --depth 1 'https://aur.archlinux.org/$p.git' && cd '$p' &&
      [[ -f PKGBUILD ]] && makepkg --nodeps --noconfirm >/dev/null 2>&1"; then
    cp "$builder/home/lumenbuild/$p"/*.pkg.tar.zst "$repo/" 2>/dev/null || echo "  (no package file for $p)"
  else
    echo "  (could not build $p; installs will fetch it from the AUR)"
  fi
done
repo-add -q -n "$repo/lumen-offline.db.tar.gz" "$repo"/*.pkg.tar.zst
rm -f "$repo"/*.old

# --- 3. The title bar plugin ----------------------------------------------------------
# hyprpm keeps its build in /var/cache/hyprpm/<user>; the installer moves it
# to the new user's name. It doesn't need Hyprland running: it reads the
# installed version (Hyprland --version-json).
echo "==> Title bars: building the hyprbars plugin for $(arch-chroot "$builder" pacman -Q hyprland)"
if arch-chroot "$builder" runuser -u lumenbuild -- bash -c '
    set -e; cd ~
    hyprpm update
    yes | hyprpm add https://github.com/hyprwm/hyprland-plugins
    hyprpm enable hyprbars
    hyprpm list' >"$work/hyprpm.log" 2>&1 &&
  [[ -f "$builder/var/cache/hyprpm/lumenbuild/hyprland-plugins/hyprbars.so" ]]; then
  mkdir -p "$hyprpm_out"
  tar -C "$builder/var/cache/hyprpm/lumenbuild" -cf "$hyprpm_out/hyprpm.tar" .
  arch-chroot "$builder" pacman -Q hyprland | awk '{print $2}' >"$hyprpm_out/hyprland-version"
  echo "  ✓ built ($(du -sh "$hyprpm_out/hyprpm.tar" | cut -f1))"
else
  echo "  ✗ the plugin didn't build; installs will build it themselves. Last lines:"
  tail -n 40 "$work/hyprpm.log" | sed 's/^/    /'
  [[ "${LUMEN_STRICT:-0}" == 1 ]] && exit 1
fi

# --- 4. The live system uses the same versions ---------------------------------------
sed -i "0,/^\[core\]/s||[lumen-offline]\nSigLevel = Optional TrustAll\nServer = file://$repo\n\n[core]|" "$profile/pacman.conf"

rm -rf "$builder" "$dbpath"
echo "  ✓ $(find "$repo" -name '*.pkg.tar.zst' | wc -l) packages, $(du -sh "$repo" | cut -f1)"
