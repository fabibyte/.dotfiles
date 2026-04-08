#!/usr/bin/env bash

set -euo pipefail

RAW_BASE_URL="https://raw.githubusercontent.com/fabibyte/.dotfiles/refs/heads/main/setup"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
MAIN_SCRIPT=""
DOTFILES_FOLDER="${DOTFILES_FOLDER:-$HOME/.dotfiles}"
BOOTSTRAP_DIR="$DOTFILES_FOLDER/.arch-wsl-bootstrap"

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
fi

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/arch-wsl-main.sh" ]]; then
    MAIN_SCRIPT="$SCRIPT_DIR/arch-wsl-main.sh"
    exec bash "$MAIN_SCRIPT" "$@"
fi

printf '\033[0;36mRunning remotely... Initializing WSL bootstrapper.\033[0m\n'

mkdir -p "$BOOTSTRAP_DIR"

curl -fsSL "$RAW_BASE_URL/arch-wsl-main.sh" -o "$BOOTSTRAP_DIR/arch-wsl-main.sh"
curl -fsSL "$RAW_BASE_URL/shared.sh" -o "$BOOTSTRAP_DIR/shared.sh"
chmod 755 -R "$BOOTSTRAP_DIR"

MAIN_SCRIPT="$BOOTSTRAP_DIR/arch-wsl-main.sh"
exec bash "$MAIN_SCRIPT" "$@"
