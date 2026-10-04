#!/usr/bin/env bash
# Build the Lumen OS installer ISO.
#
#   sudo iso/build.sh                 → out/lumen-<date>-x86_64.iso
#   sudo WORK=/var/tmp/lumen iso/build.sh
#
# Needs an Arch Linux host (or the archlinux container) with `archiso`
# installed. The ISO is Arch's official "releng" live image with Lumen's
# installer, branding and a copy of this repository layered on top, so it
# stays in step with upstream archiso automatically.
#
# No Arch machine? Push a tag or run the "iso" GitHub Actions workflow: it
# builds the ISO in an Arch container and attaches it to the run.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="${WORK:-/tmp/lumen-iso}"
out="${OUT:-$root/out}"
releng="${RELENG:-/usr/share/archiso/configs/releng}"
profile="$work/profile"

[[ $EUID -eq 0 ]] || { echo "Run as root (mkarchiso needs it): sudo $0"; exit 1; }
command -v mkarchiso >/dev/null || { echo "Install archiso first: pacman -S archiso"; exit 1; }
[[ -d "$releng" ]] || { echo "releng profile not found at $releng"; exit 1; }

echo "==> Preparing profile in $profile"
rm -rf "$work"
mkdir -p "$work" "$out"
cp -a "$releng" "$profile"

# Our files on top of releng's live system.
cp -a "$root/iso/airootfs/." "$profile/airootfs/"

# Extra packages for the live environment (installer UI and tools), plus
# the same desktop an install gets, so everything on the live desktop's bar
# and menus works: sound, Bluetooth, idle and night light, fonts and so on.
cat "$root/iso/packages.x86_64" >>"$profile/packages.x86_64"
(
  # shellcheck source=../install/packages.sh
  source "$root/install/packages.sh"
  printf '%s\n' "${PKGS_AUDIO[@]}" "${PKGS_DESKTOP[@]}" "${PKGS_TOOLS[@]}" "${PKGS_FONTS[@]}" "${PKGS_LOOK[@]}" \
    bluez bluez-utils bluetui power-profiles-daemon upower playerctl libnotify \
    wiremix pavucontrol network-manager-applet pacman-contrib \
    nautilus gvfs loupe evince gnome-calculator "${PKG_FOR[firefox]}"
) >>"$profile/packages.x86_64"
sort -u -o "$profile/packages.x86_64" "$profile/packages.x86_64"

# A copy of Lumen itself (with git history, so `lumen update` works after
# installing). Build leftovers are left out.
mkdir -p "$profile/airootfs/opt/lumen"
tar -C "$root" --exclude=./out --exclude=./work --exclude='./iso/*.iso' --exclude='__pycache__' -cf - . |
  tar -C "$profile/airootfs/opt/lumen" -xf -
git -C "$profile/airootfs/opt/lumen" remote set-url origin "${LUMEN_REPO:-https://github.com/twil09/lumen-os.git}" 2>/dev/null || true

# Wallpapers for the live desktop and the installer's theme picker, painted
# now so booting stays fast (needs python-pillow on the build host).
if python3 -c 'import PIL' 2>/dev/null; then
  echo "==> Painting wallpapers"
  LUMEN_PATH="$root" python3 "$root/bin/lumen-wallgen" --all --out "$profile/airootfs/opt/lumen-wallpapers" --size 1920x1080 >/dev/null
else
  echo "  (python-pillow not installed: the live desktop will have no wallpapers)"
fi

# The packages an install needs and the prebuilt title bar plugin, so
# installing copies from the stick instead of downloading (LUMEN_OFFLINE=0
# for a small ISO that downloads everything).
if [[ "${LUMEN_OFFLINE:-1}" == 1 ]]; then
  "$root/iso/offline.sh" "$root" "$profile" "$work"
fi

# Identity of the image.
version="$(date +%Y.%m.%d)"
sed -i \
  -e 's/^iso_name=.*/iso_name="lumen"/' \
  -e "s/^iso_label=.*/iso_label=\"LUMEN_\$(date --date=\"@\${SOURCE_DATE_EPOCH:-\$(date +%s)}\" +%Y%m)\"/" \
  -e 's/^iso_publisher=.*/iso_publisher="Lumen OS <https:\/\/github.com\/twil09\/linux>"/' \
  -e 's/^iso_application=.*/iso_application="Lumen OS installer"/' \
  "$profile/profiledef.sh"
# mkarchiso copies airootfs without file modes, so everything that must stay
# executable is listed: our installer, and every executable in Lumen's tree
# (otherwise every lumen-* command fails with "Permission denied").
perms='  ["/usr/local/bin/lumen-os-install"]="0:0:755"\n  ["/usr/local/bin/lumen-rescue"]="0:0:755"\n  ["/usr/local/bin/lumen-live-setup"]="0:0:755"\n  ["/usr/local/bin/lumen-installer"]="0:0:755"'
while IFS= read -r f; do
  perms+="\\n  [\"/opt/lumen/${f#./}\"]=\"0:0:755\""
done < <(cd "$profile/airootfs/opt/lumen" && find . -path ./.git -prune -o -type f -perm -u+x -print | sort)
sed -i "s|^file_permissions=(|file_permissions=(\\n$perms|" "$profile/profiledef.sh"

# zstd squashes faster than xz and barely differs here: most of the image is
# already-compressed packages.
sed -i "s/^airootfs_image_tool_options=.*/airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')/" "$profile/profiledef.sh"

# Boot menu branding.
find "$profile/efiboot" "$profile/syslinux" "$profile/grub" -type f \( -name '*.conf' -o -name '*.cfg' \) \
  -exec sed -i -e 's/Arch Linux install medium/Lumen OS installer/g' -e 's/Arch Linux/Lumen OS/g' {} +
[[ -f "$root/iso/splash.png" ]] && cp "$root/iso/splash.png" "$profile/syslinux/splash.png"

# Run from the stick rather than copying the (large) image into memory first.
# (Network boot entries keep copying: there's no stick to run from.)
find "$profile/efiboot" "$profile/syslinux" "$profile/grub" -type f \( -name '*.conf' -o -name '*.cfg' \) ! -name '*pxe*' \
  -exec sed -i 's/archisobasedir=/copytoram=n archisobasedir=/' {} +

# The default entry boots the live desktop with the graphical installer; a
# second entry runs the text-mode installer instead (lumen.text=1).
for entry in "$profile"/efiboot/loader/entries/*.conf; do
  case "$entry" in *speech* | *memtest* | *shell* | *accessib*) continue ;; esac
  [[ -f "$entry" ]] || continue
  text="${entry%.conf}-text.conf"
  sed -e 's/^title .*/& (text mode)/' -e 's/^options .*/& lumen.text=1/' "$entry" >"$text"
  break
done

echo "==> Building (this takes a while)"
mkarchiso -v -w "$work/build" -o "$out" "$profile"

iso=$(ls -t "$out"/lumen-*.iso | head -n1)
(cd "$out" && sha256sum "$(basename "$iso")" >"$(basename "$iso").sha256")
echo
echo "✓ $iso"
echo "  Write it to a USB stick with Impression, Ventoy, or:"
echo "  sudo dd if=$iso of=/dev/sdX bs=4M status=progress oflag=sync"
echo "  (version $version)"
