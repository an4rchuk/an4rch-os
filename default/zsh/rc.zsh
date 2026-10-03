# Lumen shell defaults (zsh). Managed by Lumen — put your own settings in
# ~/.zshrc after the line that sources this file.

export LUMEN_PATH="${LUMEN_PATH:-$HOME/.local/share/lumen}"
typeset -U path
path=("$LUMEN_PATH/bin" "$HOME/.local/bin" $path)

# --- History -------------------------------------------------------------------
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
[[ -d "${HISTFILE:h}" ]] || mkdir -p "${HISTFILE:h}"
HISTSIZE=50000
SAVEHIST=50000
setopt EXTENDED_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS SHARE_HISTORY INC_APPEND_HISTORY

# --- Behaviour -----------------------------------------------------------------
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS INTERACTIVE_COMMENTS NO_BEEP EXTENDED_GLOB
WORDCHARS='*?_-.[]~&;!#$%^(){}<>'

# --- Completion ----------------------------------------------------------------
autoload -Uz compinit
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zcompdump-$ZSH_VERSION"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{8}── %d ──%f'
zmodload zsh/complist

# --- Keys ----------------------------------------------------------------------
bindkey -e
bindkey '^[[1;5C' forward-word      # Ctrl+Right
bindkey '^[[1;5D' backward-word     # Ctrl+Left
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
bindkey '^H' backward-kill-word     # Ctrl+Backspace
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

# --- Theme-aware tools -----------------------------------------------------------
_lumen_theme="${XDG_CONFIG_HOME:-$HOME/.config}/lumen/current/theme"
[[ -f "$_lumen_theme/fzf.sh" ]] && source "$_lumen_theme/fzf.sh"
export STARSHIP_CONFIG="${STARSHIP_CONFIG:-$_lumen_theme/starship.toml}"
export BAT_THEME="${BAT_THEME:-ansi}"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export MANROFFOPT="-c"

(( $+commands[starship] )) && eval "$(starship init zsh)"
(( $+commands[zoxide] )) && eval "$(zoxide init zsh --cmd cd)"
(( $+commands[fzf] )) && source <(fzf --zsh)
(( $+commands[mise] )) && eval "$(mise activate zsh)"

# --- Aliases -------------------------------------------------------------------
if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -l --group-directories-first --icons=auto --git --time-style=relative'
  alias la='eza -la --group-directories-first --icons=auto --git --time-style=relative'
  alias lt='eza --tree --level=2 --icons=auto --git-ignore'
fi
(( $+commands[bat] )) && alias cat='bat --paging=never --style=plain'
alias ..='cd ..'
alias ...='cd ../..'
alias g='git'
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate -20'
alias v='nvim'
alias open='xdg-open'
alias copy='wl-copy'
alias paste='wl-paste'
alias ff='fzf --preview "bat --color=always --style=numbers {}"'

# Quick install / remove through Lumen's package helper.
alias install='lumen-pkg add'
alias uninstall='lumen-pkg rm'
alias update='lumen-update'

# --- Plugins (last, as their docs ask) -------------------------------------------
for _p in /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
          /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  [[ -f "$_p" ]] && source "$_p"
done
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
unset _p _lumen_theme
