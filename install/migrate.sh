#!/usr/bin/env bash
# Run after `lumen-update` pulls a new version.
#
#   - installs config files that are new in this version (existing files are
#     never touched — they're yours)
#   - runs each script in install/migrations/ exactly once, in name order
#
#   install/migrate.sh             apply pending migrations
#   install/migrate.sh --mark-all  record every migration as done (fresh install)
set -euo pipefail

LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/lumen/migrations"
mkdir -p "$state"

if [[ "${1:-}" == --mark-all ]]; then
  for m in "$LUMEN_PATH"/install/migrations/*.sh; do
    [[ -f "$m" ]] && touch "$state/$(basename "$m")"
  done
  exit 0
fi

# New config files only.
while IFS= read -r -d '' f; do
  rel="${f#"$LUMEN_PATH/config/"}"
  case "$rel" in
    zsh/zshrc) dest="$HOME/.zshrc" ;;
    zsh/zprofile) dest="$HOME/.zprofile" ;;
    *) dest="$HOME/.config/$rel" ;;
  esac
  if [[ ! -e "$dest" ]]; then
    mkdir -p "$(dirname "$dest")"
    cp "$f" "$dest"
    echo "  + ${dest/#$HOME/\~}"
  fi
done < <(find "$LUMEN_PATH/config" -type f -print0)

# Launchers and icons for an4rch's own apps are managed by an4rch: always refresh.
data="${XDG_DATA_HOME:-$HOME/.local/share}"
mkdir -p "$data/applications" "$data/icons/hicolor/scalable/apps"
cp "$LUMEN_PATH"/share/applications/*.desktop "$data/applications/"
cp "$LUMEN_PATH"/share/icons/hicolor/scalable/apps/*.svg "$data/icons/hicolor/scalable/apps/"
update-desktop-database -q "$data/applications" 2>/dev/null || true

for m in "$LUMEN_PATH"/install/migrations/*.sh; do
  [[ -f "$m" ]] || continue
  name=$(basename "$m")
  [[ -f "$state/$name" ]] && continue
  echo "  → migration $name"
  if bash "$m"; then
    touch "$state/$name"
  else
    echo "  ! migration $name failed; it will be retried next update" >&2
  fi
done
