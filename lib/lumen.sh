# shellcheck shell=bash
# shellcheck disable=SC2034  # settings are read by the commands that source this file
# Lumen shared shell library. Sourced by every `lumen-*` command.
#
# Keep this file dependency-free: it must load on a half-installed system so
# `lumen doctor` can explain what is missing.

LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
LUMEN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/lumen"
LUMEN_CURRENT="$LUMEN_CONFIG/current"
LUMEN_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/lumen"
LUMEN_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/lumen"
LUMEN_WALLPAPERS="${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/lumen"
export LUMEN_PATH LUMEN_CONFIG LUMEN_CURRENT LUMEN_STATE LUMEN_CACHE LUMEN_WALLPAPERS

# --- settings ---------------------------------------------------------------
# settings.conf is plain `KEY=value` shell syntax. Defaults live here so a
# missing or partial file never breaks a command.
LUMEN_TERMINAL=ghostty
LUMEN_BROWSER=firefox
LUMEN_EDITOR=code
LUMEN_FILES=nautilus
LUMEN_SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
LUMEN_RECORDING_DIR="$HOME/Videos/Recordings"
LUMEN_NIGHTLIGHT_TEMP=4300
LUMEN_TITLEBARS=yes   # title bars with close/maximise/minimise buttons
LUMEN_TASKBAR=no      # taskbar along the bottom of the screen
# shellcheck source=/dev/null
[[ -f "$LUMEN_CONFIG/settings.conf" ]] && source "$LUMEN_CONFIG/settings.conf"

# --- small helpers -------------------------------------------------------------
has() { command -v "$1" >/dev/null 2>&1; }

die() {
  printf '\e[31m✗\e[0m %s\n' "$*" >&2
  exit 1
}

# notify TITLE [BODY] [extra notify-send args...]
notify() {
  local title="$1" body="${2:-}"
  shift 2 2>/dev/null || shift $#
  has notify-send || { printf '%s %s\n' "$title" "$body"; return; }
  # No notification service (an install from a console): not an error.
  notify-send -a Lumen "$@" "$title" "$body" 2>/dev/null || printf '%s %s\n' "$title" "$body"
}

# Run a program detached from the caller, as its own systemd scope when the
# session is managed by uwsm (keeps logs and resource accounting tidy).
launch() {
  if has uwsm && systemctl --user is-active -q graphical-session.target 2>/dev/null; then
    uwsm app -- "$@" >/dev/null 2>&1 &
  else
    setsid -f "$@" >/dev/null 2>&1
  fi
}

# --- menus -------------------------------------------------------------------
# menu PROMPT [fuzzel args...] < choices
# Prints the chosen line. Opening a menu while one is visible closes it, so
# every menu hotkey also works as a toggle.
menu() {
  local prompt="$1"
  shift
  if pgrep -x fuzzel >/dev/null; then
    pkill -x fuzzel
    return 1
  fi
  fuzzel --dmenu --prompt "$prompt  " "$@"
}

# ask PROMPT [placeholder] — free-text input, prints what was typed.
ask() {
  local prompt="$1" placeholder="${2:-}"
  pkill -x fuzzel 2>/dev/null
  fuzzel --dmenu --prompt-only "$prompt  " --placeholder "$placeholder"
}

# ask_secret PROMPT — password input.
ask_secret() {
  pkill -x fuzzel 2>/dev/null
  fuzzel --dmenu --prompt-only "$1  " --password
}

# confirm QUESTION — yes/no menu, returns 0 on yes.
confirm() {
  local answer
  answer=$(printf '  Yes\n  No\n' | menu "$1" --lines 2 --width 30) || return 1
  [[ "$answer" == *Yes ]]
}

# --- terminal ------------------------------------------------------------------
# term [--float] [--title TITLE] [--hold] [-- CMD...]
# Opens the configured terminal. --float uses the `lumen.floating` class, which
# Hyprland centres and sizes like a dialog.
term() {
  local class="" title="" hold=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --float) class="lumen.floating" ;;
      --title) title="$2"; shift ;;
      --hold) hold=1 ;;
      --) shift; break ;;
      *) break ;;
    esac
    shift
  done

  local -a cmd=("$@")
  if [[ $hold -eq 1 && ${#cmd[@]} -gt 0 ]]; then
    cmd=(bash -c '"$@"; status=$?; printf "\n\e[2mPress any key to close…\e[0m"; read -rsn1; exit $status' _ "${cmd[@]}")
  fi

  local t="$LUMEN_TERMINAL"
  has "$t" || for t in ghostty alacritty kitty foot; do has "$t" && break; done

  local -a argv=("$t")
  case "$t" in
    ghostty)
      [[ -n "$class" ]] && argv+=("--class=$class")
      [[ -n "$title" ]] && argv+=("--title=$title")
      [[ ${#cmd[@]} -gt 0 ]] && argv+=(-e "${cmd[@]}")
      ;;
    alacritty)
      [[ -n "$class" ]] && argv+=(--class "$class")
      [[ -n "$title" ]] && argv+=(--title "$title")
      [[ ${#cmd[@]} -gt 0 ]] && argv+=(-e "${cmd[@]}")
      ;;
    kitty)
      [[ -n "$class" ]] && argv+=(--class "$class")
      [[ -n "$title" ]] && argv+=(--title "$title")
      [[ ${#cmd[@]} -gt 0 ]] && argv+=("${cmd[@]}")
      ;;
    foot)
      [[ -n "$class" ]] && argv+=(--app-id "$class")
      [[ -n "$title" ]] && argv+=(--title "$title")
      [[ ${#cmd[@]} -gt 0 ]] && argv+=("${cmd[@]}")
      ;;
  esac
  launch "${argv[@]}"
}

# --- waybar --------------------------------------------------------------------
# Custom bar modules listen on real-time signals; see config/waybar/config.jsonc.
bar_signal() {
  local n
  case "$1" in
    idle) n=8 ;;
    dnd) n=9 ;;
    record) n=10 ;;
    nightlight) n=11 ;;
    updates) n=12 ;;
    *) return ;;
  esac
  pkill -RTMIN+"$n" waybar 2>/dev/null || true
}

# --- themes --------------------------------------------------------------------
# theme_dir NAME — user themes in ~/.config/lumen/themes shadow bundled ones.
theme_dir() {
  local d
  for d in "$LUMEN_CONFIG/themes/$1" "$LUMEN_PATH/themes/$1"; do
    [[ -f "$d/theme.conf" ]] && { echo "$d"; return 0; }
  done
  return 1
}

theme_list() {
  local d
  for d in "$LUMEN_CONFIG"/themes/*/theme.conf "$LUMEN_PATH"/themes/*/theme.conf; do
    [[ -f "$d" ]] && basename "$(dirname "$d")"
  done | sort -u
}

theme_current() {
  cat "$LUMEN_CURRENT/theme.name" 2>/dev/null || echo lumen
}

# theme_get NAME KEY — read one value from a theme.conf.
theme_get() {
  local dir
  dir=$(theme_dir "$1") || return 1
  sed -n -E "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*\$/\1/p" "$dir/theme.conf" | head -n1
}
