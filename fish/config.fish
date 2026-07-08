if status is-interactive
    # Commands to run in interactive sessions can go here
    set -g fish_greeting

    fzf --fish | source
    zoxide init fish | source
    starship init fish | source
    $HOME/.local/bin/mise activate fish | source
    fish_config theme choose catppuccin-macchiato

    function y
        set tmp (mktemp -t "yazi-cwd.XXXXXX")
        command yazi $argv --cwd-file="$tmp"
        if read -z cwd < "$tmp"; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
            builtin cd -- "$cwd"
        end
        command rm -f -- "$tmp"
    end
end
