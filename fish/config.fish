if status is-interactive
    # Commands to run in interactive sessions can go here
    set -g fish_greeting
    zoxide init fish | source
    
    if env | grep -q WSL
        set -gx IS_WSL=true
        set -gx WINUSER=$(cmd.exe /c 'echo %USERNAME%' | tr -d '\r')
    end

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

    fish_config theme choose "Catppuccin Macchiato"
end
