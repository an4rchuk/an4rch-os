#!/usr/bin/env bash
# Chromebook support: the keyboard's top row and the touchpad. Run as root;
# safe to run again; does nothing on other computers.
#
#   install/chromebook.sh          detect, then set up keyd and the touchpad drivers
#   install/chromebook.sh --check  exit 0 on a Chromebook (for other scripts)
#
# Chromebooks' top-row keys send F1–F10 (or, on newer "Vivaldi" keyboards, a
# per-model layout the firmware describes in function_row_physmap), there's
# no Delete key, and the touchpad sits on I2C behind drivers that aren't
# always loaded. keyd turns the top row into back / forward / refresh /
# fullscreen / overview / brightness / volume (Search + top row gives F1–F12,
# Search + Backspace is Delete), and the touchpad drivers load at boot.
set -euo pipefail

is_chromebook() {
  local d=/sys/class/dmi/id
  [[ "$(cat "$d/sys_vendor" 2>/dev/null)" == Google ]] && return 0
  grep -qi chromebook "$d/product_family" "$d/product_name" 2>/dev/null && return 0
  [[ -e /dev/cros_ec || -d /sys/class/chromeos ]] && return 0
  return 1
}

if [[ "${1:-}" == --check ]]; then
  is_chromebook
  exit
fi
is_chromebook || exit 0
echo "==> Chromebook detected: setting up the keyboard and touchpad"

# --- Touchpad (and touchscreen) drivers -------------------------------------------------
cat >/etc/modules-load.d/lumen-chromebook.conf <<'EOF'
# Chromebook touchpads and touchscreens sit on I2C (Lumen OS).
i2c_hid_acpi
elan_i2c
cyapa
atmel_mxt_ts
chromeos_laptop
EOF
for m in i2c_hid_acpi elan_i2c cyapa atmel_mxt_ts chromeos_laptop; do
  modprobe -q "$m" 2>/dev/null || true
done

# --- Keyboard: keyd ---------------------------------------------------------------------
if ! command -v keyd >/dev/null; then
  pacman -S --needed --noconfirm keyd >/dev/null 2>&1 || {
    echo "  keyd isn't installed (no internet?); the top row keeps sending F1–F10"
    exit 0
  }
fi

# Vivaldi keyboards list the top row's scancodes; older ones send plain F1–F10
# in the classic Chromebook order.
declare -A action=(
  [EA]=back [E9]=forward [E7]=refresh [91]=f11 [92]=leftmeta [93]=sysrq
  [94]=brightnessdown [95]=brightnessup [97]=kbdillumdown [98]=kbdillumup
  [A0]=mute [AE]=volumedown [B0]=volumeup [9A]=playpause [9B]=micmute
  [90]=previoussong [99]=nextsong [9E]=kbdillumtoggle
)
classic=(back forward refresh f11 leftmeta brightnessdown brightnessup mute volumedown volumeup)
physmap=$(cat /sys/bus/platform/devices/i8042/serio0/function_row_physmap 2>/dev/null ||
  cat /sys/bus/platform/devices/*/function_row_physmap 2>/dev/null | head -n1 || true)

keys=()
if [[ -n "$physmap" ]]; then
  for code in $physmap; do
    code=${code^^}
    keys+=("${action[$code]:-}")
  done
else
  keys=("${classic[@]}")
fi

install -d /etc/keyd
{
  echo "# Chromebook keyboard (Lumen OS, install/chromebook.sh). Search + top row = F1-F12."
  echo "[ids]"
  echo "*"
  echo
  echo "[main]"
  for i in "${!keys[@]}"; do
    [[ -n "${keys[$i]}" ]] && echo "f$((i + 1)) = ${keys[$i]}"
  done
  echo
  echo "[meta]"
  for i in "${!keys[@]}"; do echo "f$((i + 1)) = f$((i + 1))"; done
  echo "backspace = delete"
} >/etc/keyd/chromebook.conf

systemctl enable --now keyd >/dev/null 2>&1 || systemctl enable keyd >/dev/null 2>&1 || true
keyd reload >/dev/null 2>&1 || true
echo "  top row: ${keys[*]}"
