{ pkgs, lib, ... }:
let
  isWSL = builtins.getEnv "IS_WSL";
  winUser = builtins.getEnv "WINUSER";
  home = builtins.getEnv "HOME";
  dotfiles = if isWSL == "true" then
    "/mnt/c/Users/${winUser}/.dotfiles"
  else
    "${home}/.dotfiles";
in {
  home.username = "fabi";
  home.homeDirectory = "/home/fabi";
  home.stateVersion = "25.05";
  home.shell.enableShellIntegration = false;

  home.activation.fish = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    echo -e "\nConfiguring shell ..."
    FISH_SHELL="$HOME/.nix-profile/bin/fish"
    if ! grep -qx "$FISH_SHELL" /etc/shells; then
        run echo "$FISH_SHELL" | sudo tee -a /etc/shells
    fi
    run chsh -s "$FISH_SHELL"
    run exec fish
  '';

  home.packages = [
    pkgs.ripgrep
    pkgs.fd
    pkgs.bat
    pkgs.wl-clipboard
    pkgs.zoxide
    pkgs.delta
    pkgs.git
    pkgs.fish
    pkgs.zellij
  ];

  programs.neovim = {
    enable = true;
    extraPackages = [
      pkgs.go
      pkgs.jdk
      pkgs.maven
      pkgs.julia
      pkgs.lua5_1
      pkgs.nodejs
      pkgs.php
      pkgs.python3
      pkgs.ruby
      pkgs.rustup
      pkgs.dotnet-sdk
      pkgs.fzf
      pkgs.tree-sitter
    ];
  };

  programs.yazi = {
    enable = true;
    plugins = {
      "yatline" = pkgs.yaziPlugins.yatline;
      "yatline-catppuccin" = pkgs.yaziPlugins.yatline-catppuccin;
      "full-border" = pkgs.yaziPlugins.full-border;
      "whoosh" =
        (builtins.fetchGit "https://github.com/WhoSowSee/whoosh.yazi").outPath;
    };
  };

  home.file = {
    ".gitconfig".source = "${dotfiles}/.gitconfig";
    "fish" = {
      source = "${dotfiles}/fish";
      target = ".config/fish";
      recursive = true;
    };
    "yazi" = {
      source = "${dotfiles}/yazi";
      target = ".config/yazi";
      recursive = true;
    };
    "zellij" = {
      source = "${dotfiles}/zellij";
      target = ".config/zellij";
      recursive = true;
    };
    "nvim" = {
      source = "${dotfiles}/nvim";
      target = ".config/nvim";
      recursive = true;
    };
    "nix" = {
      source = "${dotfiles}/nix";
      target = ".config/nix";
      recursive = true;
    };
    "home-manager" = {
      source = "${dotfiles}/home-manager";
      target = ".config/home-manager";
      recursive = true;
    };
    # fish theme
    "Catppuccin Macchiato.theme" = {
      source = builtins.fetchurl {
        url =
          "https://raw.githubusercontent.com/catppuccin/fish/refs/heads/main/themes/Catppuccin%20Macchiato.theme";
      };
      target = ".config/fish/themes/Catppuccin Macchiato.theme";
    };
    # yazi theme
    "theme.toml" = {
      source = builtins.fetchurl {
        url =
          "https://raw.githubusercontent.com/catppuccin/yazi/refs/heads/main/themes/macchiato/catppuccin-macchiato-blue.toml";
      };
      target = ".config/yazi/theme.toml";
    };
  };

  programs.home-manager.enable = true;
}
