# shellcheck shell=bash
# Installer helpers: output, logging and package handling.

LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/lumen"
LOG="$LOG_DIR/install.log"
mkdir -p "$LOG_DIR"

if [[ -t 1 ]]; then
  BOLD=$'\e[1m' DIM=$'\e[2m' RESET=$'\e[0m'
  ACCENT=$'\e[38;2;157;140;255m' CYAN=$'\e[38;2;106;215;229m'
  GREEN=$'\e[38;2;159;220;155m' YELLOW=$'\e[38;2;241;211;139m' RED=$'\e[38;2;242;119;122m'
else
  BOLD="" DIM="" RESET="" ACCENT="" CYAN="" GREEN="" YELLOW="" RED=""
fi

banner() {
  printf '%s' "$ACCENT"
  cat <<'EOF'

    ██╗     ██╗   ██╗███╗   ███╗███████╗███╗   ██╗
    ██║     ██║   ██║████╗ ████║██╔════╝████╗  ██║
    ██║     ██║   ██║██╔████╔██║█████╗  ██╔██╗ ██║
    ██║     ██║   ██║██║╚██╔╝██║██╔══╝  ██║╚██╗██║
    ███████╗╚██████╔╝██║ ╚═╝ ██║███████╗██║ ╚████║
    ╚══════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝
EOF
  printf '%s    %sa calm, keyboard-driven Arch + Hyprland desktop%s\n\n' "$RESET" "$DIM" "$RESET"
}

STEP_NO=0
STEP_TOTAL=0
step() {
  STEP_NO=$((STEP_NO + 1))
  printf '\n%s%s[%d/%d]%s %s%s%s\n' "$BOLD" "$ACCENT" "$STEP_NO" "$STEP_TOTAL" "$RESET" "$BOLD" "$*" "$RESET"
  printf '\n==> [%d/%d] %s (%s)\n' "$STEP_NO" "$STEP_TOTAL" "$*" "$(date '+%F %T')" >>"$LOG"
}

info() { printf '  %s•%s %s\n' "$CYAN" "$RESET" "$*"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() {
  printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"
  printf 'WARN: %s\n' "$*" >>"$LOG"
  WARNINGS+=("$*")
}
fail() {
  printf '\n  %s✗ %s%s\n' "$RED" "$*" "$RESET" >&2
  printf '  %sFull log: %s%s\n\n' "$DIM" "$LOG" "$RESET" >&2
  exit 1
}
WARNINGS=()

# run DESCRIPTION CMD... — run quietly with a spinner, output goes to the log.
run() {
  local desc="$1"
  shift
  printf 'RUN: %s\n' "$*" >>"$LOG"
  if [[ ! -t 1 || -n "${LUMEN_VERBOSE:-}" ]]; then
    info "$desc"
    "$@" >>"$LOG" 2>&1 || fail "$desc failed"
    return
  fi
  "$@" >>"$LOG" 2>&1 &
  local pid=$! frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  %s%s%s %s' "$ACCENT" "${frames:i++%${#frames}:1}" "$RESET" "$desc"
    sleep 0.1
  done
  if wait "$pid"; then
    printf '\r  %s✓%s %s\e[K\n' "$GREEN" "$RESET" "$desc"
  else
    printf '\r  %s✗%s %s\e[K\n' "$RED" "$RESET" "$desc"
    tail -n 15 "$LOG" | sed 's/^/    /' >&2
    fail "$desc failed"
  fi
}

ask_yes() { # ask_yes QUESTION [default y|n]
  local q="$1" def="${2:-y}" reply
  [[ -n "${LUMEN_YES:-}" ]] && { [[ "$def" == y ]]; return; }
  if [[ "$def" == y ]]; then
    read -rp "  ${BOLD}?${RESET} $q [Y/n] " reply </dev/tty
    [[ -z "$reply" || "$reply" == [yY]* ]]
  else
    read -rp "  ${BOLD}?${RESET} $q [y/N] " reply </dev/tty
    [[ "$reply" == [yY]* ]]
  fi
}

ask_choice() { # ask_choice VAR "Question" default option...
  local var="$1" q="$2" def="$3"
  shift 3
  if [[ -n "${LUMEN_YES:-}" ]]; then
    printf -v "$var" '%s' "$def"
    return
  fi
  local i=1 o reply
  printf '  %s?%s %s\n' "$BOLD" "$RESET" "$q"
  for o in "$@"; do
    if [[ "$o" == "$def" ]]; then printf '    %s%d)%s %s %s(default)%s\n' "$ACCENT" "$i" "$RESET" "$o" "$DIM" "$RESET"; else printf '    %s%d)%s %s\n' "$ACCENT" "$i" "$RESET" "$o"; fi
    i=$((i + 1))
  done
  read -rp "    → " reply </dev/tty
  if [[ "$reply" =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= $#)); then
    local -a opts=("$@")
    printf -v "$var" '%s' "${opts[$((reply - 1))]}"
  else
    printf -v "$var" '%s' "$def"
  fi
}

# --- packages --------------------------------------------------------------------

in_repos() { pacman -Si "$1" >/dev/null 2>&1; }
installed() { pacman -Qq "$1" >/dev/null 2>&1; }

# pkg_install REQUIRED|OPTIONAL PKG... — repo packages in one transaction,
# anything not in the repos from the AUR. Missing optional packages are
# skipped with a warning instead of stopping the install.
pkg_install() {
  local mode="$1"
  shift
  local repo=() aur=() p
  for p in "$@"; do
    installed "$p" && continue
    if in_repos "$p"; then
      repo+=("$p")
    else
      aur+=("$p")
    fi
  done
  if [[ ${#repo[@]} -gt 0 ]]; then
    run "Installing ${#repo[@]} packages: ${repo[*]:0:6}$([[ ${#repo[@]} -gt 6 ]] && echo " …")" \
      sudo pacman -S --needed --noconfirm "${repo[@]}"
  fi
  for p in "${aur[@]}"; do
    if command -v yay >/dev/null && yay -Si "$p" >/dev/null 2>&1; then
      run "Building $p from the AUR" yay -S --needed --noconfirm --answerdiff None --answerclean None --removemake "$p"
    elif [[ "$mode" == REQUIRED ]]; then
      fail "Required package '$p' is not available in the repos or the AUR"
    else
      warn "Skipped '$p' (not found in the repos or the AUR)"
    fi
  done
}

# copy_config SRC DEST — install a config file without clobbering user edits.
# Existing files that differ are moved to the backup directory first.
BACKUP_DIR="$HOME/.config/lumen-backup-$(date +%Y%m%d-%H%M%S)"
copy_config() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    if cmp -s "$src" "$dest"; then
      return 0
    fi
    # Mirror the path under the backup dir: ~/.config/x → backup/x, ~/.zshrc → backup/.zshrc
    local rel="${dest#"$HOME"/}"
    rel="${rel#.config/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    mv "$dest" "$BACKUP_DIR/$rel"
  fi
  cp "$src" "$dest"
}
