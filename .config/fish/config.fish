if status is-interactive
    # Commands to run in interactive sessions can go here
    set -g fish_greeting
    fish_add_path /opt/nvim/bin
    fish_add_path /home/fabi/.local/bin
    zoxide init fish | source

    alias gs='git status'
    alias gl='git log'
    alias gd='git diff'
    alias gc='git commit'
    alias ga='git add'
    alias gp='git push origin (git branch --show-current)'
    alias bat='batcat'
    alias cr='clear'

    function y
        set tmp (mktemp -t "yazi-cwd.XXXXXX")
        yazi $argv --cwd-file="$tmp"
        if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
            builtin cd -- "$cwd"
        end
        rm -f -- "$tmp"
    end

    fish_config theme save "Catppuccin Macchiato"
end
