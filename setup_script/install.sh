#!/bin/bash

echo "Installing packages ..."
sudo apt update -qq
sudo apt install -yqq ffmpeg 7zip jq poppler-utils fd-find ripgrep fzf imagemagick wget fish gcc unzip make wl-clipboard bat git

WINUSER=$(cmd.exe /c 'echo %USERNAME%' | tr -d '\r')
FOLDER="/mnt/c/Users/$WINUSER/.dotfiles/"

if [ ! -d "$FOLDER" ]; then
    echo "Cloning config files ..."
    mkdir -p $FOLDER
    git clone "https://github.com/fabibyte/.dotfiles.git" $FOLDER
fi

echo "Delete existing files ..."
rm -rf "$HOME/.config/"
rm -rf "$HOME/.gitconfig/"
rm -rf "$HOME/.local/state/yazi/"
rm -rf "/opt/nvim/"
find "/usr/local/bin/" -mindepth 1 -delete
sudo mkdir "/opt/nvim/"
mkdir -p "$HOME/.config/fish/themes/" "$HOME/.config/yazi/" "$HOME/.config/zellij/"

echo "Create symlinks ..."
ln -sf "$FOLDER/../.config/fish/config.fish" "$HOME/.config/fish/config.fish"
ln -sf "$FOLDER/../.config/yazi/init.lua" "$HOME/.config/yazi/init.lua"
ln -sf "$FOLDER/../.config/yazi/keymap.toml" "$HOME/.config/yazi/keymap.toml"
ln -sf "$FOLDER/../.config/zellij/config.kdl" "$HOME/.config/zellij/config.kdl"
ln -sf "$FOLDER/../.config/nvim/" "$HOME/.config/nvim"
ln -sf "$FOLDER/../.gitconfig" "$HOME"

echo -e "\nInstall additional software ..."

cd "/tmp"
curl -sLO "https://raw.githubusercontent.com/catppuccin/fish/refs/heads/main/themes/Catppuccin%20Macchiato.theme"
mv "./Catppuccin%20Macchiato.theme" "$HOME/.config/fish/themes/Catppuccin Macchiato.theme"

curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
chsh -s "/usr/bin/fish"

echo -e "\n---- YAZI ----"
echo "Downloading ..."
curl -sLO "https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip"
echo "Extracting ..."
unzip -q "./yazi-x86_64-unknown-linux-musl.zip"
echo "Copying to path ..."
sudo mv "./yazi-x86_64-unknown-linux-musl/ya" "/usr/local/bin/ya"
sudo mv "./yazi-x86_64-unknown-linux-musl/yazi" "/usr/local/bin/yazi"
echo "Install plugins ..."
curl -sLO "https://raw.githubusercontent.com/catppuccin/yazi/refs/heads/main/themes/macchiato/catppuccin-macchiato-blue.toml"
mv "./catppuccin-macchiato-blue.toml" "$HOME/.config/yazi/theme.toml"
git clone "https://github.com/imsi32/yatline-catppuccin.yazi.git" ~"/.config/yazi/plugins/yatline-catppuccin.yazi"
ya pkg add yazi-rs/plugins:full-border
ya pkg add imsi32/yatline
ya pkg add WhoSowSee/whoosh

echo -e "\n---- NEOVIM ----"
echo "Downloading ..."
curl -sLO "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
echo "Extracting ..."
tar -xf "./nvim-linux-x86_64.tar.gz"
echo "Copying to path ..."
sudo mv "./nvim-linux-x86_64/"* "/opt/nvim/"

echo -e "\n---- TREESITTER-CLI ----"
echo "Downloading ..."
curl -sLO "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-x64.gz"
echo "Extracting ..."
gunzip "./tree-sitter-linux-x64.gz"
echo "Copying to path ..."
sudo mv "./tree-sitter-linux-x64" "/usr/local/bin/tree-sitter"
chmod 755 "/usr/local/bin/tree-sitter"

echo -e "\n---- ZELLIJ ----"
echo "Downloading ..."
curl -sLO "https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz"
echo "Extracting ..."
tar -xf "./"zellij*.tar.gz
echo "Copying to path ..."
sudo mv "./zellij" "/usr/local/bin/zellij"

echo -e "\n---- DELTA ----"
echo "Downloading ..."
curl -sLO $(curl -s https://api.github.com/repos/dandavison/delta/releases/latest | grep -o 'https://github.com/dandavison/delta/releases/download/.*/delta-.*-x86_64-unknown-linux-musl.tar.gz')
echo "Extracting ..."
tar -xf "./"delta*.tar.gz
echo "Copying to path ..."
sudo mv "./"delta*"/delta" "/usr/local/bin/delta"

sudo rm -rf "/tmp/"*
exec fish
