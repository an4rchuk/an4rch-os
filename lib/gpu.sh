# shellcheck shell=bash
# Graphics cards and which driver suits them. Shared by install.sh and
# anarch-drivers. Source it; nothing runs on its own.

# gpus — "VENDOR:DEVICE<TAB>description" for every graphics card (PCI IDs in hex).
gpus() {
  lspci -nn 2>/dev/null | grep -Ei 'vga|3d controller|display' |
    sed -nE 's/^[0-9a-f:.]+ [^:]+: (.*) \[([0-9a-f]{4}):([0-9a-f]{4})\].*$/\2:\3\t\1/p'
}

# nvidia_driver DEVICE_ID — the NVIDIA driver for a card, by its PCI device ID:
#   open     Turing and newer (GTX 16xx, RTX 20xx and up): NVIDIA's open modules
#   580xx    Maxwell, Pascal, Volta (GTX 750–10xx, Titan V): the 580 legacy driver
#   470xx    Kepler (GTX 600/700): the 470 legacy driver
#   nouveau  anything older: the open-source driver
nvidia_driver() {
  local id=$((16#${1:-0}))
  if ((id >= 0x1e00)); then echo open
  elif ((id >= 0x1340)); then echo 580xx
  elif ((id >= 0x0fc0)); then echo 470xx
  else echo nouveau
  fi
}

# nvidia_packages DRIVER — the packages for it (the legacy ones are in the AUR).
nvidia_packages() {
  case "$1" in
    open) echo "nvidia-open-dkms nvidia-utils libva-nvidia-driver egl-wayland" ;;
    580xx) echo "nvidia-580xx-dkms nvidia-580xx-utils libva-nvidia-driver egl-wayland" ;;
    470xx) echo "nvidia-470xx-dkms nvidia-470xx-utils egl-wayland" ;;
    *) echo "" ;;
  esac
}
