# shellcheck shell=bash
# shellcheck disable=SC2034  # arrays are read by install.sh
# Package sets. REQUIRED packages stop the install if missing; everything else
# is best-effort and reported at the end.

# The base system lumen-os-install puts on the disk (plus the CPU's microcode).
PKGS_BASE=(
  base linux linux-lts linux-firmware sof-firmware btrfs-progs cryptsetup
  sudo git base-devel networkmanager wpa_supplicant plymouth zram-generator
  snapper snap-pac efibootmgr arch-install-scripts pciutils man-db nano reflector
)

# Sound (installed first, see install_packages).
PKGS_AUDIO=(
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
)

# The compositor and its family.
PKGS_DESKTOP=(
  hyprland hyprlock hypridle hyprpicker hyprsunset hyprpolkitagent
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  uwsm libnewt
  qt5-wayland qt6-wayland
  waybar fuzzel mako swaybg
  python-gobject gtk4 libadwaita
  polkit gnome-keyring libsecret
  xdg-user-dirs xdg-utils
)

# Sound, network, Bluetooth, power.
PKGS_SYSTEM=(
  networkmanager bluez bluez-utils
  power-profiles-daemon upower brightnessctl
  playerctl
  greetd greetd-tuigreet
  ufw
  git base-devel curl
)

# Everyday command-line tools Lumen relies on.
PKGS_TOOLS=(
  zsh zsh-autosuggestions zsh-syntax-highlighting starship
  fzf ripgrep fd bat eza zoxide jq
  btop fastfetch
  grim slurp wl-clipboard cliphist
  python python-pillow
)

PKGS_FONTS=(
  inter-font ttf-jetbrains-mono-nerd
  noto-fonts noto-fonts-emoji noto-fonts-cjk
)

PKGS_LOOK=(
  adw-gtk-theme papirus-icon-theme
)

# Best-effort extras: nice to have, never fatal.
PKGS_OPTIONAL=(
  man-db less unzip zip 7zip wget rsync
  satty wf-recorder
  tesseract tesseract-data-eng
  libqalculate imagemagick
  pavucontrol wiremix bluetui
  network-manager-applet
  sound-theme-freedesktop
  glow yazi neovim
  nautilus gvfs gvfs-mtp file-roller sushi
  loupe mpv evince gnome-calculator gnome-disk-utility
  flatpak fwupd pacman-contrib pciutils
  gtk4-layer-shell
  bibata-cursor-theme-bin
)

# Apps chosen during install (see choose_apps in install.sh).
declare -A PKG_FOR=(
  [ghostty]=ghostty
  [alacritty]=alacritty
  [kitty]=kitty
  [firefox]=firefox
  [chromium]=chromium
  [brave]=brave-bin
  [zen-browser]=zen-browser-bin
  [code]=code
  [zed]=zed
  [nvim]=neovim
)

# GPU drivers by vendor.
PKGS_GPU_INTEL=(mesa vulkan-intel intel-media-driver)
PKGS_GPU_AMD=(mesa vulkan-radeon)
PKGS_GPU_NVIDIA=(nvidia-open-dkms nvidia-utils libva-nvidia-driver egl-wayland)

# --- Optional features, installed on demand -----------------------------------
# Kept here so CI checks every name against the repos and the AUR.

# lumen-tune (CachyOS-style performance)
PKGS_TUNE_SCX=(scx-scheds)
PKGS_TUNE_ZEN=(linux-zen linux-zen-headers)
PKGS_TUNE_MIRRORS=(reflector)

# lumen-extras (Bazzite-style one-command recipes)
PKGS_X_OPENRGB=(openrgb)
PKGS_X_LACT=(lact)
PKGS_X_DISTROBOX=(distrobox podman)
PKGS_X_WAYDROID=(waydroid)
PKGS_X_VIRT=(qemu-desktop libvirt virt-manager dnsmasq edk2-ovmf swtpm)
PKGS_X_TAILSCALE=(tailscale)
PKGS_X_HANDHELD=(hhd)
PKGS_X_CONTROLLERS=(game-devices-udev)

# lumen-dev (development environment)
PKGS_DEV_BASE=(mise github-cli lazygit)
PKGS_DEV_DOCKER=(docker docker-compose docker-buildx lazydocker)

# lumen-titlebars: hyprpm builds the hyprbars plugin against Hyprland's
# headers, which needs Hyprland's build tools.
PKGS_TITLEBARS=(cmake meson cpio pkgconf gcc git glaze glslang hyprwayland-scanner hyprland-protocols wayland-protocols xorgproto)
