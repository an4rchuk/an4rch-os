#!/usr/bin/env bash
# Lumen installer — turns a fresh Arch Linux install into the Lumen desktop.
#
#   ./install.sh                 interactive install
#   ./install.sh --yes           accept every default (unattended)
#   ./install.sh --configs-only  refresh configs/theme without touching packages
#
# Options:
#   --browser NAME     firefox (default), chromium, brave, zen-browser
#   --terminal NAME    ghostty (default), alacritty, kitty
#   --editor NAME      code (default), zed, nvim
#   --theme NAME       starting theme (default: lumen)
#   --gaming           also install the gaming stack (Steam, Proton tools, …)
#   --distro           apply the Lumen OS system layer (branding, snapshots,
#                      boot splash, zram) — used by the Lumen OS ISO installer
#   --no-reboot        don't offer to restart at the end
#   --no-greeter       don't set up the greetd login screen
#   --autologin        log straight in (sensible with full-disk encryption)
#   --taskbar          add a taskbar along the bottom of the screen
#   --no-titlebars     no title bars or window buttons (borderless tiling look)
#   --verbose          show command output instead of spinners
#
# Safe to re-run: every step is idempotent, and files you've changed are
# never overwritten without a backup in ~/.config/lumen-backup-<date>/.
set -euo pipefail

LUMEN_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LUMEN_PATH
# Copies that lost file modes (zip downloads, some image builders) would make
# every lumen-* command fail with "Permission denied": restore them.
chmod +x "$LUMEN_PATH"/bin/* "$LUMEN_PATH"/install.sh "$LUMEN_PATH"/boot.sh 2>/dev/null || true
source "$LUMEN_PATH/install/lib.sh"
source "$LUMEN_PATH/install/packages.sh"

BROWSER="" TERMINAL_APP="" EDITOR_APP="" THEME="lumen"
GREETER=1 AUTOLOGIN=0 CONFIGS_ONLY=0 GAMING=0 DISTRO=0 REBOOT=1 TASKBAR=no TITLEBARS=yes
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y | --yes) export LUMEN_YES=1 ;;
    --browser) BROWSER="$2"; shift ;;
    --terminal) TERMINAL_APP="$2"; shift ;;
    --editor) EDITOR_APP="$2"; shift ;;
    --theme) THEME="$2"; shift ;;
    --no-greeter) GREETER=0 ;;
    --autologin) AUTOLOGIN=1 ;;
    --taskbar) TASKBAR=yes ;;
    --no-titlebars) TITLEBARS=no ;;
    --gaming) GAMING=1 ;;
    --distro) DISTRO=1 ;;
    --no-reboot) REBOOT=0 ;;
    --configs-only) CONFIGS_ONLY=1 ;;
    --verbose) export LUMEN_VERBOSE=1 ;;
    -h | --help) sed -n '2,22s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)"; exit 1 ;;
  esac
  shift
done

FIRST_INSTALL=1
[[ -f "$HOME/.config/lumen/.installed" ]] && FIRST_INSTALL=0

# --- 1. Preflight ---------------------------------------------------------------
preflight() {
  step "Checking this computer"
  [[ -f /etc/arch-release ]] || fail "Lumen needs Arch Linux (or an Arch-based distro)."
  [[ $EUID -ne 0 ]] || fail "Run the installer as your normal user, not root. It uses sudo when needed."
  command -v sudo >/dev/null || fail "sudo is required: as root, run 'pacman -S sudo' and add yourself to the wheel group."
  ok "Arch Linux, user $USER"

  info "Lumen needs administrator rights to install packages."
  # sudo -n first: with password-less sudo, -v can still prompt (verifypw=all).
  sudo -n true 2>/dev/null || sudo -v || fail "sudo authentication failed"
  # Keep sudo alive for the whole install.
  while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &

  if [[ $CONFIGS_ONLY -eq 0 ]]; then
    # Only headers, a few tries, two hosts: a slow moment on the network
    # shouldn't read as "offline".
    local online=0 host
    for _ in 1 2 3; do
      for host in https://geo.mirror.pkgbuild.com https://archlinux.org; do
        curl -fsSI --max-time 15 -o /dev/null "$host" 2>>"$LOG" && { online=1; break 2; }
      done
      sleep 3
    done
    ((online)) || fail "No internet connection. Connect first (for Wi-Fi on a fresh install: iwctl)."
    ok "Internet connection"
    local free
    free=$(df -Pk / | awk 'NR==2 {print int($4/1024/1024)}')
    ((free >= 6)) || fail "Only ${free} GB free on /. Lumen needs about 6 GB."
    ok "${free} GB free"
  fi

  local cpu_arch
  cpu_arch=$(uname -m)
  [[ "$cpu_arch" == x86_64 || "$cpu_arch" == aarch64 ]] || warn "Untested CPU architecture: $cpu_arch"

  if [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] && [[ "${XDG_CURRENT_DESKTOP:-}" != *Hyprland* ]]; then
    warn "You're running another desktop (${XDG_CURRENT_DESKTOP:-unknown}). It stays installed; pick Lumen at the login screen."
  fi
}

# --- 2. Choices -------------------------------------------------------------------
choose_apps() {
  step "Choosing your apps"
  [[ -n "$BROWSER" ]] || ask_choice BROWSER "Web browser" firefox firefox chromium brave zen-browser
  [[ -n "$TERMINAL_APP" ]] || ask_choice TERMINAL_APP "Terminal" ghostty ghostty alacritty kitty
  [[ -n "$EDITOR_APP" ]] || ask_choice EDITOR_APP "Code editor" code code zed nvim
  ok "Browser: $BROWSER · Terminal: $TERMINAL_APP · Editor: $EDITOR_APP"
  [[ -d "$LUMEN_PATH/themes/$THEME" ]] || fail "Unknown theme '$THEME'"
}

# --- 3. Package manager -------------------------------------------------------------
setup_pacman() {
  step "Preparing the package manager"
  local conf=/etc/pacman.conf
  if grep -q '^#Color' "$conf" || grep -q '^#ParallelDownloads' "$conf"; then
    run "Turning on colour output and parallel downloads" \
      sudo sed -i -e 's/^#Color/Color/' -e 's/^#ParallelDownloads.*/ParallelDownloads = 8/' -e 's/^#VerbosePkgLists/VerbosePkgLists/' "$conf"
  fi
  run "Updating the system" sudo pacman -Syu --noconfirm

  # The Lumen OS USB stick carries yay prebuilt; elsewhere it's built from the AUR.
  if ! command -v yay >/dev/null && pacman -Si yay-bin >/dev/null 2>&1; then
    pkg_install OPTIONAL yay-bin
  fi
  if ! command -v yay >/dev/null; then
    pkg_install REQUIRED git base-devel
    local tmp
    tmp=$(mktemp -d)
    run "Fetching the yay AUR helper" git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
    run "Building yay" bash -c "cd '$tmp/yay-bin' && makepkg -si --noconfirm"
    rm -rf "$tmp"
  fi
  ok "yay $(yay --version | awk '{print $2}')"
}

# --- 4. Packages ------------------------------------------------------------------
detect_gpu() {
  local gpus
  gpus=$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true)
  GPU_PKGS=()
  grep -qi intel <<<"$gpus" && GPU_PKGS+=("${PKGS_GPU_INTEL[@]}")
  grep -qiE 'amd|ati|radeon' <<<"$gpus" && GPU_PKGS+=("${PKGS_GPU_AMD[@]}")
  HAS_NVIDIA=0
  if grep -qi nvidia <<<"$gpus"; then
    HAS_NVIDIA=1
    GPU_PKGS+=("${PKGS_GPU_NVIDIA[@]}" linux-headers)
    # DKMS needs headers for whichever kernels are installed.
    pacman -Qq linux-lts >/dev/null 2>&1 && GPU_PKGS+=(linux-lts-headers)
    pacman -Qq linux-zen >/dev/null 2>&1 && GPU_PKGS+=(linux-zen-headers)
  fi
  [[ ${#GPU_PKGS[@]} -gt 0 ]] || GPU_PKGS=(mesa)
}

install_packages() {
  step "Installing the desktop"
  # Audio first: media libraries depend on "jack", and if PipeWire's JACK
  # isn't installed yet pacman picks jack2, which later conflicts with
  # pipewire-jack (unattended installs can't answer that question).
  pkg_install REQUIRED "${PKGS_AUDIO[@]}"
  pkg_install REQUIRED "${PKGS_DESKTOP[@]}"
  pkg_install REQUIRED "${PKGS_SYSTEM[@]}" wpa_supplicant
  pkg_install REQUIRED "${PKGS_TOOLS[@]}"
  pkg_install REQUIRED "${PKGS_FONTS[@]}"
  pkg_install OPTIONAL "${PKGS_LOOK[@]}"

  detect_gpu
  pkg_install OPTIONAL "${GPU_PKGS[@]}"
  ((HAS_NVIDIA)) && info "NVIDIA GPU found: installed the open kernel modules. Older (pre-Turing) cards need the drivers listed on wiki.archlinux.org/title/NVIDIA."

  step "Installing your apps and tools"
  pkg_install OPTIONAL "${PKG_FOR[$BROWSER]:-$BROWSER}" "${PKG_FOR[$TERMINAL_APP]:-$TERMINAL_APP}" "${PKG_FOR[$EDITOR_APP]:-$EDITOR_APP}"
  pkg_install OPTIONAL "${PKGS_OPTIONAL[@]}"

  # Waybar releases up to 0.15.0 speak Hyprland's old IPC, so clicking a
  # workspace does nothing under the Lua config. Use the git build until a
  # newer release lands in the repos.
  local wv
  wv=$(pacman -Q waybar 2>/dev/null | awk '{print $2}')
  if [[ -n "$wv" && "$(vercmp "${wv%-*}" 0.15.0)" -le 0 ]]; then
    info "Waybar $wv can't switch workspaces with Hyprland's Lua config; the fix is only in waybar-git."
    if [[ -n "${LUMEN_YES:-}" ]]; then
      # Unattended: replacing waybar needs a yes to a package conflict, which
      # --noconfirm answers "no". Leave it for later.
      warn "Workspace buttons in the bar won't respond to clicks until you run: yay -S waybar-git (keys work)."
    elif ask_yes "Build waybar-git from the AUR now? (a few minutes, answer y to replace waybar)" y; then
      yay -S --needed waybar-git || warn "waybar-git didn't build; keeping waybar $wv"
    else
      warn "Keeping waybar $wv: workspace buttons in the bar won't respond to clicks (keys still work)."
    fi
  fi
}

# --- 5. Configuration ------------------------------------------------------------
# User-editable files: installed on first run (backing up what was there),
# and on later runs only when missing — your edits are never replaced.
place() {
  local src="$1" dest="$2"
  if [[ $FIRST_INSTALL -eq 1 || ! -e "$dest" ]]; then
    copy_config "$src" "$dest"
  fi
}

install_configs() {
  step "Writing configuration"
  # Configs refer to ~/.local/share/lumen; make sure this checkout is there.
  local home_path="$HOME/.local/share/lumen"
  if [[ "$LUMEN_PATH" != "$(realpath -m "$home_path")" ]]; then
    if [[ -L "$home_path" || ! -e "$home_path" ]]; then
      mkdir -p "$(dirname "$home_path")"
      ln -sfn "$LUMEN_PATH" "$home_path"
      ok "Linked ~/.local/share/lumen → $LUMEN_PATH"
    else
      warn "$home_path exists and isn't this checkout; Lumen commands will use that copy"
    fi
  fi
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$LUMEN_PATH/config/"}"
    case "$rel" in
      zsh/zshrc) place "$f" "$HOME/.zshrc" ;;
      zsh/zprofile) place "$f" "$HOME/.zprofile" ;;
      *) place "$f" "$HOME/.config/$rel" ;;
    esac
  done < <(find "$LUMEN_PATH/config" -type f -print0)
  ok "Configs in ~/.config (hypr, waybar, fuzzel, mako, ghostty, …)"

  # Launchers and icons for Lumen's own apps (Start, App Store, Welcome, …).
  local data="${XDG_DATA_HOME:-$HOME/.local/share}"
  mkdir -p "$data/applications" "$data/icons/hicolor/scalable/apps"
  cp "$LUMEN_PATH"/share/applications/*.desktop "$data/applications/"
  cp "$LUMEN_PATH"/share/icons/hicolor/scalable/apps/*.svg "$data/icons/hicolor/scalable/apps/"
  update-desktop-database -q "$data/applications" 2>/dev/null || true
  gtk-update-icon-cache -q -t "$data/icons/hicolor" 2>/dev/null || true
  ok "App Store, Start menu and Welcome launchers"
  "$LUMEN_PATH/bin/lumen-session" autostart

  mkdir -p "$HOME/.config/lumen"
  local settings="$HOME/.config/lumen/settings.conf"
  if [[ ! -f "$settings" ]]; then
    cat >"$settings" <<EOF
# Lumen settings. Change apps here or with: Lumen menu → Setup → Default apps.
LUMEN_TERMINAL=$TERMINAL_APP
LUMEN_BROWSER=$( [[ "$BROWSER" == brave ]] && echo brave || echo "$BROWSER")
LUMEN_EDITOR=$EDITOR_APP
LUMEN_FILES=nautilus

# Where captures go.
LUMEN_SCREENSHOT_DIR="\$HOME/Pictures/Screenshots"
LUMEN_RECORDING_DIR="\$HOME/Videos/Recordings"

# Night light colour temperature (Kelvin; lower is warmer).
LUMEN_NIGHTLIGHT_TEMP=4300

# Suspend after 30 idle minutes: always | battery | never
LUMEN_IDLE_SUSPEND=always

# Title bars with close/maximise/minimise buttons: yes | no
LUMEN_TITLEBARS=$TITLEBARS

# Taskbar along the bottom of the screen: yes | no
LUMEN_TASKBAR=$TASKBAR
EOF
  fi
  ok "Settings in ~/.config/lumen/settings.conf"

  if ((HAS_NVIDIA)); then
    grep -q LIBVA_DRIVER_NAME "$HOME/.config/uwsm/env" 2>/dev/null || cat >>"$HOME/.config/uwsm/env" <<'EOF'

# NVIDIA (added by the Lumen installer)
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export NVD_BACKEND=direct
EOF
    printf 'options nvidia_drm modeset=1 fbdev=1\n' | sudo tee /etc/modprobe.d/lumen-nvidia.conf >/dev/null
    ok "NVIDIA environment and kernel mode setting"
  fi

  if [[ -d "$BACKUP_DIR" ]]; then
    info "Your previous configs were saved in ${BACKUP_DIR/#$HOME/\~}"
  fi
  # From now on, re-running the installer leaves existing configs alone.
  cat "$LUMEN_PATH/VERSION" >"$HOME/.config/lumen/.installed" 2>/dev/null || date >"$HOME/.config/lumen/.installed"
}

# --- 6. System services -----------------------------------------------------------
setup_system() {
  step "Setting up system services"

  # One network manager only. Others are disabled for the next boot (not
  # stopped now, so an install over Wi-Fi or SSH keeps its connection).
  local s
  # Only units installed on this system: inside the ISO installer's chroot,
  # `systemctl is-enabled` can report the live USB's iwd instead.
  for s in iwd systemd-networkd dhcpcd netctl; do
    [[ -e "/usr/lib/systemd/system/$s.service" || -e "/etc/systemd/system/$s.service" ]] || continue
    if systemctl is-enabled -q "$s" 2>/dev/null; then
      try "Handing networking over from $s to NetworkManager" sudo systemctl disable "$s"
    fi
  done
  run "Enabling NetworkManager, Bluetooth, power profiles and time sync" \
    sudo systemctl enable NetworkManager bluetooth power-profiles-daemon systemd-timesyncd fstrim.timer
  # Without a running user manager (the ISO installer's chroot), enable them
  # for all users instead; same result at the next login.
  # shellcheck disable=SC2024  # the log is the user's; only systemctl needs root
  systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service >>"$LOG" 2>&1 ||
    sudo systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service >>"$LOG" 2>&1 ||
    warn "Could not enable PipeWire for your user; run: systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber"

  # Firewall: block incoming connections, allow everything outgoing.
  if command -v ufw >/dev/null; then
    [[ -n "${SSH_CONNECTION:-}" ]] && run "Keeping SSH reachable" sudo ufw allow ssh
    if booted; then
      try "Turning on the firewall" bash -c 'sudo ufw default deny incoming >/dev/null && sudo ufw default allow outgoing >/dev/null && sudo ufw --force enable && sudo systemctl enable ufw'
    else
      # Not booted (installer chroot): write the settings; ufw applies them at boot.
      try "Turning on the firewall (applies at first boot)" bash -c '
        sudo sed -i -e "s/^DEFAULT_INPUT_POLICY=.*/DEFAULT_INPUT_POLICY=\"DROP\"/" -e "s/^DEFAULT_OUTPUT_POLICY=.*/DEFAULT_OUTPUT_POLICY=\"ACCEPT\"/" /etc/default/ufw &&
        sudo sed -i "s/^ENABLED=.*/ENABLED=yes/" /etc/ufw/ufw.conf &&
        sudo systemctl enable ufw'
    fi
  fi

  # Power button opens Lumen's power menu instead of shutting down at once;
  # holding it still powers off.
  sudo mkdir -p /etc/systemd/logind.conf.d
  printf '[Login]\nHandlePowerKey=ignore\nHandlePowerKeyLongPress=poweroff\n' |
    sudo tee /etc/systemd/logind.conf.d/10-lumen.conf >/dev/null
  ok "Power button shows the power menu (hold to force off)"

  # Polkit agent runs as a user service in the graphical session.
  systemctl --user enable hyprpolkitagent.service >/dev/null 2>&1 ||
    sudo systemctl --global enable hyprpolkitagent.service >/dev/null 2>&1 || true

  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != */zsh ]]; then
    run "Making zsh your shell" sudo chsh -s /usr/bin/zsh "$USER"
  fi

  if [[ $DISTRO -eq 1 ]]; then
    run "Applying the Lumen OS system layer (branding, snapshots, boot splash, zram)" sudo LUMEN_PATH="$LUMEN_PATH" bash "$LUMEN_PATH/install/distro.sh"
  fi

  if [[ $GAMING -eq 1 ]] || { [[ -z "${LUMEN_YES:-}" ]] && ask_yes "Set up gaming too? (Steam, Proton tools, GameMode, MangoHud)" n; }; then
    run "Installing the gaming stack" env LUMEN_YES=1 "$LUMEN_PATH/bin/lumen-gaming" install
  fi

  if [[ $GREETER -eq 1 ]]; then
    setup_greeter
  else
    info "No login screen: logging in on the first console starts Lumen (see ~/.zprofile)."
  fi
}

setup_greeter() {
  local dm other=""
  for dm in gdm sddm lightdm ly lxdm; do
    systemctl is-enabled -q "$dm" 2>/dev/null && other="$dm"
  done
  if [[ -n "$other" ]]; then
    if ask_yes "Replace the $other login screen with Lumen's (greetd)?" n; then
      run "Disabling $other" sudo systemctl disable "$other"
    else
      info "Keeping $other. Choose \"Hyprland (uwsm-managed)\" when you log in."
      return
    fi
  fi

  sudo mkdir -p /etc/greetd
  sudo tee /etc/greetd/config.toml >/dev/null <<'EOF'
# Lumen login screen (greetd + tuigreet).
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --time-format '%A %d %B  ·  %H:%M' --remember --asterisks --greeting 'Welcome to Lumen' --cmd 'uwsm start -- hyprland.desktop'"
user = "greeter"
EOF
  if [[ $AUTOLOGIN -eq 1 ]]; then
    printf '\n[initial_session]\ncommand = "uwsm start -- hyprland.desktop"\nuser = "%s"\n' "$USER" | sudo tee -a /etc/greetd/config.toml >/dev/null
    ok "Auto-login enabled"
  fi

  # Unlock the keyring with the login password.
  if [[ -f /etc/pam.d/greetd ]] && ! grep -q pam_gnome_keyring /etc/pam.d/greetd; then
    sudo sed -i -e '/^auth.*include/a auth       optional     pam_gnome_keyring.so' \
      -e '/^session.*include/a session    optional     pam_gnome_keyring.so auto_start' /etc/pam.d/greetd
  fi
  run "Enabling the login screen" sudo systemctl enable greetd
}

# --- 7. Look and feel --------------------------------------------------------------
setup_look() {
  if [[ "$TITLEBARS" == yes ]]; then
    # shellcheck disable=SC2024  # the log is the user's
    try "Window title bars (the hyprbars plugin)" "$LUMEN_PATH/bin/lumen-titlebars" setup </dev/null
  fi

  step "Styling"
  xdg-user-dirs-update 2>/dev/null || true
  mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Pictures/Wallpapers" "$HOME/Videos/Recordings"

  # dconf needs a session bus; installs from a console don't have one yet.
  local gs=(gsettings)
  [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && gs=(dbus-run-session -- gsettings)
  {
    "${gs[@]}" set org.gnome.desktop.interface font-name 'Inter 11'
    "${gs[@]}" set org.gnome.desktop.interface document-font-name 'Inter 11'
    "${gs[@]}" set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 11'
    "${gs[@]}" set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic'
    "${gs[@]}" set org.gnome.desktop.interface cursor-size 24
    "${gs[@]}" set org.gnome.desktop.wm.preferences button-layout ':'
    "${gs[@]}" set org.gnome.desktop.interface font-antialiasing 'rgba'
  } >>"$LOG" 2>&1 || warn "Could not apply GTK settings (they'll apply on first login)"
  ok "Fonts, cursor and GTK preferences"

  # Default apps for links, folders, images, video and PDFs.
  local browser_desktop
  browser_desktop=$(find /usr/share/applications -maxdepth 1 -iname "*${BROWSER%%-*}*.desktop" 2>/dev/null | head -n1)
  {
    [[ -n "$browser_desktop" ]] && xdg-mime default "$(basename "$browser_desktop")" x-scheme-handler/http x-scheme-handler/https text/html
    xdg-mime default org.gnome.Nautilus.desktop inode/directory
    xdg-mime default org.gnome.Loupe.desktop image/png image/jpeg image/webp image/gif image/svg+xml
    xdg-mime default mpv.desktop video/mp4 video/x-matroska video/webm audio/mpeg audio/flac
    xdg-mime default org.gnome.Evince.desktop application/pdf
  } >>"$LOG" 2>&1 || true
  ok "Default apps"

  local theme_out
  if theme_out=$("$LUMEN_PATH/bin/lumen-theme" set "$THEME" 2>&1); then
    ok "Theme: $THEME"
  else
    warn "Theme could not be applied: $(tail -n 1 <<<"$theme_out")"
  fi
  printf '%s\n' "$theme_out" >>"$LOG"

  if python3 -c 'import PIL' 2>/dev/null; then
    try "Painting wallpapers for every theme" python3 "$LUMEN_PATH/bin/lumen-wallgen" --all --out "${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/lumen"
    "$LUMEN_PATH/bin/lumen-wallpaper" theme >>"$LOG" 2>&1 || true
  else
    warn "python-pillow missing: run 'lumen-wallpaper generate' later"
  fi
}

# --- 8. Done ----------------------------------------------------------------------
finish() {
  step "Finishing up"
  bash "$LUMEN_PATH/install/migrate.sh" --mark-all >>"$LOG" 2>&1 || true

  printf '\n  %s%s✓ Lumen is installed.%s\n\n' "$BOLD" "$GREEN" "$RESET"
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '  %sNotes:%s\n' "$YELLOW" "$RESET"
    printf '    • %s\n' "${WARNINGS[@]}"
    printf '\n'
  fi
  cat <<EOF
  ${BOLD}First steps${RESET}
    ${ACCENT}SUPER + SPACE${RESET}        open apps
    ${ACCENT}SUPER + ALT + SPACE${RESET}  the Lumen menu: Wi-Fi, themes, capture, settings…
    ${ACCENT}SUPER + /${RESET}            every key binding
    ${ACCENT}SUPER + F1${RESET}           the manual (or: lumen manual)

  Log: ${DIM}$LOG${RESET}

EOF
  if [[ $REBOOT -eq 1 && -z "${WAYLAND_DISPLAY:-}" ]] && ask_yes "Restart now to start Lumen?" y; then
    sudo systemctl reboot
  fi
}

banner
if [[ $CONFIGS_ONLY -eq 1 ]]; then
  STEP_TOTAL=3
  BROWSER="${BROWSER:-firefox}" TERMINAL_APP="${TERMINAL_APP:-ghostty}" EDITOR_APP="${EDITOR_APP:-code}"
  HAS_NVIDIA=0
  preflight
  install_configs
  setup_look
  exit 0
fi

STEP_TOTAL=9
preflight
choose_apps
setup_pacman
install_packages
install_configs
setup_system
setup_look
finish
