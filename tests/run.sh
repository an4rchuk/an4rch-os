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
fi

step "Shell scripts"
mapfile -t scripts < <(grep -lE '^#!/usr/bin/env bash|^#!/bin/bash' "$root"/bin/* "$root"/install.sh "$root"/boot.sh "$root"/install/*.sh "$root"/tests/*.sh 2>/dev/null)
if command -v shellcheck >/dev/null; then
  if shellcheck -x -P "$root/lib" -e SC1091 -S warning "${scripts[@]}" "$root/lib/lumen.sh"; then
    ok "shellcheck: ${#scripts[@]} scripts"
  else
    bad "shellcheck found issues"
  fi
else
  bad "shellcheck not installed"
fi
for s in "${scripts[@]}"; do bash -n "$s" || bad "syntax: $s"; done
ok "bash -n"

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
