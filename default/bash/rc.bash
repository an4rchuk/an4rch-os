# shellcheck shell=bash
# An4rch shell defaults (bash). Managed by An4rch — put your own settings in
# ~/.bashrc after the line that sources this file.

export LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
case ":$PATH:" in *":$LUMEN_PATH/bin:"*) ;; *) PATH="$LUMEN_PATH/bin:$HOME/.local/bin:$PATH" ;; esac
export PATH

[[ $- == *i* ]] || return 0

# --- History -------------------------------------------------------------------
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
mkdir -p "$(dirname "$HISTFILE")"
HISTSIZE=50000
HISTFILESIZE=50000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize globstar autocd 2>/dev/null
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# --- Completion ----------------------------------------------------------------
# shellcheck source=/dev/null
[[ -f /usr/share/bash-completion/bash_completion ]] && source /usr/share/bash-completion/bash_completion
bind 'set completion-ignore-case on' 2>/dev/null
bind 'set show-all-if-ambiguous on' 2>/dev/null
bind '"\e[A": history-search-backward' 2>/dev/null
bind '"\e[B": history-search-forward' 2>/dev/null

# --- Theme-aware tools -----------------------------------------------------------
_lumen_theme="${XDG_CONFIG_HOME:-$HOME/.config}/lumen/current/theme"
# shellcheck source=/dev/null
[[ -f "$_lumen_theme/fzf.sh" ]] && source "$_lumen_theme/fzf.sh"
export STARSHIP_CONFIG="${STARSHIP_CONFIG:-$_lumen_theme/starship.toml}"
export BAT_THEME="${BAT_THEME:-ansi}"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export MANROFFOPT="-c"

command -v starship >/dev/null && eval "$(starship init bash)"
command -v zoxide >/dev/null && eval "$(zoxide init bash --cmd cd)"
# shellcheck source=/dev/null
command -v fzf >/dev/null && source <(fzf --bash 2>/dev/null)
command -v mise >/dev/null && eval "$(mise activate bash)"

# --- Aliases -------------------------------------------------------------------
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -l --group-directories-first --icons=auto --git --time-style=relative'
  alias la='eza -la --group-directories-first --icons=auto --git --time-style=relative'
  alias lt='eza --tree --level=2 --icons=auto --git-ignore'
fi
command -v bat >/dev/null && alias cat='bat --paging=never --style=plain'
alias ..='cd ..'
alias ...='cd ../..'
alias g='git'
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate -20'
alias v='nvim'
alias open='xdg-open'
alias copy='wl-copy'
alias paste='wl-paste'
alias install='anarch-pkg add'
alias uninstall='anarch-pkg rm'
alias update='anarch-update'
unset _lumen_theme
