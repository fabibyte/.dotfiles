#!/usr/bin/env bash

set -euo pipefail

RAW_BASE_URL="https://raw.githubusercontent.com/fabibyte/.dotfiles/refs/heads/main/setup"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
MAIN_SCRIPT=""
TMP_DIR=""

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf -- "$TMP_DIR"
    fi
}

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
fi

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/arch-wsl-main.sh" ]]; then
    MAIN_SCRIPT="$SCRIPT_DIR/arch-wsl-main.sh"
    exec bash "$MAIN_SCRIPT" "$@"
fi

printf '\033[0;36mRunning remotely... Initializing WSL bootstrapper.\033[0m\n'

TMP_DIR="$(mktemp -d)"
trap cleanup EXIT

curl -fsSL "$RAW_BASE_URL/arch-wsl-main.sh" -o "$TMP_DIR/arch-wsl-main.sh"
curl -fsSL "$RAW_BASE_URL/shared.sh" -o "$TMP_DIR/shared.sh"
chmod 755 -R "$TMP_DIR"

MAIN_SCRIPT="$TMP_DIR/arch-wsl-main.sh"
bash "$MAIN_SCRIPT" "$@"
