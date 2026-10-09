# shellcheck shell=bash
# shellcheck disable=SC2034  # settings are read by the commands that source this file
# An4rch shared shell library. Sourced by every `lumen-*` command.
#
# Keep this file dependency-free: it must load on a half-installed system so
# `anarch doctor` can explain what is missing.

LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
LUMEN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/lumen"
LUMEN_CURRENT="$LUMEN_CONFIG/current"
LUMEN_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/lumen"
LUMEN_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/lumen"
LUMEN_WALLPAPERS="${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/lumen"
export LUMEN_PATH LUMEN_CONFIG LUMEN_CURRENT LUMEN_STATE LUMEN_CACHE LUMEN_WALLPAPERS

# The taskbar's waybar runs on a private D-Bus session: two waybars on the
# session bus count as one app, and the second crashes a few minutes in.
# Commands it starts get the real session bus back here.
if [[ -n "${LUMEN_DBUS:-}" && "${DBUS_SESSION_BUS_ADDRESS:-}" != "$LUMEN_DBUS" ]]; then
  export DBUS_SESSION_BUS_ADDRESS="$LUMEN_DBUS"
fi

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

# need PKG... — install the packages a feature uses if they're missing
# (pacman asks first; AUR names go through the AUR helper).
need() {
  local missing=() p
  for p in "$@"; do pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p"); done
  [[ ${#missing[@]} -eq 0 ]] && return 0
  printf '\e[2mThis needs: %s\e[0m\n' "${missing[*]}"
  "$LUMEN_PATH/bin/anarch-pkg" add "${missing[@]}"
}

# in_terminal "$0" "$@" — rerun in a floating terminal when started from a
# menu or key (no terminal to ask questions in).
in_terminal() {
  [[ -t 0 ]] && return 0
  term --float --hold --title "an4rch" -- "$@"
  exit 0
}

# is_server — installed as An4rch Server (no desktop).
is_server() { [[ "$(cat "$LUMEN_CONFIG/edition" 2>/dev/null)" == server ]]; }

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
  notify-send -an An4rch "$@" "$title" "$body" 2>/dev/null || printf '%s %s\n' "$title" "$body"
}

# Run a program detached from the caller, as its own systemd scope when the
# session is managed by uwsm (keeps logs and resource accounting tidy).
# systemd-run directly rather than `uwsm app`: the same scope, without
# starting Python for every app that opens (much quicker, above all from USB).
#
# Apps must never fail silently: a missing program says so; if the scope
# can't be made the app runs directly; and an app that quits with an error
# within a few seconds shows why (also in ~/.local/state/lumen/apps.log,
# which `anarch doctor` reports). LUMEN_LAUNCH_NAME names it in messages.
launch() {
  local name="${LUMEN_LAUNCH_NAME:-${1##*/}}"
  if ! has "$1"; then
    notify "Can't open $name" "It isn't installed. Find it in the App Store (⊞ + A)." -u critical -i dialog-error
    return 1
  fi
  local state="${XDG_STATE_HOME:-$HOME/.local/state}/lumen"
  mkdir -p "$state"
  (
    # Never stop half-way (callers use set -e / pipefail): always report.
    set +e +o pipefail
    err=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/anarch-launch.XXXXXX") || err=/dev/null
    start=$SECONDS rc=0
    # Only the last few KB of an app's error output are kept, however long it runs.
    if systemctl --user is-active -q graphical-session.target 2>/dev/null; then
      systemd-run --user --quiet --collect --scope --slice=app-graphical.slice -- "$@" 2> >(tail -c 4000 >"$err") || rc=$?
      sleep 0.2
      if ((rc != 0)) && grep -qE '^Failed to (start transient|connect|create)' "$err"; then
        printf '%s  %s: no app scope (%s); starting it directly\n' "$(date '+%F %T')" "$name" "$(head -n1 "$err")" >>"$state/apps.log"
        rc=0
        "$@" 2> >(tail -c 4000 >"$err") || rc=$?
        sleep 0.2
      fi
    else
      setsid "$@" 2> >(tail -c 4000 >"$err") || rc=$?
      sleep 0.2
    fi
    # Only inside a desktop session (not, e.g., the installer setting up
    # the wallpaper with no display).
    if ((rc != 0 && rc != 130 && rc != 143)) && [[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]]; then
      why=$(grep -v '^\s*$' "$err" | grep -viE 'warn|deprecat|gtk-message|dbind' | tail -n 3 | cut -c1-200)
      printf '%s  %s exited with code %s after %ss: %s\n' "$(date '+%F %T')" "$name" "$rc" "$((SECONDS - start))" \
        "$(tr '\n' ' ' <<<"$why")" >>"$state/apps.log"
      if ((SECONDS - start < 10)); then
        notify "$name couldn't start" "${why:-It stopped with error code $rc.}" -u critical -i dialog-error
      fi
    fi
    if [[ -f "$state/apps.log" ]]; then tail -n 200 "$state/apps.log" >"$state/apps.log.tmp" && mv "$state/apps.log.tmp" "$state/apps.log"; fi
    [[ "$err" == /dev/null ]] || rm -f "$err"
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
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
# term [--float] [--class CLASS] [--title TITLE] [--hold] [-- CMD...]
# Opens the configured terminal. --float uses the `lumen.floating` class, which
# Hyprland centres and sizes like a dialog.
term() {
  local class="" title="" hold=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --float) class="lumen.floating" ;;
      --class) class="$2"; shift ;;
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
    focus) n=14 ;;
    *) return ;;
  esac
  pkill -RTMIN+"$n" waybar 2>/dev/null || true
}

# --- themes --------------------------------------------------------------------
DEFAULT_THEME=an4rch

# theme_renamed NAME — the theme to use for NAME: themes that were renamed or
# retired map to their replacement (unless you have a theme of your own by
# that name). The signature theme was "lumen" before 1.1.0; the other old
# palettes gave way to the anarchism themes in 1.1.1.
theme_renamed() {
  if [[ -f "$LUMEN_CONFIG/themes/$1/theme.conf" ]]; then echo "$1"; return; fi
  case "$1" in
    lumen | an4rch-violet | cachy | catppuccin-mocha | tokyo-night | gruvbox | nord | rose-pine | everforest | kanagawa) echo "$DEFAULT_THEME" ;;
    catppuccin-latte) echo an4rch-light ;;
    *) echo "$1" ;;
  esac
}

# theme_dir NAME — user themes in ~/.config/lumen/themes shadow bundled ones.
theme_dir() {
  local d
  set -- "$(theme_renamed "$1")"
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
  local t
  t=$(cat "$LUMEN_CURRENT/theme.name" 2>/dev/null) || t=""
  [[ -z "$t" ]] && t=$DEFAULT_THEME
  theme_renamed "$t"
}

# theme_get NAME KEY — read one value from a theme.conf.
theme_get() {
  local dir
  dir=$(theme_dir "$1") || return 1
  sed -n -E "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*\$/\1/p" "$dir/theme.conf" | head -n1
}
