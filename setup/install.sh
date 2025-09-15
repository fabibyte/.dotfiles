#!/bin/bash

# check if script is running in WSL
if env | grep -q WSL; then
    export IS_WSL=true
    export WINUSER=$(cmd.exe /c 'echo %USERNAME%' | tr -d '\r')
    FOLDER="/mnt/c/Users/$WINUSER/.dotfiles/"
else
    FOLDER="$HOME/.dotfiles"
fi

# clone dotfiles
if [ ! -d "$FOLDER" ]; then
    echo "Cloning config files ..."
    mkdir -p $FOLDER
    git clone "https://github.com/fabibyte/.dotfiles.git" $FOLDER
fi

# install nix if its not already there
if ! nix --version; then
    echo -e "\nInstalling nix ..."
    sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
    source /etc/profile.d/nix.sh
fi

# install home-manager if its not already there
if ! home-manager --version; then
    echo -e "\nInstalling home-manager ..."
    nix run home-manager/master -- --extra-experimental-features "nix-command flakes" switch --impure --flake "$FOLDER/home-manager/"
else
    echo -e "\nActivate home-manager config ..."
    home-manager switch --impure    
fi
