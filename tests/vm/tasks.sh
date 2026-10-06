#!/bin/bash
# VM test only (installed with lumen.serial=1): use the desktop like a person
# would, as the logged-in user, and report each result on the serial console.
#
# Protocol with the e2e workflow, which watches the serial log:
#   E2E-SHOT name        take a screenshot now (we wait while it does)
#   E2E-KEYS k1 k2 ...   press these keys (QEMU sendkey names)
#   E2E-TYPE text        type this text (lower case, digits, space, - . /)
#   E2E-RESULT name PASS|FAIL detail
#   E2E-DONE
set -uo pipefail
exec >/dev/ttyS0 2>&1

u=$(id -un 1000)
home="/home/$u"
run=/run/user/1000
lumen="$home/.local/share/lumen"
sig=$(ls "$run/hypr" 2>/dev/null | head -n1)
wl=""
for s in "$run"/wayland-[0-9]*; do [[ -S "$s" ]] && { wl="${s##*/}"; break; }; done
pass=0 fail=0

say() { printf '%s\n' "$*"; }
shot() { say "E2E-SHOT $1"; sleep 9; }
keys() { say "E2E-KEYS $*"; sleep 4; }
type_text() { say "E2E-TYPE $1"; sleep $((${#1} / 3 + 4)); }
result() {
  if [[ "$2" == PASS ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); fi
  say "E2E-RESULT $1 $2 ${3:-}"
}

# as_user CMD... — run inside the user's desktop session.
as_user() {
  timeout 120 runuser -u "$u" -- env -i HOME="$home" USER="$u" LOGNAME="$u" SHELL=/bin/zsh \
    XDG_RUNTIME_DIR="$run" WAYLAND_DISPLAY="$wl" HYPRLAND_INSTANCE_SIGNATURE="$sig" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$run/bus" XDG_CURRENT_DESKTOP=Hyprland \
    XDG_SESSION_TYPE=wayland LUMEN_PATH="$lumen" LANG=en_US.UTF-8 \
    PATH="$lumen/bin:$home/.local/bin:/usr/local/bin:/usr/bin" "$@"
}

# task NAME CMD... — run a command, print its output, PASS on exit 0.
task() {
  local name="$1" out rc
  shift
  say "--- task: $name"
  # Output via a file, not $(...): a command may leave a background child
  # (e.g. a clickable notification) holding the pipe open forever.
  out=$(mktemp)
  "$@" >"$out" 2>&1 </dev/null
  rc=$?
  sed 's/\x1b\[[0-9;]*m//g' "$out" | tail -n 40
  rm -f "$out"
  if [[ $rc -eq 0 ]]; then result "$name" PASS; else result "$name" FAIL "exit $rc"; fi
  return $rc
}

# cli NAME CMD... — a command-line task, run in a pseudo-terminal like a
# person typing it (some commands otherwise open their own terminal window).
cli() {
  local name="$1"
  shift
  task "$name" as_user script -qefc "$(printf '%q ' "$@")" /dev/null
}

windows() { as_user hyprctl clients -j 2>/dev/null | jq -r '.[].class' 2>/dev/null; }
count_windows() { windows | grep -Eci -- "$1"; }

# wait_window NAME CLASS-REGEX SECONDS [MIN-COUNT]
wait_window() {
  local name="$1" class="$2" secs="$3" want="${4:-1}" i
  for ((i = 0; i < secs; i++)); do
    if (($(count_windows "$class") >= want)); then
      result "$name" PASS "window '$class' after ${i}s"
      return 0
    fi
    sleep 1
  done
  result "$name" FAIL "no '$class' window after ${secs}s; windows: $(windows | tr '\n' ' ')"
  return 1
}

say "=== LUMEN-E2E-TASKS (user $u, display $wl) ==="
pkill -f lumen_welcome.py
pkill -f lumen_store.py
sleep 2
shot 10-clean-desktop

# --- Health check ---------------------------------------------------------------------
cli "lumen doctor" lumen-doctor

# --- Apps from Lumen's launcher ------------------------------------------------------
as_user lumen-launch terminal
if wait_window "terminal opens (lumen-launch)" 'ghostty|alacritty|kitty' 30; then
  type_text "fastfetch"
  keys ret
  sleep 3
  shot 11-terminal-fastfetch
fi

# --- Themes --------------------------------------------------------------------------
task "theme switch to nord" as_user lumen-theme set nord
if [[ "$(cat "$home/.config/lumen/current/theme.name" 2>/dev/null)" == nord ]]; then
  result "theme files rendered" PASS
else
  result "theme files rendered" FAIL "theme.name is '$(cat "$home/.config/lumen/current/theme.name" 2>/dev/null)'"
fi
sleep 3
shot 12-theme-nord
task "next wallpaper" as_user lumen-wallpaper next

# --- Notifications, reminders, clipboard, screenshots --------------------------------
task "notification" as_user notify-send -a Lumen "Hello from the test" "Notifications work"
sleep 1
shot 13-notification
task "reminder scheduled" as_user lumen-remind 30m "Test reminder"
if as_user lumen-remind list --plain 2>/dev/null | grep -q "Test reminder"; then
  result "reminder listed" PASS
else
  result "reminder listed" FAIL
fi

as_user bash -c 'printf lumen-clip-test | wl-copy'
sleep 2
if as_user cliphist list 2>/dev/null | grep -q lumen-clip-test; then
  result "clipboard history" PASS
else
  result "clipboard history" FAIL "$(as_user cliphist list 2>&1 | head -n 3 | tr '\n' ' ')"
fi

marker=$(mktemp)
sleep 1
task "screenshot (lumen-screenshot screen)" as_user lumen-screenshot screen
sleep 2
if find "$home/Pictures/Screenshots" -name '*.png' -newer "$marker" 2>/dev/null | grep -q .; then
  result "screenshot saved" PASS "$(find "$home/Pictures/Screenshots" -name '*.png' -newer "$marker" | head -n1)"
else
  result "screenshot saved" FAIL "nothing new in ~/Pictures/Screenshots"
fi
rm -f "$marker"

# --- Menus and keyboard ----------------------------------------------------------------
as_user lumen-menu >/dev/null 2>&1 &
sleep 4
if pgrep -x fuzzel >/dev/null; then result "lumen menu opens" PASS; else result "lumen menu opens" FAIL; fi
shot 14-lumen-menu
keys esc
pkill -x fuzzel

before=$(count_windows 'ghostty|alacritty|kitty')
keys meta_l-ret
wait_window "SUPER+Enter opens a terminal" 'ghostty|alacritty|kitty' 20 $((before + 1)) && shot 15-keybind-terminal

keys meta_l
type_text "calc"
shot 16-start-search
keys ret
wait_window "Start search launches Calculator" 'calculator' 30 && shot 17-calculator

# --- Title bars, minimise and the taskbar -------------------------------------------------
if grep -q '^LUMEN_TITLEBARS=no' "$home/.config/lumen/settings.conf" 2>/dev/null; then
  # Title bars turned off when installing: the plugin must not be loaded.
  if as_user hyprctl plugin list 2>/dev/null | grep -q hyprbars; then
    result "title bars off (as chosen)" FAIL "the plugin is loaded"
  else
    result "title bars off (as chosen)" PASS
  fi
elif as_user hyprctl plugin list 2>/dev/null | grep -q hyprbars; then
  result "title bars plugin loaded" PASS
else
  result "title bars plugin loaded" FAIL "$(as_user hyprctl plugin list 2>&1 | head -n 3 | tr '\n' ' ')"
  say "--- title bars diagnostics"
  as_user lumen-titlebars status 2>&1
  say "stamp: $(cat /var/lib/lumen/hyprbars-hyprland 2>&1) installed: $(pacman -Q hyprland 2>&1)"
  ls -la /usr/lib/lumen 2>&1
  say "login load log:"; cat "$home/.local/state/lumen/titlebars.log" 2>&1 | tail -n 20
  say "load now:"; as_user hyprctl plugin load /usr/lib/lumen/hyprbars.so 2>&1 | tail -n 20
  say "install log:"; grep -n -i -A12 'title bars\|hyprbars' /var/log/lumen-os-install.log 2>/dev/null | tail -n 60
fi
shot 17b-titlebars
task "minimise the calculator" as_user lumen-window minimize
sleep 2
if as_user lumen-window list | grep -qi calculator; then result "minimised window is hidden" PASS; else result "minimised window is hidden" FAIL "$(as_user lumen-window list | tr '\n' ' ')"; fi
task "taskbar on" as_user lumen-taskbar on
sleep 4
if pgrep -f '^(/usr/bin/)?waybar -c .*taskbar.jsonc' >/dev/null; then result "taskbar running" PASS; else result "taskbar running" FAIL; fi
shot 17c-taskbar
task "restore the calculator" as_user lumen-window restore
sleep 2
if as_user lumen-window list | grep -qi calculator; then result "restored window is back" FAIL; else result "restored window is back" PASS; fi
shot 17d-restored

# --- Bigger apps -------------------------------------------------------------------------
as_user lumen-store --search "video editor" >/dev/null 2>&1 &
sleep 20
shot 18-store-search
pkill -f lumen_store.py

as_user lumen-launch files
wait_window "file manager opens" 'nautilus' 40 && { sleep 3; shot 19-files; }

as_user lumen-launch monitor
wait_window "Task Manager opens" 'SystemMonitor' 40 && { sleep 3; shot 19b-task-manager; }

as_user lumen-launch browser https://archlinux.org
if wait_window "browser opens" 'firefox|chromium|brave|zen' 90; then
  sleep 15; shot 20-browser
else
  # What went wrong, for the log: the chosen browser, failed apps, processes,
  # and the browser's own output when started directly.
  br=$(sed -n 's/^LUMEN_BROWSER=//p' "$home/.config/lumen/settings.conf" 2>/dev/null)
  say "--- browser diagnostics (LUMEN_BROWSER=$br)"
  tail -n 10 "$home/.local/state/lumen/apps.log" 2>&1
  pgrep -af 'firefox|chromium|chrome|brave' | cut -c1-200
  ls -l "$home/.config/"*-flags.conf 2>&1
  as_user timeout 25 "${br:-firefox}" --version 2>&1 | tail -n 3
  as_user timeout 25 "${br:-firefox}" about:blank 2>&1 | grep -v '^\s*$' | tail -n 25
  shot 20-browser-failed
fi

# --- Command-line tools -------------------------------------------------------------------
cli "lumen help" lumen help
cli "lumen tune status" lumen tune status
cli "lumen extras list" lumen extras list
cli "lumen dev status" lumen dev status
cli "lumen snapshot list" lumen snapshot
cli "lumen theme list" lumen theme list
bat=$(as_user lumen battery 2>&1)
if [[ "$bat" =~ ^(No\ battery|[0-9]+%) ]]; then result "lumen battery" PASS "$bat"; else result "lumen battery" FAIL "${bat:-no output}"; fi
task "audio (wpctl status)" as_user wpctl status
task "firewall active" systemctl is-active ufw
task "NetworkManager online" nmcli -t -f STATE general
task "zram swap" swapon --show
# The keyboard layout picked when installing reaches the desktop (not only the console).
km=$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf 2>/dev/null)
if [[ -n "$km" && "$km" != us ]]; then
  task "keyboard layout ($km) on the desktop" bash -c "! grep -q 'kb_layout  = \"us\"' '$home/.config/hypr/input.lua' && grep -q XkbLayout /etc/X11/xorg.conf.d/00-keyboard.conf"
fi
task "memory protection (systemd-oomd)" systemctl is-active systemd-oomd
task "text editor and camera installed" bash -c 'command -v gnome-text-editor && command -v snapshot'

# --- NVIDIA driver (installed with lumen.gpu=nvidia; this VM has no NVIDIA card) ----------
# Without an NVIDIA card, NVIDIA's libraries must not have been pulled in.
if ! pacman -Q nvidia-open-dkms >/dev/null 2>&1; then
  if pacman -Q nvidia-utils lib32-nvidia-utils 2>/dev/null | grep -q .; then
    result "no NVIDIA libraries without an NVIDIA card" FAIL "$(pacman -Qi nvidia-utils lib32-nvidia-utils 2>/dev/null | grep -E '^(Name|Required By)' | tr '\n' ' ')"
  else
    result "no NVIDIA libraries without an NVIDIA card" PASS
  fi
fi
if pacman -Q nvidia-open-dkms >/dev/null 2>&1; then
  say "--- NVIDIA: $(pacman -Q nvidia-open-dkms nvidia-utils 2>&1 | tr '\n' ' ')"
  say "running kernel: $(uname -r)"
  dkms status 2>&1 | head -n 5
  for k in /usr/lib/modules/*/; do
    kv=$(basename "$k")
    [[ -d "$k/kernel" ]] || continue
    if modinfo -k "$kv" nvidia >/dev/null 2>&1; then result "NVIDIA driver built for $kv" PASS; else result "NVIDIA driver built for $kv" FAIL; fi
  done
  if [[ -f /etc/modprobe.d/lumen-nvidia.conf ]]; then result "NVIDIA kernel mode setting configured" PASS; else result "NVIDIA kernel mode setting configured" FAIL; fi
  # This VM's screen is a virtio GPU, like the Intel/AMD GPU of a hybrid
  # laptop: the NVIDIA-only settings must not be there.
  if grep -q __GLX_VENDOR_LIBRARY_NAME "$home/.config/uwsm/env" 2>/dev/null; then
    result "hybrid graphics: no NVIDIA-only settings" FAIL "$(grep -n nvidia "$home/.config/uwsm/env")"
  else
    result "hybrid graphics: no NVIDIA-only settings" PASS
  fi
fi
case "$(uname -r)" in *lts*) result "running the LTS kernel" PASS "$(uname -r)" ;; esac

# --- Installed alongside Windows ---------------------------------------------------------------
if findmnt -n /efi >/dev/null 2>&1; then
  say "--- dual boot: $(bootctl list --no-pager 2>/dev/null | grep -E 'title:|id:' | tr -s ' ' | tr '\n' ' ')"
  if [[ -f /efi/EFI/Microsoft/Boot/bootmgfw.efi ]]; then result "Windows boot manager kept" PASS; else result "Windows boot manager kept" FAIL; fi
  if bootctl list --no-pager 2>/dev/null | grep -qi 'windows'; then result "boot menu lists Windows" PASS; else result "boot menu lists Windows" FAIL "$(bootctl list --no-pager 2>&1 | head -n 20 | tr '\n' ' ')"; fi
  if grep -q LOCAL /etc/adjtime 2>/dev/null; then result "clock in local time (like Windows)" PASS; else result "clock in local time (like Windows)" FAIL; fi
fi

# --- Settings, the sound panel and the login screen ------------------------------------------
as_user lumen-settings windows >/dev/null 2>&1 &
if wait_window "Settings opens" 'lumen.Settings' 40; then
  sleep 3
  shot 21a-settings
fi
# A change made in Settings reaches Hyprland (desktop.json → desktop.lua → reload).
# Every option changed at once, as someone working through the Settings app would.
as_user bash -c 'mkdir -p ~/.config/lumen && printf "%s\n" "{\"gaps_in\": 9, \"gaps_out\": 6, \"border_size\": 3, \"rounding\": 4, \"inactive_opacity\": 0.9, \"blur\": false, \"shadow\": false, \"animations\": false, \"sensitivity\": -0.3, \"natural_scroll\": false, \"tap_to_click\": false, \"disable_while_typing\": false, \"scroll_factor\": 0.8, \"repeat_delay\": 400, \"repeat_rate\": 30}" > ~/.config/lumen/desktop.json'
task "Settings writes the window config" as_user python3 "$lumen/apps/lumen-settings/lumen_settings.py" --write-desktop
as_user hyprctl reload >/dev/null 2>&1
sleep 2
gaps=$(as_user hyprctl getoption general:gaps_in -j 2>/dev/null | tr -d ' \n')
[[ "$gaps" == *9* ]] || gaps=$(as_user hyprctl repl 'return hl.get_config("general.gaps_in")' 2>/dev/null | tail -n1)
if [[ "$gaps" == *9* ]]; then result "Settings change applied" PASS "$gaps"; else result "Settings change applied" FAIL "${gaps:-no answer}"; fi
errs=$(as_user hyprctl configerrors 2>&1 | grep -v -i -e '^\s*$' -e 'no errors')
if [[ -z "$errs" ]]; then result "no config errors after Settings changes" PASS; else result "no config errors after Settings changes" FAIL "$(tr '\n' ' ' <<<"$errs")"; fi
as_user rm -f "$home/.config/lumen/desktop.json" "$home/.config/lumen/desktop.lua"
as_user hyprctl reload >/dev/null 2>&1
pkill -f lumen_settings.py

as_user lumen-audio >/dev/null 2>&1 &
sleep 6
if as_user hyprctl layers -j 2>/dev/null | grep -q '"lumen-audio"'; then
  result "sound panel opens" PASS
else
  result "sound panel opens" FAIL "$(pgrep -af lumen_audio | head -n 2 | tr '\n' ' ')"
fi
shot 21b-sound-panel
as_user lumen-audio >/dev/null 2>&1
sleep 2

if [[ -x /usr/local/bin/lumen-greeter ]] && grep -q lumen-greeter /etc/greetd/config.toml 2>/dev/null; then
  result "login screen installed" PASS
else
  result "login screen installed" FAIL "$(grep -m1 command /etc/greetd/config.toml 2>&1)"
fi
if [[ -s /var/lib/lumen/login/wallpaper && -s /var/lib/lumen/login/regreet.css ]]; then
  result "login screen has the theme and wallpaper" PASS
else
  result "login screen has the theme and wallpaper" FAIL "$(ls -la /var/lib/lumen/login 2>&1 | tr '\n' ' ')"
fi
as_user lumen-login preview >/dev/null 2>&1
if wait_window "login screen preview" 'regreet' 30; then
  sleep 3
  shot 21c-login-screen
fi
pkill -x regreet

# --- Lock screen ---------------------------------------------------------------------------
pkill -x firefox
pkill -x nautilus
pkill -f gnome-calculator
sleep 2
loginctl lock-sessions
sleep 6
if pgrep -x hyprlock >/dev/null; then result "lock screen" PASS; else result "lock screen" FAIL; fi
shot 21-lock-screen
type_text "lumen"
keys ret
sleep 5
if pgrep -x hyprlock >/dev/null; then result "unlock with password" FAIL; else result "unlock with password" PASS; fi

as_user lumen-theme set lumen >/dev/null 2>&1
sleep 3
shot 22-final

# The taskbar used to crash ~5 minutes after starting (two waybars on D-Bus).
if grep -q '^LUMEN_TASKBAR=no' "$home/.config/lumen/settings.conf" 2>/dev/null; then
  : # switched off (the no-taskbar scenario)
elif pgrep -f '^(/usr/bin/)?waybar -c .*taskbar.jsonc' >/dev/null && ! grep -q 'taskbar stopped' "$home/.local/state/lumen/apps.log" 2>/dev/null; then
  result "taskbar still running at the end (no crash)" PASS
else
  result "taskbar still running at the end (no crash)" FAIL "$(tail -n 3 "$home/.local/state/lumen/apps.log" 2>/dev/null | tr '\n' ' ')"
fi

# The bar watcher brings a crashed top bar back (waybar has crashed in VMs).
if pgrep -f 'lumen-session watch-bars' >/dev/null; then
  pkill -KILL -fx '(/usr/bin/)?waybar'
  back=0
  for i in $(seq 40); do
    sleep 1
    if ((i > 2)) && pgrep -fx '(/usr/bin/)?waybar' >/dev/null; then back=$i; break; fi
  done
  if ((back)); then
    result "top bar comes back after a crash" PASS "after ${back}s"
  else
    result "top bar comes back after a crash" FAIL "not restarted after 40s"
    echo "--- bar watcher diagnostics"
    ps -eo pid,etimes,args | grep -E 'waybar|watch-bars' | grep -v grep
    tail -n 15 "$home/.local/state/lumen/apps.log" 2>/dev/null
    ls -d "$run/hypr/"* 2>/dev/null
  fi
else
  result "top bar comes back after a crash" FAIL "lumen-session watch-bars isn't running"
fi

say "E2E-SUMMARY $pass passed, $fail failed"
say "E2E-DONE"
