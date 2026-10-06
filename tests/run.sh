#!/usr/bin/env bash
# Lumen test suite. Runs on any Linux box (no Hyprland needed):
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
  if out=$("$root/bin/lumen-theme" set "$name" 2>&1) && ! grep -rq '{{' "$HOME/.config/lumen/current/theme/"; then
    ok "$name"
  else
    bad "$name: $out"
  fi
done
"$root/bin/lumen-theme" set lumen >/dev/null

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

step "Lumen apps (Start menu, App Store, Welcome)"
if python3 -m py_compile "$root"/apps/*/*.py "$root/bin/lumen-wallgen" 2>&1; then ok "Python compiles"; else bad "Python syntax"; fi
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
# binding and app shortcut must point at a command Lumen ships (or a
# well-known system one), so no menu item silently does nothing.
if python3 - "$root" <<'PY'
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
ours = {p.name for p in (root / "bin").iterdir()}
refs = []  # (where, command)
def add(where, cmd):
    if cmd.startswith("lumen-"):
        refs.append((where, cmd))
for f in [root / "bin/lumen-menu", *root.glob("apps/*/*.py"), root / "config/waybar/config.jsonc",
          root / "config/waybar/taskbar.jsonc", root / "default/hypr/binds.lua"]:
    text = f.read_text()
    for m in re.finditer(r'\$bin/(lumen-[a-z-]+)', text): add(f.name, m.group(1))
    for m in re.finditer(r'["\[]\s*"?(lumen-[a-z-]+)"', text): add(f.name, m.group(1))
    for m in re.finditer(r'"on-click[a-z-]*":\s*"(lumen-[a-z-]+)', text): add(f.name, m.group(1))
    for m in re.finditer(r'(?<![\w.])cmd\("([a-z-]+)"', text): add(f.name, "lumen-" + m.group(1))
for f in root.glob("share/applications/*.desktop"):
    m = re.search(r"^Exec=(\S+)", f.read_text(), re.M)
    if m: add(f.name, m.group(1))
# Lua files are referenced as lumen-<name>.lua etc. and app ids as lumen-start; keep real commands only.
skip = {"lumen-logo", "lumen-installer", "lumen-floating", "lumen-start.desktop"}
missing = sorted({(w, c) for w, c in refs if c not in ours and c not in skip and not c.endswith((".desktop", "-"))
                  and c != "lumen-os-install" and (root / "iso/airootfs/usr/local/bin" / c).exists() is False})
for w, c in missing:
    print(f"  {w}: {c} doesn't exist")
print(f"  {len(set(c for _, c in refs))} commands referenced from menus, bars, binds and apps")
sys.exit(1 if missing else 0)
PY
then ok "every menu item points at a real command"; else bad "menu items point at missing commands"; fi

# Headless smoke test: each GTK app starts and renders without a traceback.
if command -v xvfb-run >/dev/null && python3 -c 'import gi; gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")' 2>/dev/null; then
  for app in "lumen-start/lumen_start.py --show" "lumen-store/lumen_store.py" "lumen-welcome/lumen_welcome.py" "lumen-installer/lumen_installer.py" \
    "lumen-settings/lumen_settings.py" "lumen-audio/lumen_audio.py --show" "lumen-desktop/lumen_desktop.py"; do
    log="$tmp/gui.log"
    # shellcheck disable=SC2086
    LUMEN_INSTALLER_DEMO=1 LUMEN_SETTINGS_ALL_PAGES=1 GDK_BACKEND=x11 GSK_RENDERER=cairo GTK_A11Y=none timeout 25 xvfb-run -a dbus-run-session -- \
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
  if python3 "$root/bin/lumen-wallgen" --theme lumen --theme catppuccin-latte --size 640x360 --out "$tmp/walls" >/dev/null; then
    ok "$(find "$tmp/walls" -type f | wc -l) wallpapers generated"
  else
    bad "lumen-wallgen failed"
  fi
else
  printf '  - skipped (Pillow not installed)\n'
fi

printf '\n'
if [[ $failures -eq 0 ]]; then
  printf '\e[1;32mAll checks passed.\e[0m\n'
else
  printf '\e[1;31m%d check(s) failed.\e[0m\n' "$failures"
  exit 1
fi
