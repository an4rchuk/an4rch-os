#!/usr/bin/env bash
# An4rch installer — turns a fresh Arch Linux install into the An4rch desktop.
#
#   ./install.sh                 interactive install
#   ./install.sh --yes           accept every default (unattended)
#   ./install.sh --configs-only  refresh configs/theme without touching packages
#
# Options:
#   --browser NAME     firefox (default), chromium, brave, zen-browser
#   --terminal NAME    ghostty (default), alacritty, kitty
#   --editor NAME      code (default), zed, nvim
#   --theme NAME       starting theme (default: an4rch)
#   --gaming           also install the gaming stack (Steam, Proton tools, …)
#   --game             the Game edition: gaming, and start straight into Steam's
#                      Game Mode (like a Steam Deck)
#   --shell NAME       zsh (default), bash or fish
#   --apps ID,ID…      extra apps from the App Store's list (apps/lumen-store/catalog.json)
#   --server           no desktop: the system, SSH, the firewall and An4rch's tools
#   --distro           apply the An4rch OS system layer (branding, snapshots,
#                      boot splash, zram) — used by the An4rch OS ISO installer
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

BROWSER="" TERMINAL_APP="" EDITOR_APP="" THEME="an4rch" SHELL_CHOICE=zsh EXTRA_APPS="" SERVER=0
GREETER=1 AUTOLOGIN=0 CONFIGS_ONLY=0 GAMING=0 GAME=0 DISTRO=0 REBOOT=1 TASKBAR=no TITLEBARS=yes
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
    --game) GAMING=1 GAME=1 ;;
    --shell) SHELL_CHOICE="$2"; shift ;;
    --apps) EXTRA_APPS="$2"; shift ;;
    --server) SERVER=1 GREETER=0 ;;
    --distro) DISTRO=1 ;;
    --no-reboot) REBOOT=0 ;;
    --configs-only) CONFIGS_ONLY=1 ;;
    --verbose) export LUMEN_VERBOSE=1 ;;
    -h | --help) sed -n '2,25s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)"; exit 1 ;;
  esac
  shift
done

# The login shell's own packages (bash itself is always there).
case "$SHELL_CHOICE" in
  zsh) SHELL_PKGS=() ;;
  bash) SHELL_PKGS=(bash-completion) ;;
  fish) SHELL_PKGS=(fish) ;;
  *) echo "Unknown shell: $SHELL_CHOICE (zsh, bash or fish)"; exit 1 ;;
esac

FIRST_INSTALL=1
[[ -f "$HOME/.config/lumen/.installed" ]] && FIRST_INSTALL=0

# --- 1. Preflight ---------------------------------------------------------------
preflight() {
  step "Checking this computer"
  [[ -f /etc/arch-release ]] || fail "An4rch needs Arch Linux (or an Arch-based distro)."
  [[ $EUID -ne 0 ]] || fail "Run the installer as your normal user, not root. It uses sudo when needed."
  command -v sudo >/dev/null || fail "sudo is required: as root, run 'pacman -S sudo' and add yourself to the wheel group."
  ok "Arch Linux, user $USER"

  info "An4rch needs administrator rights to install packages."
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
    if ((online)); then
      ok "Internet connection"
    elif [[ "${LUMEN_OFFLINE:-0}" == 1 ]]; then
      # An4rch OS installing from its USB stick: every package is on the stick.
      ok "No internet: installing from the USB stick"
    else
      fail "No internet connection. Connect first (for Wi-Fi on a fresh install: iwctl)."
    fi
    local free
    free=$(df -Pk / | awk 'NR==2 {print int($4/1024/1024)}')
    ((free >= 6)) || fail "Only ${free} GB free on /. An4rch needs about 6 GB."
    ok "${free} GB free"
  fi

  local cpu_arch
  cpu_arch=$(uname -m)
  [[ "$cpu_arch" == x86_64 || "$cpu_arch" == aarch64 ]] || warn "Untested CPU architecture: $cpu_arch"

  if [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]] && [[ "${XDG_CURRENT_DESKTOP:-}" != *Hyprland* ]]; then
    warn "You're running another desktop (${XDG_CURRENT_DESKTOP:-unknown}). It stays installed; pick An4rch at the login screen."
  fi
}

# --- 2. Choices -------------------------------------------------------------------
choose_apps() {
  step "Choosing your apps"
  if ((SERVER)); then
    BROWSER="${BROWSER:-firefox}" TERMINAL_APP="${TERMINAL_APP:-ghostty}" EDITOR_APP="${EDITOR_APP:-nvim}"
    ok "Server: no desktop apps · shell: $SHELL_CHOICE"
    return 0
  fi
  [[ -n "$BROWSER" ]] || ask_choice BROWSER "Web browser" firefox firefox chromium brave zen-browser
  [[ -n "$TERMINAL_APP" ]] || ask_choice TERMINAL_APP "Terminal" ghostty ghostty alacritty kitty
  [[ -n "$EDITOR_APP" ]] || ask_choice EDITOR_APP "Code editor" code code zed nvim
  ok "Browser: $BROWSER · Terminal: $TERMINAL_APP · Editor: $EDITOR_APP · Shell: $SHELL_CHOICE"
  [[ "$THEME" == lumen ]] && THEME=an4rch  # renamed in 1.1.0
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

  # The An4rch OS USB stick carries yay prebuilt; elsewhere it's built from the AUR.
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
  # By PCI vendor ID (8086 Intel, 1002 AMD, 10de NVIDIA): matching vendor
  # names misfires ("ati" is in "Corporation").
  local gpus
  gpus=$(lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display' || true)
  GPU_PKGS=()
  HAS_INTEL=0 HAS_AMD=0 HAS_NVIDIA=0 OTHER_GPU=0 LEGACY_NVIDIA=0
  grep -q '\[8086:' <<<"$gpus" && HAS_INTEL=1
  grep -q '\[1002:' <<<"$gpus" && HAS_AMD=1
  grep -q '\[10de:' <<<"$gpus" && HAS_NVIDIA=1
  # NVIDIA's driver while installing only for cards its open modules support
  # (GTX 16xx / RTX 20xx and newer). Older cards run on nouveau until
  # `anarch drivers install` adds their legacy driver (from the AUR).
  if ((HAS_NVIDIA)) && [[ "${LUMEN_GPU:-}" != nvidia ]]; then
    source "$LUMEN_PATH/lib/gpu.sh"
    local id open=0
    for id in $(gpus | awk -F'\t' '$1 ~ /^10de:/ {sub(/^10de:/, "", $1); print $1}'); do
      [[ "$(nvidia_driver "$id")" == open ]] && open=1
    done
    ((open)) || { HAS_NVIDIA=0; LEGACY_NVIDIA=1; }
  fi
  grep -vqE '\[(8086|1002|10de):' <<<"$gpus" && OTHER_GPU=1
  # Tests (lumen.gpu=nvidia): set up NVIDIA's driver on a machine without one.
  [[ "${LUMEN_GPU:-}" == nvidia ]] && HAS_NVIDIA=1
  ((HAS_INTEL)) && GPU_PKGS+=("${PKGS_GPU_INTEL[@]}")
  ((HAS_AMD)) && GPU_PKGS+=("${PKGS_GPU_AMD[@]}")
  if ((HAS_NVIDIA)); then
    GPU_PKGS+=("${PKGS_GPU_NVIDIA[@]}")
    # DKMS needs headers for whichever kernels are installed.
    local k
    for k in linux linux-lts linux-zen linux-hardened; do
      pacman -Qq "$k" >/dev/null 2>&1 && GPU_PKGS+=("$k-headers")
    done
  fi
  # NVIDIA drives the screen itself only when it's the only GPU; on hybrid
  # laptops (Intel/AMD + NVIDIA) the other GPU does, and NVIDIA-only
  # settings would break apps there.
  NVIDIA_ONLY=0
  ((HAS_NVIDIA && !HAS_INTEL && !HAS_AMD && !OTHER_GPU)) && NVIDIA_ONLY=1
  [[ ${#GPU_PKGS[@]} -gt 0 ]] || GPU_PKGS=(mesa)
  return 0
}

# install_extra_apps — the apps ticked in the installer, by their App Store
# ids: each app tries its sources in the App Store's order (Arch
# repositories, then the AUR, then Flathub) until one works, so an AUR
# build that fails still gets the app from Flathub. Never fatal.
install_extra_apps() {
  local id srcs src kind pkg got done_ids=() skipped=()
  # attempt CMD… — quietly, the output to the log; true when it worked.
  attempt() { printf 'TRY: %s\n' "$*" >>"$LOG"; "$@" >>"$LOG" 2>&1; }
  while IFS=$'\t' read -r id srcs; do
    [[ -n "$id" ]] || continue
    info "App: $id"
    got=0
    for src in $srcs; do
      kind=${src%%:*} pkg=${src#*:}
      case "$kind" in
        pacman) attempt sudo pacman -S --needed --noconfirm "$pkg" ;;
        aur) [[ "${LUMEN_OFFLINE:-0}" != 1 ]] && command -v yay >/dev/null &&
          attempt yay -S --needed --noconfirm --answerdiff None --answerclean None --removemake "$pkg" ;;
        flatpak)
          [[ "${LUMEN_OFFLINE:-0}" != 1 ]] && command -v flatpak >/dev/null &&
            attempt sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &&
            attempt sudo flatpak install -y --noninteractive flathub "$pkg" ;;
        *) false ;;
      esac && { got=1; break; }
      printf 'APP %s: %s %s did not install\n' "$id" "$kind" "$pkg" >>"$LOG"
    done
    ((got)) && done_ids+=("$id") || skipped+=("$id")
  done < <(python3 - "$LUMEN_PATH/apps/lumen-store/catalog.json" "$EXTRA_APPS" <<'PY'
import json, subprocess, sys
apps = {a["id"]: a for a in json.load(open(sys.argv[1]))["apps"]}
for want in filter(None, sys.argv[2].split(",")):
    srcs = apps.get(want, {}).get("sources", [])
    # Repositories first (when the package is there), then the AUR, then Flathub.
    order = [s for s in srcs if s["type"] == "pacman" and
             subprocess.run(["pacman", "-Si", s["id"]], capture_output=True).returncode == 0]
    order += [s for s in srcs if s["type"] == "aur"] + [s for s in srcs if s["type"] == "flatpak"]
    print(want + "\t" + " ".join(f"{s['type']}:{s['id']}" for s in order))
PY
)
  ((${#done_ids[@]})) && ok "Extra apps: ${done_ids[*]}"
  ((${#skipped[@]})) && warn "Not installed now (add them from the App Store later): ${skipped[*]}"
  return 0
}

install_packages() {
  if ((SERVER)); then
    step "Installing the system tools"
    pkg_install REQUIRED "${PKGS_SERVER[@]}" "${SHELL_PKGS[@]}"
    pkg_install OPTIONAL "${PKGS_SERVER_OPTIONAL[@]}"
    step "Installing your apps and tools"
    ok "Server: nothing else to install"
    return 0
  fi
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
  ((HAS_NVIDIA)) && info "NVIDIA graphics: installed NVIDIA's open kernel modules."
  ((LEGACY_NVIDIA)) && info "Older NVIDIA graphics: using the open-source driver for now. For NVIDIA's own (legacy) driver, run: anarch drivers install"

  step "Installing your apps and tools"
  pkg_install OPTIONAL "${PKG_FOR[$BROWSER]:-$BROWSER}" "${PKG_FOR[$TERMINAL_APP]:-$TERMINAL_APP}" "${PKG_FOR[$EDITOR_APP]:-$EDITOR_APP}"
  pkg_install OPTIONAL "${PKGS_OPTIONAL[@]}" "${SHELL_PKGS[@]}"
  [[ -n "$EXTRA_APPS" ]] && install_extra_apps

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
      warn "$home_path exists and isn't this checkout; An4rch commands will use that copy"
    fi
  fi
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$LUMEN_PATH/config/"}"
    case "$rel" in
      zsh/zshrc) place "$f" "$HOME/.zshrc" ;;
      zsh/zprofile) place "$f" "$HOME/.zprofile" ;;
      # bash and fish settings only for those who chose them.
      bash/bashrc) if [[ $SHELL_CHOICE == bash ]]; then place "$f" "$HOME/.bashrc"; fi ;;
      bash/bash_profile) if [[ $SHELL_CHOICE == bash ]]; then place "$f" "$HOME/.bash_profile"; fi ;;
      fish/*) if [[ $SHELL_CHOICE == fish ]]; then place "$f" "$HOME/.config/$rel"; fi ;;
      # A server has no desktop to configure.
      *) if ((!SERVER)); then place "$f" "$HOME/.config/$rel"; fi ;;
    esac
  done < <(find "$LUMEN_PATH/config" -type f -print0)
  mkdir -p "$HOME/.config/lumen"
  if ((SERVER)); then echo server; else echo desktop; fi >"$HOME/.config/lumen/edition"
  if ((SERVER)); then
    ok "Shell settings ($SHELL_CHOICE)"
    cat "$LUMEN_PATH/VERSION" >"$HOME/.config/lumen/.installed" 2>/dev/null || date >"$HOME/.config/lumen/.installed"
    return 0
  fi
  ok "Configs in ~/.config (hypr, waybar, fuzzel, mako, ghostty, …)"
  # "Remove hidden data" in the file manager's right-click menu, and the daily health check.
  "$LUMEN_PATH/bin/anarch-scrub" setup >/dev/null 2>&1 || true
  "$LUMEN_PATH/bin/anarch-health" timer >/dev/null 2>&1 || true

  # Launchers and icons for An4rch's own apps (Start, App Store, Welcome, …).
  local data="${XDG_DATA_HOME:-$HOME/.local/share}"
  mkdir -p "$data/applications" "$data/icons/hicolor/scalable/apps"
  cp "$LUMEN_PATH"/share/applications/*.desktop "$data/applications/"
  cp "$LUMEN_PATH"/share/icons/hicolor/scalable/apps/*.svg "$data/icons/hicolor/scalable/apps/"
  update-desktop-database -q "$data/applications" 2>/dev/null || true
  gtk-update-icon-cache -q -t "$data/icons/hicolor" 2>/dev/null || true
  ok "App Store, Start menu and Welcome launchers"
  "$LUMEN_PATH/bin/anarch-session" autostart

  mkdir -p "$HOME/.config/lumen"
  local settings="$HOME/.config/lumen/settings.conf"
  if [[ ! -f "$settings" ]]; then
    cat >"$settings" <<EOF
# An4rch settings. Change apps here or with: An4rch menu → Setup → Default apps.
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
    ((NVIDIA_ONLY)) && ! grep -q LIBVA_DRIVER_NAME "$HOME/.config/uwsm/env" 2>/dev/null && cat >>"$HOME/.config/uwsm/env" <<'EOF'

# NVIDIA (added by the An4rch installer: NVIDIA is the only GPU)
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export NVD_BACKEND=direct
EOF
    printf 'options nvidia_drm modeset=1 fbdev=1\n' | sudo tee /etc/modprobe.d/lumen-nvidia.conf >/dev/null
    if ((NVIDIA_ONLY)); then ok "NVIDIA environment and kernel mode setting"; else ok "NVIDIA kernel mode setting (hybrid graphics: the other GPU drives the screen)"; fi
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
  if ((SERVER)); then
    run "Enabling NetworkManager, SSH and time sync" sudo systemctl enable NetworkManager sshd systemd-timesyncd fstrim.timer
    # Reachable over SSH; everything else stays closed.
    if command -v ufw >/dev/null; then
      try "Turning on the firewall (SSH allowed)" bash -c '
        sudo sed -i -e "s/^DEFAULT_INPUT_POLICY=.*/DEFAULT_INPUT_POLICY=\"DROP\"/" -e "s/^DEFAULT_OUTPUT_POLICY=.*/DEFAULT_OUTPUT_POLICY=\"ACCEPT\"/" /etc/default/ufw &&
        sudo sed -i "s/^ENABLED=.*/ENABLED=yes/" /etc/ufw/ufw.conf &&
        for v in "" 6; do
          f=/etc/ufw/user$v.rules
          grep -q -- "--dport 22 -j ACCEPT" "$f" && continue
          any=0.0.0.0/0; [[ -n $v ]] && any=::/0
          # Inside the RULES section: anything after COMMIT stops ufw loading.
          sudo sed -i "/^### RULES ###\$/a ### tuple ### allow tcp 22 $any any $any in\n-A ufw$v-user-input -p tcp --dport 22 -j ACCEPT\n" "$f"
        done &&
        grep -q -- "--dport 22" /etc/ufw/user.rules &&
        sudo systemctl enable ufw'
    fi
    set_login_shell
    if [[ $DISTRO -eq 1 ]]; then
      run "Applying the An4rch OS system layer (branding, snapshots, zram)" sudo LUMEN_PATH="$LUMEN_PATH" bash "$LUMEN_PATH/install/distro.sh"
    fi
    return 0
  fi
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

  # Power button opens An4rch's power menu instead of shutting down at once;
  # holding it still powers off.
  sudo mkdir -p /etc/systemd/logind.conf.d
  printf '[Login]\nHandlePowerKey=ignore\nHandlePowerKeyLongPress=poweroff\n' |
    sudo tee /etc/systemd/logind.conf.d/10-lumen.conf >/dev/null
  ok "Power button shows the power menu (hold to force off)"

  # Polkit agent runs as a user service in the graphical session.
  systemctl --user enable hyprpolkitagent.service >/dev/null 2>&1 ||
    sudo systemctl --global enable hyprpolkitagent.service >/dev/null 2>&1 || true

  set_login_shell

  if [[ $DISTRO -eq 1 ]]; then
    run "Applying the An4rch OS system layer (branding, snapshots, boot splash, zram)" sudo LUMEN_PATH="$LUMEN_PATH" bash "$LUMEN_PATH/install/distro.sh"
  fi

  if [[ $GAMING -eq 1 ]] || { [[ -z "${LUMEN_YES:-}" ]] && ask_yes "Set up gaming too? (Steam, Proton tools, GameMode, MangoHud)" n; }; then
    # Steam and the 32-bit libraries come from the internet: offline, or if a
    # download fails, the desktop still installs and gaming is set up later.
    if [[ "${LUMEN_OFFLINE:-0}" == 1 ]]; then
      warn "No internet: gaming (Steam, Proton tools…) is set up later with: anarch gaming install"
    elif ! (run "Installing the gaming stack" env LUMEN_YES=1 "$LUMEN_PATH/bin/anarch-gaming" install); then
      warn "Gaming couldn't be set up right now; run 'anarch gaming install' later (the desktop is fine)"
    fi
  fi

  if [[ $GREETER -eq 1 ]]; then
    setup_greeter
    # The Game edition: Steam's Game Mode at start-up (needs the internet once).
    if [[ $GAME -eq 1 ]]; then
      if [[ "${LUMEN_OFFLINE:-0}" != 1 ]] && run "Setting up Steam Game Mode" env LUMEN_YES=1 "$LUMEN_PATH/bin/anarch-gaming" game-mode on &&
        run "Starting in Game Mode" env LUMEN_YES=1 "$LUMEN_PATH/bin/anarch-gaming" game-mode boot on; then
        :
      else
        warn "Game Mode couldn't be set up now; once online: anarch gaming game-mode on, then anarch gaming game-mode boot on"
      fi
    fi
  else
    info "No login screen: logging in on the first console starts An4rch (see ~/.zprofile)."
  fi
}

set_login_shell() {
  local want="/usr/bin/$SHELL_CHOICE"
  [[ -x "$want" ]] || want="/bin/$SHELL_CHOICE"
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$want" ]]; then
    run "Making $SHELL_CHOICE your shell" sudo chsh -s "$want" "$USER"
  fi
}

setup_greeter() {
  local dm other=""
  for dm in gdm sddm lightdm ly lxdm; do
    systemctl is-enabled -q "$dm" 2>/dev/null && other="$dm"
  done
  if [[ -n "$other" ]]; then
    if ask_yes "Replace the $other login screen with An4rch's (greetd)?" n; then
      run "Disabling $other" sudo systemctl disable "$other"
    else
      info "Keeping $other. Choose \"Hyprland (uwsm-managed)\" when you log in."
      return
    fi
  fi

  # The graphical login screen in An4rch's theme (text login as a fallback).
  run "Setting up the login screen" "$LUMEN_PATH/bin/anarch-login" setup
  if [[ $AUTOLOGIN -eq 1 ]] && ! grep -q '^\[initial_session\]' /etc/greetd/config.toml; then
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
  if ((SERVER)); then
    step "Styling"
    ok "Server: nothing to style"
    return 0
  fi
  if [[ "$TITLEBARS" == yes ]]; then
    # shellcheck disable=SC2024  # the log is the user's
    try "Window title bars (the hyprbars plugin)" "$LUMEN_PATH/bin/anarch-titlebars" setup </dev/null
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

  # Wallpapers first (switching theme picks one). The other themes get
  # theirs the first time they're picked.
  if python3 -c 'import PIL' 2>/dev/null; then
    try "Painting wallpapers for the theme" python3 "$LUMEN_PATH/bin/anarch-wallgen" --theme "$THEME" --out "${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/lumen"
  else
    warn "python-pillow missing: run 'anarch-wallpaper generate' later"
  fi

  local theme_out
  if theme_out=$("$LUMEN_PATH/bin/anarch-theme" set "$THEME" 2>&1); then
    ok "Theme: $THEME"
  else
    warn "Theme could not be applied: $(tail -n 1 <<<"$theme_out")"
  fi
  printf '%s\n' "$theme_out" >>"$LOG"
}

# --- 8. Done ----------------------------------------------------------------------
finish() {
  step "Finishing up"
  bash "$LUMEN_PATH/install/migrate.sh" --mark-all >>"$LOG" 2>&1 || true

  printf '\n  %s%s✓ An4rch is installed.%s\n\n' "$BOLD" "$GREEN" "$RESET"
  if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    printf '  %sNotes:%s\n' "$YELLOW" "$RESET"
    printf '    • %s\n' "${WARNINGS[@]}"
    printf '\n'
  fi
  if ((SERVER)); then
    cat <<EOF
  ${BOLD}First steps${RESET}
    ${ACCENT}anarch help${RESET}      every command
    ${ACCENT}anarch update${RESET}    update the system (with a snapshot first)
    ${ACCENT}anarch doctor${RESET}    check everything is healthy
    SSH is on (the firewall allows it): ssh $USER@$(cat /etc/hostname 2>/dev/null || hostname)

  Log: ${DIM}$LOG${RESET}

EOF
    return 0
  fi
  cat <<EOF
  ${BOLD}First steps${RESET}
    ${ACCENT}SUPER + SPACE${RESET}        open apps
    ${ACCENT}SUPER + ALT + SPACE${RESET}  the An4rch menu: Wi-Fi, themes, capture, settings…
    ${ACCENT}SUPER + /${RESET}            every key binding
    ${ACCENT}SUPER + F1${RESET}           the manual (or: anarch manual)

  Log: ${DIM}$LOG${RESET}

EOF
  if [[ $REBOOT -eq 1 && -z "${WAYLAND_DISPLAY:-}" ]] && ask_yes "Restart now to start An4rch?" y; then
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
