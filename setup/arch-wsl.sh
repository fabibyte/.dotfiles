#!/usr/bin/env bash

set -euo pipefail

RAW_BASE_URL="https://raw.githubusercontent.com/fabibyte/.dotfiles/refs/heads/main/setup"

# Check if we are running via a pipe or if the main script is not adjacent
if [[ ! -f "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == *"bash"* || ! -f "$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" && pwd)/arch-wsl-main.sh" ]]; then
    echo -e "\033[0;36mRunning remotely... Initializing WSL bootstrapper.\033[0m"
    
    TMP_DIR=$(mktemp -d)
    
    curl -fsSL "$RAW_BASE_URL/arch-wsl-main.sh" -o "$TMP_DIR/arch-wsl-main.sh"
    curl -fsSL "$RAW_BASE_URL/shared.sh" -o "$TMP_DIR/shared.sh"
    chmod 755 -R "$TMP_DIR"
    
    MAIN_SCRIPT="$TMP_DIR/arch-wsl-main.sh"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    MAIN_SCRIPT="$SCRIPT_DIR/arch-wsl-main.sh"
fi

exec bash "$MAIN_SCRIPT" "$@"
