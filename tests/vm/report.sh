#!/bin/bash
# VM test only (installed with lumen.serial=1): describe the desktop session
# on the serial console, for the e2e workflow to print.
exec >/dev/ttyS0 2>&1
u=$(id -un 1000 2>/dev/null)
run=/run/user/1000
sig=$(ls "$run/hypr" 2>/dev/null | head -n1)
echo "=== LUMEN-E2E-REPORT ==="
echo "--- processes"; ps -eo user,pid,etime,args | grep -E 'hypr|waybar|swaybg|mako|lumen|greetd|uwsm|fuzzel|pipewire' | grep -v grep
echo "--- failed units"; systemctl --failed --no-pager
echo "--- hyprland log"; for f in "$run"/hypr/*/hyprland.log; do tail -n 60 "$f"; echo; done
for q in configerrors layers clients; do
  echo "--- hyprctl $q"
  sudo -u "$u" env XDG_RUNTIME_DIR="$run" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$q" 2>&1 | head -n 60
done
echo "--- user journal (warnings)"; journalctl -b _UID=1000 -p warning --no-pager -o short-monotonic | tail -n 80
echo "--- errors"; journalctl -b -p err --no-pager | tail -n 40
echo "--- lumen state"; ls -la "/home/$u/.config/lumen/" "/home/$u/.config/lumen/current/" "/home/$u/.config/autostart/" 2>&1 | head -n 40
echo "--- session.log"; grep -v '^+ \(local\|\[\[\|pgrep\|has \|command -v\|systemctl --user is-active\|shift\)' "/home/$u/.local/state/lumen/session.log" 2>&1 | tail -n 40
echo "--- install warnings"; grep -n -E '^(WARN|FAIL|!)|warning:|error:' "/home/$u/.local/state/lumen/install.log" 2>&1 | tail -n 40
echo "=== LUMEN-E2E-REPORT-END ==="
