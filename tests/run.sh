#!/usr/bin/env bash
# an4rch test suite. Runs on any Linux box (no Hyprland needed):
#   - Hyprland Lua config checked against the real 0.56 API (tests/hypr-api.lua)
#   - every theme renders with no leftover placeholders
#   - shellcheck on all shell scripts
#   - Waybar config is valid JSON(C); wallpapers generate
#
# Requirements: bash, lua (5.1+), shellcheck, jq, python3 (+ Pillow for wallpapers).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
root=$PWD
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

step() { printf '\n\e[1m▸ %s\e[0m\n' "$1"; }
ok() { printf '  \e[32m✓\e[0m %s\n' "$1"; }
bad() { printf '  \e[31m✗\e[0m %s\n' "$1"; failures=$((failures + 1)); }

export HOME="$tmp/home" LUMEN_PATH="$root" XDG_CONFIG_HOME="$tmp/home/.config" XDG_STATE_HOME="$tmp/home/.local/state"
mkdir -p "$HOME/.config"
# Stand-ins for desktop tools so scripts can run headless.
mkdir -p "$tmp/bin"
for c in notify-send hyprctl makoctl gsettings pkill swaybg; do printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/$c"; chmod +x "$tmp/bin/$c"; done
export PATH="$tmp/bin:$PATH"

step "Themes"
for t in "$root"/themes/*/; do
  name=$(basename "$t")
  if out=$("$root/bin/anarch-theme" set "$name" 2>&1) && ! grep -rq '{{' "$HOME/.config/lumen/current/theme/"; then
    ok "$name"
  else
    bad "$name: $out"
  fi
done
# Themes from the packs (anarch theme get …).
for t in "$root"/themes-extra/*/*/; do
  [[ -f "$t/theme.conf" ]] || continue
  name=$(basename "$t")
  mkdir -p "$HOME/.config/lumen/themes" && cp -r "$t" "$HOME/.config/lumen/themes/$name"
  if out=$("$root/bin/anarch-theme" set "$name" 2>&1) && ! grep -rq '{{' "$HOME/.config/lumen/current/theme/"; then
    ok "pack theme $name"
  else
    bad "pack theme $name: $out"
  fi
  rm -rf "$HOME/.config/lumen/themes/$name"
done
# The signature theme's old name still works.
if "$root/bin/anarch-theme" set lumen >/dev/null 2>&1 && [[ "$("$root/bin/anarch-theme" current)" == an4rch ]]; then
  ok "old theme name 'lumen' switches to an4rch"
else
  bad "theme 'lumen' doesn't map to an4rch"
fi
# Retired themes (the old palettes before 1.1.1) land on their replacement.
if "$root/bin/anarch-theme" set nord >/dev/null 2>&1 && [[ "$("$root/bin/anarch-theme" current)" == an4rch ]] &&
  "$root/bin/anarch-theme" set catppuccin-latte >/dev/null 2>&1 && [[ "$("$root/bin/anarch-theme" current)" == an4rch-light ]]; then
  ok "retired themes switch to an4rch / an4rch Light"
else
  bad "retired theme names don't map to their replacement"
fi
"$root/bin/anarch-theme" set an4rch >/dev/null

step "Hyprland config (Lua)"
lua=$(command -v lua5.4 || command -v lua5.3 || command -v luajit || command -v lua)
if [[ -z "$lua" ]]; then
  bad "no lua interpreter found"
else
  cp -r "$root/config/hypr" "$HOME/.config/hypr"
  if "$lua" "$root/tests/check-hypr-config.lua" "$HOME/.config/hypr/hyprland.lua" "$root/tests"; then
    ok "config loads cleanly"
  else
    bad "config has problems"
  fi
  # The generated theme file on its own.
  theme_lua="$HOME/.config/lumen/current/theme/hyprland.lua"
  if "$lua" "$root/tests/check-hypr-config.lua" "$theme_lua" "$root/tests" >/dev/null; then ok "theme hyprland.lua"; else bad "theme hyprland.lua"; fi
  # What the Settings app writes, with every choice changed from the default.
  python3 - "$HOME/.config/lumen/desktop.json" <<'PY'
import json, sys
json.dump({"gaps_in": 9, "gaps_out": 0, "border_size": 3, "rounding": 0, "inactive_opacity": 0.9, "blur": False,
           "shadow": False, "animations": False, "sensitivity": -0.3, "natural_scroll": False, "tap_to_click": False,
           "disable_while_typing": False, "scroll_factor": 0.8, "repeat_delay": 400, "repeat_rate": 30}, open(sys.argv[1], "w"))
PY
  python3 "$root/apps/lumen-settings/lumen_settings.py" --write-desktop >/dev/null
  if "$lua" "$root/tests/check-hypr-config.lua" "$HOME/.config/lumen/desktop.lua" "$root/tests" >/dev/null; then
    ok "Settings' desktop.lua (every option changed)"
  else
    bad "Settings' desktop.lua: $("$lua" "$root/tests/check-hypr-config.lua" "$HOME/.config/lumen/desktop.lua" "$root/tests" | grep '✗')"
  fi
  rm -f "$HOME/.config/lumen/desktop.json" "$HOME/.config/lumen/desktop.lua"
fi

step "Shell scripts"
mapfile -t scripts < <(grep -lE '^#!/usr/bin/env bash|^#!/bin/bash' "$root"/bin/* "$root"/install.sh "$root"/boot.sh "$root"/install/*.sh "$root"/tests/*.sh "$root"/tests/vm/*.sh "$root"/iso/*.sh "$root"/iso/airootfs/usr/local/bin/* 2>/dev/null)
if command -v shellcheck >/dev/null; then
  if LC_ALL=C.UTF-8 shellcheck -x -P "$root/lib" -e SC1091 -S warning "${scripts[@]}" "$root/lib/lumen.sh"; then
    ok "shellcheck: ${#scripts[@]} scripts"
  else
    bad "shellcheck found issues"
  fi
else
  bad "shellcheck not installed"
fi
for s in "${scripts[@]}"; do bash -n "$s" || bad "syntax: $s"; done
ok "bash -n"

step "an4rch apps (Start menu, App Store, Welcome)"
if python3 -m py_compile "$root"/apps/*/*.py "$root/bin/anarch-wallgen" 2>&1; then ok "Python compiles"; else bad "Python syntax"; fi
rm -rf "$root"/apps/*/__pycache__ "$root"/bin/__pycache__
if python3 - "$root/apps/lumen-store/catalog.json" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1]))
cats = {c["id"] for c in data["categories"]}
ids, problems = set(), []
for a in data["apps"]:
    if a["id"] in ids: problems.append(f"duplicate id {a['id']}")
    ids.add(a["id"])
    if a["category"] not in cats: problems.append(f"{a['id']}: unknown category {a['category']}")
    if not a["sources"]: problems.append(f"{a['id']}: no sources")
    for s in a["sources"]:
        if s["type"] not in ("pacman", "aur", "flatpak"): problems.append(f"{a['id']}: bad source type {s['type']}")
        if not re.match(r"^[A-Za-z0-9@._+-]+$", s["id"]): problems.append(f"{a['id']}: bad package id {s['id']}")
        if s["type"] == "flatpak" and s["id"].count(".") < 2: problems.append(f"{a['id']}: flatpak id {s['id']} looks wrong")
if problems:
    sys.exit("\n".join(problems))
print(f"  {len(ids)} apps in {len(cats)} categories")
PY
then ok "store catalogue is valid"; else bad "store catalogue"; fi

# Every menu entry, Start search action, Settings button, bar click, key
# binding and app shortcut must point at a command an4rch ships (or a
# well-known system one), so no menu item silently does nothing.
if python3 - "$root" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
ours = {p.name for p in (root / "bin").iterdir()}
refs = []  # (where, command)
def add(where, cmd):
    if cmd.startswith("anarch-"):
        refs.append((where, cmd))
for f in [root / "bin/anarch-menu", *root.glob("apps/*/*.py"), root / "config/waybar/config.jsonc",
          root / "config/waybar/taskbar.jsonc", root / "default/hypr/binds.lua"]:
    text = f.read_text()
    for m in re.finditer(r'\$bin/(anarch-[a-z0-9-]+)', text): add(f.name, m.group(1))
    for m in re.finditer(r'["\[]\s*"?(anarch-[a-z0-9-]+)"', text): add(f.name, m.group(1))
    for m in re.finditer(r'"on-click[a-z-]*":\s*"(anarch-[a-z0-9-]+)', text): add(f.name, m.group(1))
    for m in re.finditer(r'(?<![\w.])cmd\("([a-z0-9-]+)"', text): add(f.name, "anarch-" + m.group(1))
for f in root.glob("share/applications/*.desktop"):
    m = re.search(r"^Exec=(\S+)", f.read_text(), re.M)
    if m: add(f.name, m.group(1))
# Lua files are referenced as lumen-<name>.lua etc. and app ids as anarch-start; keep real commands only.
skip = {"lumen-logo", "anarch-installer", "lumen-floating", "lumen-start.desktop"}
missing = sorted({(w, c) for w, c in refs if c not in ours and c not in skip and not c.endswith((".desktop", "-"))
                  and c != "anarch-os-install" and (root / "iso/airootfs/usr/local/bin" / c).exists() is False})
for w, c in missing:
    print(f"  {w}: {c} doesn't exist")
print(f"  {len(set(c for _, c in refs))} commands referenced from menus, bars, binds and apps")
sys.exit(1 if missing else 0)
PY
then ok "every menu item points at a real command"; else bad "menu items point at missing commands"; fi

# Headless smoke test: each GTK app starts and renders without a traceback.
if command -v xvfb-run >/dev/null && python3 -c 'import gi; gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")' 2>/dev/null; then
  for app in "lumen-start/lumen_start.py --show" "lumen-store/lumen_store.py" "lumen-welcome/lumen_welcome.py" "lumen-installer/lumen_installer.py" \
    "lumen-settings/lumen_settings.py" "lumen-audio/lumen_audio.py --show" "lumen-desktop/lumen_desktop.py" \
    "lumen-panels/lumen_panels.py network --show" "lumen-panels/lumen_panels.py bluetooth --show" "lumen-panels/lumen_panels.py power --show"; do
    log="$tmp/gui.log"
    # shellcheck disable=SC2086
    LUMEN_INSTALLER_DEMO=1 LUMEN_SETTINGS_ALL_PAGES=1 LUMEN_PANELS_DEMO=1 GDK_BACKEND=x11 GSK_RENDERER=cairo GTK_A11Y=none timeout 25 xvfb-run -a dbus-run-session -- \
      bash -c "python3 $root/apps/$app & pid=\$!; sleep 6; kill -0 \$pid && echo LUMEN-ALIVE; kill \$pid" >"$log" 2>&1 || true
    if grep -qE 'Traceback|Error:' "$log" || ! grep -q LUMEN-ALIVE "$log"; then
      bad "${app%%/*}: $(grep -v 'fd limit' "$log" | grep -m1 -E 'Error|error|No such' || echo "exited early")"
    else
      ok "${app%%/*} renders"
    fi
  done
else
  printf '  - GUI smoke test skipped (needs xvfb-run and Python GTK 4 + libadwaita)\n'
fi

step "Waybar"
if python3 - "$root/config/waybar/config.jsonc" <<'PY'
import json, re, sys
text = open(sys.argv[1]).read()
# Strip // comments that are not inside strings.
out, i, in_str = [], 0, False
while i < len(text):
    c = text[i]
    if in_str:
        out.append(c)
        if c == "\\":
            out.append(text[i + 1]); i += 1
        elif c == '"':
            in_str = False
    elif c == '"':
        in_str = True; out.append(c)
    elif text.startswith("//", i):
        while i < len(text) and text[i] != "\n":
            i += 1
        continue
    else:
        out.append(c)
    i += 1
cfg = json.loads("".join(out))
mods = cfg["modules-left"] + cfg["modules-center"] + cfg["modules-right"]
for g in [m for m in mods if m.startswith("group/")]:
    mods += cfg[g]["modules"]
missing = [m for m in mods if m not in cfg and not m.startswith(("hyprland/workspaces",))]
missing = [m for m in missing if m not in ("hyprland/workspaces",)]
if missing:
    sys.exit("modules without a config block: " + ", ".join(missing))
PY
then ok "config.jsonc parses and every module is configured"; else bad "waybar config"; fi

step "Docs"
if [[ -n "$lua" ]]; then
  if "$lua" "$root/tests/gen-keys-doc.lua" "$root" | diff -q - "$root/docs/02-keybindings.md" >/dev/null; then
    ok "docs/02-keybindings.md matches the bindings"
  else
    bad "docs/02-keybindings.md is out of date: $lua tests/gen-keys-doc.lua . > docs/02-keybindings.md"
  fi
fi

step "Wallpapers"
if python3 -c 'import PIL' 2>/dev/null; then
  if python3 "$root/bin/anarch-wallgen" --theme an4rch --theme an4rch-light --theme ancom --size 640x360 --out "$tmp/walls" >/dev/null &&
    [[ $(find "$tmp/walls" -type f | wc -l) -eq 27 ]]; then
    ok "$(find "$tmp/walls" -type f | wc -l) wallpapers generated (dark, light and an anarchism theme)"
  else
    bad "anarch-wallgen failed"
  fi
else
  printf '  - skipped (Pillow not installed)\n'
fi

step "Graphics drivers"
picks=$(bash -c 'source "$1/lib/gpu.sh"; for d in 2684 1f08 1c03 13c2 1180 0a65; do printf "%s " "$(nvidia_driver $d)"; done' _ "$root")
if [[ "$picks" == "open open 580xx 580xx 470xx nouveau " ]]; then ok "NVIDIA driver by card: RTX 40/20 open, GTX 10/900 580xx, GTX 600 470xx, older nouveau"
else bad "NVIDIA driver picks: $picks"; fi

step "Display scaling"
picks=$(printf '[{"name":"Virtual-1","width":3840,"height":2160,"refreshRate":60},{"name":"DP-1","width":1920,"height":1080,"refreshRate":60},{"name":"eDP-1","width":2560,"height":1600,"refreshRate":60},{"name":"HDMI-A-1","width":5120,"height":2880,"refreshRate":60}]' |
  python3 "$root/lib/autoscale.py" | awk '{printf "%s=%s ", $1, $2}')
if [[ "$picks" == "Virtual-1=1.5 DP-1=1 eDP-1=1.6 HDMI-A-1=2 " ]]; then ok "auto scale: 4K 150%, 1080p 100%, laptop 160%, 5K 200%"
else bad "auto scale picked: $picks"; fi

step "Privacy, safety and other an4rch tools"
# anarch carry: export, change a setting, import, and the setting is back.
mkdir -p "$HOME/.config/lumen" "$HOME/.config/hypr"
echo 'LUMEN_BROWSER=carry-test' >"$HOME/.config/lumen/settings.conf"
echo '-- monitors here' >"$HOME/.config/hypr/monitors.lua"
if "$root/bin/anarch-carry" export "$tmp/carry.tar.gz" >/dev/null 2>&1 &&
  echo 'LUMEN_BROWSER=changed' >"$HOME/.config/lumen/settings.conf" &&
  echo '-- this machine' >"$HOME/.config/hypr/monitors.lua" &&
  script -qefc "$root/bin/anarch-carry import $tmp/carry.tar.gz" /dev/null </dev/null >/dev/null 2>&1 &&
  grep -q carry-test "$HOME/.config/lumen/settings.conf" && grep -q 'this machine' "$HOME/.config/hypr/monitors.lua" &&
  ls "$HOME"/.local/state/lumen/before-carry-*/.config/lumen/settings.conf >/dev/null 2>&1; then
  ok "anarch carry: export and import round-trip (screen layout kept, old settings backed up)"
else
  bad "anarch carry round-trip"
fi
# An unsafe carry file is refused.
mkdir -p "$tmp/evil/meta" && touch "$tmp/evil/meta/carry.conf" "$tmp/evil/escape"
tar -C "$tmp/evil" -czf "$tmp/evil.tar.gz" meta escape
if ! "$root/bin/anarch-carry" show "$tmp/evil.tar.gz" >/dev/null 2>&1; then ok "anarch carry refuses files outside home/ and meta/"; else bad "anarch carry accepted an unsafe file"; fi
rm -f "$HOME/.config/lumen/settings.conf"

# anarch a11y: text size steps, saved for the next login.
if "$root/bin/anarch-a11y" text bigger >/dev/null && "$root/bin/anarch-a11y" text bigger >/dev/null &&
  grep -qx 'TEXT=1.5' "$HOME/.config/lumen/a11y.conf" && "$root/bin/anarch-a11y" text reset >/dev/null &&
  grep -qx 'TEXT=1.0' "$HOME/.config/lumen/a11y.conf"; then
  ok "anarch a11y text sizes"
else
  bad "anarch a11y text sizes"
fi
if "$root/bin/anarch-a11y" contrast on >/dev/null 2>&1 && [[ "$("$root/bin/anarch-theme" current)" == high-contrast ]] &&
  "$root/bin/anarch-a11y" contrast off >/dev/null 2>&1 && [[ "$("$root/bin/anarch-theme" current)" == an4rch ]]; then
  ok "anarch a11y contrast on/off returns to the theme you had"
else
  bad "anarch a11y contrast"
fi

# The status JSON the top bar reads.
for m in camera focus; do
  if "$root/bin/anarch-status" "$m" | jq -e 'has("text") and has("class")' >/dev/null 2>&1; then ok "anarch-status $m"; else bad "anarch-status $m: not JSON"; fi
done
# Every new command has --help.
for c in privacy panic vault sandbox scrub focus health carry a11y auto note say screentime tidy reset share; do
  if [[ -n "$("$root/bin/anarch-$c" --help 2>/dev/null | head -n1)" ]]; then :; else bad "anarch-$c --help"; fi
done
ok "--help for privacy, panic, vault, sandbox, scrub, focus, health, carry, a11y, auto, note, say, screentime, tidy, reset, share"
# Vault names can't escape ~/.vaults.
if ! "$root/bin/anarch-vault" open ../../etc >/dev/null 2>&1; then ok "anarch vault rejects odd names"; else bad "anarch vault accepted '../../etc'"; fi

# anarch auto: sunrise and sunset from the time zone (London in early October: ~07:10 and ~18:25).
sun=$(sed -n "/python3 - \"\$tz\" <<'PY'/,/^PY\$/p" "$root/bin/anarch-auto" | sed '1d;$d')
if [[ "$(TZ=Europe/London python3 - Europe/London <<<"$sun" 2>/dev/null | wc -w)" == 2 ]] &&
  TZ=Europe/London python3 - Europe/London <<<"$sun" | grep -qE '^0[4-9]:[0-5][0-9] 1[5-9]:[0-5][0-9]$|^0[4-9]:[0-5][0-9] 2[0-2]:[0-5][0-9]$'; then
  ok "anarch auto: sunrise $(TZ=Europe/London python3 - Europe/London <<<"$sun" | tr ' ' '/') in London today"
else
  bad "anarch auto: sunrise/sunset calculation"
fi
if "$root/bin/anarch-auto" times 07:00 19:30 >/dev/null && grep -qx 'MODE=fixed' "$HOME/.config/lumen/auto.conf" &&
  ! "$root/bin/anarch-auto" times 25:00 19:30 >/dev/null 2>&1; then
  ok "anarch auto: fixed times, bad times refused"
else
  bad "anarch auto times"
fi
rm -f "$HOME/.config/lumen/auto.conf"

# anarch note: a line added from the command line.
# Backups: set up on a folder, back up, change a file, restore the first version.
if command -v restic >/dev/null; then
  b="$tmp/backup"
  mkdir -p "$b/home/Documents" "$b/drive" "$b/bin"
  printf '#!/bin/sh\nexit 0\n' >"$b/bin/pacman"; cp "$b/bin/pacman" "$b/bin/systemctl"; chmod +x "$b/bin/"*
  echo v1 >"$b/home/Documents/note.txt"
  benv=(env HOME="$b/home" XDG_CONFIG_HOME="$b/home/.config" XDG_STATE_HOME="$b/home/.local/state" PATH="$b/bin:$PATH" LUMEN_PATH="$root")
  if "${benv[@]}" "$root/bin/anarch-backup" setup "$b/drive" >/dev/null 2>&1 && echo v2 >"$b/home/Documents/note.txt" &&
    "${benv[@]}" "$root/bin/anarch-backup" now >/dev/null 2>&1; then
    first=$(RESTIC_PASSWORD_FILE="$b/home/.config/lumen/backup.key" restic -r "$(echo "$b"/drive/an4rch-backups/*)" snapshots --json 2>/dev/null |
      python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["short_id"])')
    "${benv[@]}" "$root/bin/anarch-backup" restore "$b/home/Documents/note.txt" "$first" >/dev/null 2>&1
    if [[ "$(find "$b/home/Restored" -name note.txt -exec cat {} \; 2>/dev/null)" == v1 ]]; then ok "anarch backup: back up, then restore an earlier version"
    else bad "anarch backup: the earlier version didn't come back"; fi
  else
    bad "anarch backup: setup or backup failed"
  fi
else
  printf "  - anarch backup round trip skipped (restic isn't installed)\n"
fi
if LUMEN_NOTES="$tmp/notes.md" "$root/bin/anarch-note" buy milk >/dev/null && grep -q -- '- buy milk' "$tmp/notes.md"; then
  ok "anarch note adds a line"
else
  bad "anarch note"
fi

# anarch screentime: a report from counted time, and limits.
mkdir -p "$HOME/.local/state/lumen/screentime"
printf 'firefox\t1800\nfirefox\t1800\ncom.mitchellh.ghostty\t600\n' >"$HOME/.local/state/lumen/screentime/$(date +%F).tsv"
if out=$(script -qefc "$root/bin/anarch-screentime" /dev/null </dev/null) && grep -q '1h 10m' <<<"$out" && grep -qi 'firefox.*1h 00m' <<<"$out" &&
  "$root/bin/anarch-screentime" limit firefox 60 >/dev/null && grep -qx 'firefox 60' "$HOME/.config/lumen/screentime-limits" &&
  "$root/bin/anarch-screentime" limit firefox off >/dev/null && ! grep -q firefox "$HOME/.config/lumen/screentime-limits"; then
  ok "anarch screentime: report and limits"
else
  bad "anarch screentime: $out"
fi

# anarch reset: lists changed files and changes nothing on --dry-run.
mkdir -p "$HOME/.config/hypr" && echo '-- mine' >"$HOME/.config/hypr/bindings.lua"
if "$root/bin/anarch-reset" --dry-run 2>/dev/null | grep -q 'hypr/bindings.lua' && grep -q mine "$HOME/.config/hypr/bindings.lua" &&
  ! "$root/bin/anarch-reset" --dry-run 2>/dev/null | grep -q 'monitors.lua'; then
  ok "anarch reset --dry-run (screens and keyboard kept)"
else
  bad "anarch reset --dry-run"
fi

printf '\n'
if [[ $failures -eq 0 ]]; then
  printf '\e[1;32mAll checks passed.\e[0m\n'
else
  printf '\e[1;31m%d check(s) failed.\e[0m\n' "$failures"
  exit 1
fi
