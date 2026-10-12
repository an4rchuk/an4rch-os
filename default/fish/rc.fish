# An4rch shell defaults (fish). Managed by An4rch — put your own settings in
# ~/.config/fish/config.fish after the line that sources this file.

set -q LUMEN_PATH; or set -gx LUMEN_PATH $HOME/.local/share/lumen
fish_add_path -g $LUMEN_PATH/bin $HOME/.local/bin
set -gx EDITOR nvim
set -gx VISUAL nvim

if status is-login
    # Without a display manager, logging in on the first console starts the
    # desktop. (With greetd this never runs: it starts the session itself.)
    if test -z "$WAYLAND_DISPLAY"; and test "$XDG_VTNR" = 1; and command -q uwsm; and uwsm check may-start >/dev/null 2>&1
        exec uwsm start -- hyprland.desktop
    end
end

status is-interactive; or return

set -g fish_greeting
set -l theme (set -q XDG_CONFIG_HOME; and echo $XDG_CONFIG_HOME; or echo $HOME/.config)/lumen/current/theme
set -q STARSHIP_CONFIG; or set -gx STARSHIP_CONFIG $theme/starship.toml
set -gx BAT_THEME ansi
set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"
set -gx MANROFFOPT -c

command -q starship; and starship init fish | source
command -q zoxide; and zoxide init fish --cmd cd | source
command -q fzf; and fzf --fish 2>/dev/null | source
command -q mise; and mise activate fish | source

if command -q eza
    alias ls 'eza --group-directories-first --icons=auto'
    alias ll 'eza -l --group-directories-first --icons=auto --git --time-style=relative'
    alias la 'eza -la --group-directories-first --icons=auto --git --time-style=relative'
    alias lt 'eza --tree --level=2 --icons=auto --git-ignore'
end
command -q bat; and alias cat 'bat --paging=never --style=plain'
abbr -a g git
abbr -a gs 'git status -sb'
abbr -a gl 'git log --oneline --graph --decorate -20'
abbr -a v nvim
alias open xdg-open
alias copy wl-copy
alias paste wl-paste
alias install 'anarch-pkg add'
alias uninstall 'anarch-pkg rm'
alias update anarch-update
