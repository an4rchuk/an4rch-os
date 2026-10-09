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
# QEMU types US key positions, so typing needs a US layout for the moment
# (Dvorak would turn "calc" into something else); the installed layout is
# checked from the config files, and comes back with the next config reload.
type_text() {
  as_user hyprctl eval 'hl.config({ input = { kb_layout = "us", kb_variant = "" } })' >/dev/null 2>&1 || true
  say "E2E-TYPE $1"
  sleep $((${#1} / 3 + 4))
}
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

# --- The choices made when installing (kernel, shell, edition, extra apps) --------------
choice() { sed -n "s/^$1=//p" /etc/lumen/install.conf 2>/dev/null | head -n1; }
k=$(choice kernel)
case "${k:-linux}" in
  lts) want='-lts$' ;; zen) want='-zen' ;; hardened) want='-hardened' ;; *) want='-arch[0-9]' ;;
esac
# Installed with lumen.bootlts=1: the LTS fallback kernel starts by default.
[[ "$(choice boot)" == fallback ]] && want='-lts$' && k="${k:-linux}, starting the LTS fallback"
# Offline installs fall back to the standard kernel when the chosen one isn't on the stick.
if uname -r | grep -qE -- "$want"; then
  result "kernel ($k) is running" PASS "$(uname -r)"
elif grep -q "needs the internet; installing the standard one" /var/log/lumen-os-install.log 2>/dev/null; then
  result "kernel ($k) is running" PASS "offline: standard kernel instead ($(uname -r))"
else
  result "kernel ($k) is running" FAIL "$(uname -r)"
fi
sh_want=$(choice shell)
sh_now=$(getent passwd "$u" | cut -d: -f7)
if [[ "${sh_now##*/}" == "${sh_want:-zsh}" ]]; then result "login shell is ${sh_want:-zsh}" PASS; else result "login shell is ${sh_want:-zsh}" FAIL "$sh_now"; fi
if [[ "${sh_want:-zsh}" == fish ]]; then
  task "fish starts with an4rch's settings" runuser -u "$u" -- env HOME="$home" fish -l -c 'type -q anarch; and set -q LUMEN_PATH'
elif [[ "${sh_want:-zsh}" == bash ]]; then
  task "bash starts with an4rch's settings" runuser -u "$u" -- env HOME="$home" bash -ic 'type anarch >/dev/null && alias ll >/dev/null'
fi
apps=$(choice apps)
if [[ -n "$apps" ]]; then
  missing=""
  for a in ${apps//,/ }; do
    src=$(python3 -c '
import json, sys
app = next((x for x in json.load(open(sys.argv[1]))["apps"] if x["id"] == sys.argv[2]), {})
print(" ".join(s["id"] for s in app.get("sources", [])))' "$lumen/apps/lumen-store/catalog.json" "$a")
    found=0
    for id in $src; do pacman -Q "$id" >/dev/null 2>&1 && found=1; flatpak info "$id" >/dev/null 2>&1 && found=1; done
    ((found)) || missing+="$a "
  done
  if [[ -z "$missing" ]]; then result "extra apps installed ($apps)" PASS; else result "extra apps installed ($apps)" FAIL "missing: $missing"; fi
fi
if [[ "$(choice mode)" == manual ]]; then
  task "installed on the chosen partitions" bash -c 'findmnt -no SOURCE / | grep -q "^/dev/vda[0-9]" ; lsblk -no FSTYPE "$(findmnt -no SOURCE / | sed "s/\[.*//")" | grep -q btrfs'
fi

# The an4rch boot screen: set as the theme, and inside every initramfs.
task "boot screen is an4rch's" bash -c 'grep -qx "Theme=an4rch" /etc/plymouth/plymouthd.conf &&
  for i in /boot/initramfs-*.img; do [[ $i == *fallback* ]] && continue; lsinitcpio "$i" | grep -q "usr/share/plymouth/themes/an4rch/an4rch.script" || { echo "missing from $i"; exit 1; }; done'

# How the boot screen met the graphics (for diagnosing handovers): which
# displays plymouth used and when, and the graphics drivers in the initramfs.
say "--- boot screen displays"
grep -aiE 'renderer|drm|simpledrm|/dev/dri|card[0-9]|add_device|remove_device|seat|show_splash|frame.?buffer' /var/log/plymouth-debug.log 2>/dev/null | cut -c1-200 | head -n 60
for img in /boot/initramfs-*.img; do
  [[ $img == *fallback* ]] && continue
  lsinitcpio "$img" 2>/dev/null | grep -E 'drm|gpu|virtio' | head -n 20
  break
done
journalctl -b -k --no-pager -o short-monotonic 2>/dev/null | grep -iE 'simpledrm|virtio_gpu|virtio-gpu|fb0|efifb|drm' | head -n 20
say "--- end boot screen displays"

# The boot animation gets its ~2 s before the boot screen hands over.
shown=$(systemctl show plymouth-start.service -p ActiveEnterTimestampMonotonic --value 2>/dev/null)
quit=$(systemctl show plymouth-quit.service -p ExecMainStartTimestampMonotonic --value 2>/dev/null)
if [[ "$shown" =~ ^[0-9]+$ && "$quit" =~ ^[0-9]+$ && $shown -gt 0 && $quit -gt 0 ]]; then
  played=$(awk -v a="$shown" -v b="$quit" 'BEGIN { printf "%.1f", (b - a) / 1000000 }')
  if awk -v p="$played" 'BEGIN { exit !(p >= 1.9) }'; then result "boot animation plays before the login" PASS "${played}s"
  else result "boot animation plays before the login" FAIL "handed over after ${played}s"; fi
else
  result "boot animation plays before the login" FAIL "shown=$shown quit=$quit"
fi

# --- an4rch Game edition: starts in Steam's Game Mode instead of the desktop --------------
if [[ "$(choice edition)" == game ]]; then
  say "Game edition: Steam's Game Mode at start-up"
  if pacman -Q steam >/dev/null 2>&1; then result "Steam installed" PASS; else result "Steam installed" FAIL; fi
  if pacman -Qq gamescope-session-steam-git >/dev/null 2>&1; then result "Game Mode session installed" PASS; else result "Game Mode session installed" FAIL; fi
  if sed -n '/^\[initial_session\]/,$p' /etc/greetd/config.toml | grep -q gamescope; then result "starts straight into Game Mode" PASS "$(sed -n '/^\[initial_session\]/,$p' /etc/greetd/config.toml | tr '\n' ' ')"; else result "starts straight into Game Mode" FAIL "$(tail -n 5 /etc/greetd/config.toml | tr '\n' ' ')"; fi
  if [[ -x /usr/local/bin/steamos-session-select ]]; then result "Switch to Desktop goes to the login screen" PASS; else result "Switch to Desktop goes to the login screen" FAIL; fi
  if compgen -G "/usr/share/wayland-sessions/hyprland*.desktop" >/dev/null; then result "the desktop is still a choice at login" PASS; else result "the desktop is still a choice at login" FAIL; fi
  sleep 40
  say "--- game session: $(pgrep -a gamescope | head -n 2 | tr '\n' ' ') $(pgrep -ax steam | head -n1)"
  journalctl -b --no-pager -q -u greetd | tail -n 15
  shot 30-game-mode
  # Steam → Power → Switch to Desktop: the login screen comes back.
  if pgrep -x gamescope >/dev/null || pgrep -f gamescope-session >/dev/null; then
    runuser -u "$u" -- env XDG_SESSION_ID="$(loginctl list-sessions --no-legend | awk -v u="$u" '$3 == u {print $1; exit}')" /usr/local/bin/steamos-session-select >/dev/null 2>&1 || true
    sleep 20
    if pgrep -f lumen_greeter.py >/dev/null || pgrep -x regreet >/dev/null; then result "Switch to Desktop shows the login screen" PASS; else result "Switch to Desktop shows the login screen" FAIL "$(pgrep -a cage | head -n1)"; fi
    shot 31-game-switch-to-desktop
  else
    say "Game Mode didn't start here (gamescope needs Vulkan; this VM may have none)"
  fi
  say "E2E-SUMMARY $pass passed, $fail failed"
  say "E2E-DONE"
  exit 0
fi

# --- an4rch Server: no desktop; check the system, remote access and the tools -----------
if [[ "$(choice edition)" == server ]]; then
  say "Server install: no desktop to test"
  if systemctl is-active -q sshd; then result "SSH server running" PASS; else result "SSH server running" FAIL; fi
  if systemctl is-active -q ufw && grep -q 'dport 22' /etc/ufw/user.rules; then result "firewall on, SSH allowed" PASS; else result "firewall on, SSH allowed" FAIL; fi
  if systemctl is-active -q NetworkManager; then result "NetworkManager running" PASS; else result "NetworkManager running" FAIL; fi
  if ! systemctl is-enabled -q greetd 2>/dev/null && ! pacman -Q hyprland >/dev/null 2>&1; then result "no desktop installed" PASS; else result "no desktop installed" FAIL; fi
  cli "anarch doctor (server)" anarch-doctor
  cli "anarch help" anarch help
  cli "anarch snapshot list" anarch snapshot
  task "anarch update can reach GitHub without a login" as_user env GIT_TERMINAL_PROMPT=0 timeout 60 bash -c 'cd "$LUMEN_PATH" && for r in https://github.com/an4rchuk/an4rch-os.git https://github.com/an4rchuk/lumen-os.git; do git remote set-url origin "$r" && git fetch --quiet --tags origin 2>/dev/null && break; done && git tag -l "v*" | tail -n 3'
  if swapon --show | grep -q zram; then result "zram swap" PASS; else result "zram swap" FAIL; fi
  shot 30-server-console
  say "E2E-SUMMARY $pass passed, $fail failed"
  say "E2E-DONE"
  exit 0
fi
pkill -f lumen_welcome.py
pkill -f lumen_store.py
sleep 2
shot 10-clean-desktop

# --- Health check ---------------------------------------------------------------------
cli "anarch doctor" anarch-doctor

# --- Apps from an4rch's launcher ------------------------------------------------------
as_user anarch-launch terminal
if wait_window "terminal opens (anarch-launch)" 'ghostty|alacritty|kitty' 30; then
  type_text "fastfetch"
  keys ret
  sleep 3
  shot 11-terminal-fastfetch
fi

# --- Themes --------------------------------------------------------------------------
task "theme switch to ancom" as_user anarch-theme set ancom
if [[ "$(cat "$home/.config/lumen/current/theme.name" 2>/dev/null)" == ancom ]]; then
  result "theme files rendered" PASS
else
  result "theme files rendered" FAIL "theme.name is '$(cat "$home/.config/lumen/current/theme.name" 2>/dev/null)'"
fi
sleep 3
shot 12-theme-ancom
task "next wallpaper" as_user anarch-wallpaper next

# --- Notifications, reminders, clipboard, screenshots --------------------------------
task "notification" as_user notify-send -a an4rch "Hello from the test" "Notifications work"
sleep 1
shot 13-notification
task "reminder scheduled" as_user anarch-remind 30m "Test reminder"
if as_user anarch-remind list --plain 2>/dev/null | grep -q "Test reminder"; then
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
task "screenshot (anarch-screenshot screen)" as_user anarch-screenshot screen
sleep 2
if find "$home/Pictures/Screenshots" -name '*.png' -newer "$marker" 2>/dev/null | grep -q .; then
  result "screenshot saved" PASS "$(find "$home/Pictures/Screenshots" -name '*.png' -newer "$marker" | head -n1)"
else
  result "screenshot saved" FAIL "nothing new in ~/Pictures/Screenshots"
fi
rm -f "$marker"

# --- Menus and keyboard ----------------------------------------------------------------
as_user anarch-menu >/dev/null 2>&1 &
sleep 4
if pgrep -x fuzzel >/dev/null; then result "anarch menu opens" PASS; else result "anarch menu opens" FAIL; fi
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
  as_user anarch-titlebars status 2>&1
  say "stamp: $(cat /var/lib/lumen/hyprbars-hyprland 2>&1) installed: $(pacman -Q hyprland 2>&1)"
  ls -la /usr/lib/lumen 2>&1
  say "login load log:"; cat "$home/.local/state/lumen/titlebars.log" 2>&1 | tail -n 20
  say "load now:"; as_user hyprctl plugin load /usr/lib/lumen/hyprbars.so 2>&1 | tail -n 20
  say "install log:"; grep -n -i -A12 'title bars\|hyprbars' /var/log/lumen-os-install.log 2>/dev/null | tail -n 60
fi
shot 17b-titlebars
task "minimise the calculator" as_user anarch-window minimize
sleep 2
if as_user anarch-window list | grep -qi calculator; then result "minimised window is hidden" PASS; else result "minimised window is hidden" FAIL "$(as_user anarch-window list | tr '\n' ' ')"; fi
task "taskbar on" as_user anarch-taskbar on
sleep 4
if pgrep -f '^(/usr/bin/)?waybar -c .*taskbar.jsonc' >/dev/null; then result "taskbar running" PASS; else result "taskbar running" FAIL; fi
shot 17c-taskbar
task "restore the calculator" as_user anarch-window restore
sleep 2
if as_user anarch-window list | grep -qi calculator; then result "restored window is back" FAIL; else result "restored window is back" PASS; fi
shot 17d-restored

# --- Bigger apps -------------------------------------------------------------------------
as_user anarch-store --search "video editor" >/dev/null 2>&1 &
sleep 20
shot 18-store-search
pkill -f lumen_store.py

as_user anarch-launch files
wait_window "file manager opens" 'nautilus' 40 && { sleep 3; shot 19-files; }

as_user anarch-launch monitor
wait_window "Task Manager opens" 'SystemMonitor' 40 && { sleep 3; shot 19b-task-manager; }

as_user anarch-launch browser https://archlinux.org
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
cli "anarch help" anarch help
cli "anarch tune status" anarch tune status
cli "anarch extras list" anarch extras list
cli "anarch dev status" anarch dev status
cli "anarch snapshot list" anarch snapshot
cli "anarch theme list" anarch theme list
cli "lumen (old name) still works" lumen version
cli "anarch theme packs" anarch theme packs
cli "anarch theme get ancom (a pack theme)" anarch theme get ancom
n=$(ls "$home/.local/share/backgrounds/lumen/ancom/"*.jpg 2>/dev/null | wc -l)
if [[ "$(cat "$home/.config/lumen/current/theme.name" 2>/dev/null)" == ancom && "$n" -ge 9 ]]; then
  result "pack theme switched on with its wallpapers" PASS "$n wallpapers"
else
  result "pack theme switched on with its wallpapers" FAIL "theme $(cat "$home/.config/lumen/current/theme.name" 2>/dev/null), $n wallpapers"
fi
shot 08b-pack-theme
bat=$(as_user anarch battery 2>&1)
if [[ "$bat" =~ ^(No\ battery|[0-9]+%) ]]; then result "anarch battery" PASS "$bat"; else result "anarch battery" FAIL "${bat:-no output}"; fi
task "audio (wpctl status)" as_user wpctl status
task "firewall active" systemctl is-active ufw
task "NetworkManager online" nmcli -t -f STATE general
task "zram swap" swapon --show
# The keyboard layout picked when installing reaches the desktop (not only the console).
km=$(sed -n 's/^KEYMAP=//p' /etc/vconsole.conf 2>/dev/null)
if [[ -n "$km" && "$km" != us ]]; then
  # (Dvorak and Colemak are the "us" layout with a variant.)
  task "keyboard layout ($km) on the desktop" bash -c "{ ! grep -q 'kb_layout  = \"us\"' '$home/.config/hypr/input.lua' || grep -qE '^\s*kb_variant = \"[a-z]+' '$home/.config/hypr/input.lua'; } && grep -q XkbLayout /etc/X11/xorg.conf.d/00-keyboard.conf"
fi
task "memory protection (systemd-oomd)" systemctl is-active systemd-oomd
# The live USB leaves out manuals and translations; an install must still get them.
task "installed system has manuals and translations" bash -c 'ls /usr/share/man/man1/ls.1* && ls -d /usr/share/locale/de/LC_MESSAGES'
# anarch update reaches GitHub with no login prompt (real installs asked for a GitHub password).
if nmcli -t -f STATE general 2>/dev/null | grep -q '^connected'; then
  task "anarch update can reach GitHub without a login" as_user env GIT_TERMINAL_PROMPT=0 timeout 60 bash -c 'cd "$LUMEN_PATH" && for r in https://github.com/an4rchuk/an4rch-os.git https://github.com/an4rchuk/lumen-os.git; do git remote set-url origin "$r" && git fetch --quiet --tags origin 2>/dev/null && break; done && git tag -l "v*" | tail -n 3'
fi
task "text editor and camera installed" bash -c 'command -v gnome-text-editor && command -v snapshot'

# --- Privacy, safety and the other an4rch tools ------------------------------------------
# root_cli NAME CMD... — like cli, as root (the commands use sudo).
root_cli() {
  local name="$1"
  shift
  task "$name" script -qefc "env LUMEN_PATH=$lumen HOME=/root $(printf '%q ' "$@")" /dev/null
}
cli "anarch health" anarch health
task "anarch health (as administrator)" script -qefc "env LUMEN_PATH=$lumen HOME=/root $lumen/bin/anarch-health" /dev/null
if ! systemctl is-failed -q smartd 2>/dev/null; then result "drive monitoring (smartd) not failed" PASS "$(systemctl is-active smartd)"; else result "drive monitoring (smartd) not failed" FAIL; fi
if [[ "$(findmnt -no FSTYPE /)" == btrfs ]]; then
  task "monthly btrfs scrub timer" systemctl is-enabled btrfs-scrub@-.timer
fi
task "daily health check timer" as_user systemctl --user is-enabled lumen-health.timer
task "'Remove hidden data' in Files" test -x "$home/.local/share/nautilus/scripts/Remove hidden data"

# Remove hidden data: a PNG with an author in it comes out without it.
as_user python3 -c '
from PIL import Image, PngImagePlugin
info = PngImagePlugin.PngInfo(); info.add_text("Author", "secret-author")
Image.new("RGB", (64, 64), "red").save("/tmp/scrub.png", pnginfo=info)'
task "anarch scrub removes hidden data" as_user bash -c 'anarch scrub --show /tmp/scrub.png | grep -q secret-author && anarch scrub --inplace /tmp/scrub.png && ! anarch scrub --show /tmp/scrub.png | grep -q secret-author'

# Vaults: make one, put a file in, close it: only scrambled names remain.
printf 'vm-vault-password\n' >/tmp/vault-pass && chmod 644 /tmp/vault-pass
task "anarch vault new + open" as_user env LUMEN_VAULT_PASSFILE=/tmp/vault-pass bash -c 'anarch vault new vmtest && anarch vault open vmtest && echo hello >~/Vaults/vmtest/note.txt && mountpoint -q ~/Vaults/vmtest'
task "anarch vault close (encrypted at rest)" as_user bash -c 'anarch vault close vmtest && ! mountpoint -q ~/Vaults/vmtest && ! ls ~/Vaults/vmtest/note.txt 2>/dev/null && ! grep -rq hello ~/.vaults/vmtest && ! find ~/.vaults/vmtest -name "note.txt" | grep -q .'
as_user env LUMEN_VAULT_PASSFILE=/tmp/vault-pass anarch vault open vmtest >/dev/null 2>&1

# Carry: save the setup, change a setting, bring the setup back.
task "anarch carry export + import" as_user script -qefc 'anarch carry export /tmp/carry.tar.gz && cp ~/.config/hypr/looks.lua /tmp/looks.before && echo "-- changed" >>~/.config/hypr/looks.lua && anarch carry import /tmp/carry.tar.gz --yes && cmp -s ~/.config/hypr/looks.lua /tmp/looks.before' /dev/null

# Focus: notifications off with a countdown, then back on.
cli "anarch focus 1" anarch focus 1
sleep 3
if as_user anarch-status focus | grep -q '1m' && as_user makoctl mode | grep -qx do-not-disturb; then
  result "focus session: countdown and Do Not Disturb" PASS
else
  result "focus session: countdown and Do Not Disturb" FAIL "$(as_user anarch-status focus) / $(as_user makoctl mode | tr '\n' ' ')"
fi
shot 19a-focus
cli "anarch focus stop" anarch focus stop
if ! as_user makoctl mode | grep -qx do-not-disturb; then result "focus session ends cleanly" PASS; else result "focus session ends cleanly" FAIL; fi

# Accessibility: bigger text and cursor, then the high contrast theme.
cli "anarch a11y text bigger" anarch a11y text bigger
cli "anarch a11y cursor big" anarch a11y cursor big
if [[ "$(as_user gsettings get org.gnome.desktop.interface text-scaling-factor)" == 1.25 ]]; then result "text size 125%" PASS; else result "text size 125%" FAIL; fi
cli "anarch a11y contrast on" anarch a11y contrast on
sleep 3
shot 19b-high-contrast
cli "anarch a11y contrast off" anarch a11y contrast off
as_user anarch a11y text reset >/dev/null 2>&1
as_user anarch a11y cursor normal >/dev/null 2>&1

# Privacy (needs the internet for the blocklist and encrypted DNS).
if nmcli -t -f STATE general 2>/dev/null | grep -q '^connected'; then
  root_cli "anarch privacy on" "$lumen/bin/anarch-privacy" on
  sleep 3
  task "privacy: encrypted DNS in use" bash -c 'resolvectl status | grep -q "+DNSOverTLS" && getent hosts archlinux.org'
  # systemd-resolved answers a 0.0.0.0 entry with no address at all (blocked).
  task "privacy: trackers blocked" bash -c 'grep -q "^0\.0\.0\.0 doubleclick\.net$" /etc/hosts && { ! getent hosts doubleclick.net || getent hosts doubleclick.net | grep -q "^0\.0\.0\.0"; }'
  task "privacy: hidden hardware address set" test -f /etc/NetworkManager/conf.d/50-lumen-privacy-mac.conf
  cli "anarch privacy status" anarch privacy status
  root_cli "anarch privacy off" "$lumen/bin/anarch-privacy" off
  sleep 3
  task "privacy off: names still resolve" bash -c '! grep -q "an4rch blocklist" /etc/hosts && getent hosts archlinux.org'
  # A sandboxed app sees an empty home and, offline, no network.
  if pacman -S --needed --noconfirm firejail >/dev/null 2>&1; then
    cli "anarch sandbox (no files, no network)" anarch sandbox --offline bash -c 'test ! -e ~/.config/lumen && ! curl -s --max-time 5 https://archlinux.org >/dev/null'
  fi
fi

# --- Tools borrowed from other systems ------------------------------------------------------
cli "anarch note (add a line)" anarch note "from the VM test"
task "notes file has the line" grep -q 'from the VM test' "$home/Notes/notes.md"
as_user anarch-note
sleep 4
if as_user hyprctl clients -j | jq -e '.[] | select(.class == "lumen.notes")' >/dev/null; then result "quick notes window (SUPER + ALT + K)" PASS; else result "quick notes window (SUPER + ALT + K)" FAIL "windows: $(windows | tr '\n' ' ')"; fi
shot 19c-notes
as_user anarch-note # hide again
sleep 2
if pgrep -f 'anarch-screentime daemon' >/dev/null; then result "screen time is counting" PASS; else result "screen time is counting" FAIL; fi
sleep 35
cli "anarch screentime" anarch screentime
task "screen time has counted something" bash -c "ls '$home/.local/state/lumen/screentime/'*.tsv"
cli "anarch tidy --dry-run" anarch tidy --dry-run
cli "anarch share text (QR code)" anarch share text "https://github.com/an4rchuk/an4rch-os"
cli "anarch auto (sunrise and sunset)" anarch auto on
if [[ -f "$home/.config/lumen/auto.conf" ]] && pgrep -f 'anarch-auto daemon' >/dev/null; then result "light/dark follows the sun" PASS "$(as_user anarch auto | tr '\n' ' ')"; else result "light/dark follows the sun" FAIL; fi
cli "anarch auto off" anarch auto off
as_user anarch-theme set an4rch >/dev/null 2>&1
as_user anarch-toggle nightlight off >/dev/null 2>&1
cli "anarch reset --dry-run" anarch reset --dry-run

# --- 1.1.1: scaling, backups, drivers, problem reports, phone, Secure Boot ------------------
# Screens get the size an4rch picks for them (150% on 4K, 100% on 1080p),
# unless a display rule of your own says otherwise.
mons=$(as_user hyprctl monitors -j 2>/dev/null)
read -r mname pick _ < <(as_user python3 "$lumen/lib/autoscale.py" <<<"$mons" 2>/dev/null | head -n1)
if [[ -n "${mname:-}" ]] && ! grep -qs "\"$mname\"\|desc:" "$home/.config/hypr/monitors.lua"; then
  got=$(jq -r --arg n "$mname" '.[] | select(.name == $n) | .scale' <<<"$mons")
  size=$(jq -r --arg n "$mname" '.[] | select(.name == $n) | "\(.width)x\(.height)"' <<<"$mons")
  if awk -v a="$pick" -v b="$got" 'BEGIN { exit !(a - b < 0.01 && b - a < 0.01) }'; then
    result "display scaled for its size" PASS "$size at $got"
  else
    result "display scaled for its size" FAIL "$size: want $pick, have ${got:-?}"
  fi
fi
cli "anarch display autoscale" anarch display autoscale
# Backups: back up, lose a file, get it back.
pacman -S --needed --noconfirm restic fuse3 >/dev/null 2>&1 || true
as_user bash -c 'mkdir -p ~/Documents && echo "an4rch backup check" > ~/Documents/backup-check.txt'
cli "anarch backup setup (to a folder)" anarch backup setup /var/tmp/an4rch-bk
as_user rm -f "$home/Documents/backup-check.txt"
cli "anarch backup restore" anarch backup restore "$home/Documents/backup-check.txt"
if as_user bash -c 'grep -rqs "an4rch backup check" ~/Restored'; then result "backup brings a deleted file back" PASS; else result "backup brings a deleted file back" FAIL "$(as_user find "$home/Restored" -type f | head -n 5 | tr '\n' ' ')"; fi
task "hourly backup timer" as_user systemctl --user is-enabled lumen-backup.timer
cli "anarch backup off" anarch backup off
cli "anarch drivers" anarch drivers
task "anarch drivers check (nothing better to install)" as_user anarch drivers check
rep=$(as_user anarch report --print 2>/dev/null)
# (The VM's computer name is an4rch, the OS's own name, which the report keeps;
# the user name and home folder must be gone.)
if [[ "$rep" == *"===== System"* && "$rep" != *"/home/$u"* ]] && ! grep -qw -- "$u" <<<"$rep"; then
  result "problem report (private details removed)" PASS "$(wc -l <<<"$rep") lines"
else
  result "problem report (private details removed)" FAIL "$(grep -m3 -w -e "/home/$u" -e "$u" <<<"$rep" | tr '\n' ' ')"
fi
cli "anarch phone (status)" anarch phone
if [[ -d /sys/firmware/efi ]]; then cli "anarch secureboot (status)" anarch secureboot; fi
if [[ -d /sys/class/power_supply/BAT0 || -d /sys/class/power_supply/BAT1 ]]; then cli "anarch battery limit (show)" anarch battery limit; fi

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
# (Only beside Windows: own partitions with a separate boot partition also use /efi.)
if findmnt -n /efi >/dev/null 2>&1 && { [[ "$(choice mode)" == alongside ]] || [[ -d /efi/EFI/Microsoft ]]; }; then
  say "--- dual boot: $(bootctl list --no-pager 2>/dev/null | grep -E 'title:|id:' | tr -s ' ' | tr '\n' ' ')"
  if [[ -f /efi/EFI/Microsoft/Boot/bootmgfw.efi ]]; then result "Windows boot manager kept" PASS; else result "Windows boot manager kept" FAIL; fi
  if bootctl list --no-pager 2>/dev/null | grep -qi 'windows'; then result "boot menu lists Windows" PASS; else result "boot menu lists Windows" FAIL "$(bootctl list --no-pager 2>&1 | head -n 20 | tr '\n' ' ')"; fi
  if grep -q LOCAL /etc/adjtime 2>/dev/null; then result "clock in local time (like Windows)" PASS; else result "clock in local time (like Windows)" FAIL; fi
fi

# --- Settings, the sound panel and the login screen ------------------------------------------
as_user anarch-settings windows >/dev/null 2>&1 &
if wait_window "Settings opens" 'lumen.Settings' 40; then
  sleep 3
  shot 21a-settings
fi
# The an4rch Hub's 1.1.1 pages: every page built (a broken one fails here), then Backups shown.
pkill -f lumen_settings.py
sleep 2
as_user env LUMEN_SETTINGS_ALL_PAGES=1 anarch-hub backups >/dev/null 2>&1 &
if wait_window "an4rch Hub opens (all pages built)" 'lumen.Settings' 40; then
  sleep 3
  shot 21b-hub-backups
  pkill -f lumen_settings.py
  sleep 2
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

as_user anarch-audio >/dev/null 2>&1 &
sleep 6
if as_user hyprctl layers -j 2>/dev/null | grep -q '"anarch-audio"'; then
  result "sound panel opens" PASS
else
  result "sound panel opens" FAIL "$(pgrep -af lumen_audio | head -n 2 | tr '\n' ' ')"
fi
shot 21b-sound-panel
as_user anarch-audio >/dev/null 2>&1
sleep 2

# The Wi-Fi, Bluetooth and power panels under the top bar.
for panel in network bluetooth power; do
  as_user anarch-panel "$panel" >/dev/null 2>&1 &
  sleep 6
  if as_user hyprctl layers -j 2>/dev/null | grep -q '"anarch-panel"'; then
    result "$panel panel opens" PASS
  else
    result "$panel panel opens" FAIL "$(pgrep -af lumen_panels | head -n 2 | tr '\n' ' ')"
  fi
  shot "21c-$panel-panel"
  as_user anarch-panel "$panel" >/dev/null 2>&1
  sleep 2
done

if [[ -x /usr/local/bin/lumen-greeter ]] && grep -q lumen-greeter /etc/greetd/config.toml 2>/dev/null; then
  result "login screen installed" PASS
else
  result "login screen installed" FAIL "$(grep -m1 command /etc/greetd/config.toml 2>&1)"
fi
if [[ -s /var/lib/lumen/login/wallpaper && -s /var/lib/lumen/login/greeter.css && -f /usr/local/share/lumen/greeter/lumen_greeter.py ]]; then
  result "login screen has the theme and wallpaper" PASS
else
  result "login screen has the theme and wallpaper" FAIL "$(ls -la /var/lib/lumen/login 2>&1 | tr '\n' ' ')"
fi
as_user anarch-login preview >/dev/null 2>&1
if wait_window "login screen preview" 'os.an4rch.Greeter' 30; then
  sleep 3
  shot 21c-login-screen
fi
pkill -f 'lumen-greeter/lumen_greeter.py' 

# --- Lock screen ---------------------------------------------------------------------------
pkill -x firefox
pkill -x nautilus
pkill -f gnome-calculator
sleep 2
# The panic key: locks, closes vaults, wipes the clipboard and mutes.
as_user wl-copy "panic-clipboard-test"
keys meta_l-shift-esc
sleep 6
if pgrep -x hyprlock >/dev/null; then result "panic key locks the screen" PASS; else result "panic key locks the screen" FAIL; fi
if ! mountpoint -q "$home/Vaults/vmtest"; then result "panic key closes vaults" PASS; else result "panic key closes vaults" FAIL; fi
if [[ "$(as_user wl-paste -n 2>/dev/null)" != panic-clipboard-test ]]; then result "panic key wipes the clipboard" PASS; else result "panic key wipes the clipboard" FAIL; fi
mic=$(as_user wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>&1)
if [[ "$mic" == *MUTED* ]]; then result "panic key mutes the microphone" PASS
elif [[ "$mic" == *"not a valid ID"* ]]; then result "panic key mutes the microphone" PASS "this VM has no microphone"
else result "panic key mutes the microphone" FAIL "$mic"; fi
shot 20b-panic
type_text "lumen"
keys ret
sleep 5
as_user wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 2>/dev/null
as_user wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 2>/dev/null

loginctl lock-sessions
sleep 6
if pgrep -x hyprlock >/dev/null; then result "lock screen" PASS; else result "lock screen" FAIL; fi
shot 21-lock-screen
type_text "lumen"
keys ret
sleep 5
if pgrep -x hyprlock >/dev/null; then result "unlock with password" FAIL; else result "unlock with password" PASS; fi

as_user anarch-theme set an4rch >/dev/null 2>&1
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
if pgrep -f 'anarch-session watch-bars' >/dev/null; then
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
  result "top bar comes back after a crash" FAIL "anarch-session watch-bars isn't running"
fi

say "E2E-SUMMARY $pass passed, $fail failed"
say "E2E-DONE"
