if status is-interactive
    # Commands to run in interactive sessions can go here
    set -g fish_greeting
    set -gx EDITOR nvim

    alias gs='git status'
    alias gl='git log'
    alias gd='git diff'
    alias gc='git commit'
    alias ga='git add'
    alias gp='git push origin (git branch --show-current)'
    alias bat='batcat'
    alias cr='clear'

    zoxide init fish | source
    /home/$USER/.local/bin/mise activate fish | source

    function y
        set tmp (mktemp -t "yazi-cwd.XXXXXX")
        yazi $argv --cwd-file="$tmp"
        if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
            builtin cd -- "$cwd"
        end
        rm -f -- "$tmp"
    end

    fish_config theme choose catppuccin-macchiato
end
