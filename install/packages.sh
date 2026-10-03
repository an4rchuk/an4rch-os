# shellcheck shell=bash
# shellcheck disable=SC2034  # arrays are read by install.sh
# Package sets. REQUIRED packages stop the install if missing; everything else
# is best-effort and reported at the end.

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
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber
  networkmanager bluez bluez-utils
  power-profiles-daemon upower brightnessctl
  playerctl
  greetd greetd-tuigreet
  ufw
  man-db less unzip zip p7zip wget curl rsync git base-devel
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
PKGS_GPU_AMD=(mesa vulkan-radeon libva-mesa-driver)
PKGS_GPU_NVIDIA=(nvidia-open-dkms nvidia-utils libva-nvidia-driver egl-wayland)
