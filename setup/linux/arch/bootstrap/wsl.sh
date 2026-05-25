#!/usr/bin/env bash

set -euo pipefail

ARCHIVE_URL="https://github.com/fabibyte/.dotfiles/archive/refs/heads/main.tar.gz"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
MAIN_FILEPATH="linux/arch/flow/wsl.sh"
DOTFILES_FOLDER="${DOTFILES_FOLDER:-$HOME/.dotfiles}"
MAIN_SCRIPT_ROOT=""
MAIN_SCRIPT=""

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
	MAIN_SCRIPT_ROOT="$(cd "$(dirname "$SCRIPT_SOURCE")/../../.." && pwd)"
	MAIN_SCRIPT="$MAIN_SCRIPT_ROOT/$MAIN_FILEPATH"

	if [[ ! -f "$MAIN_SCRIPT" ]]; then
		printf "\033[0;31mCould not find $MAIN_SCRIPT locally.\033[0m\n"
		exit 1
	fi
else
	printf '\033[0;36mRunning remotely... Downloading dotfiles archive.\033[0m\n'
	TEMP_ROOT="$(mktemp -d)"
	trap 'rm -rf -- "$TEMP_ROOT"' EXIT

	ARCHIVE_PATH="$TEMP_ROOT/dotfiles.tar.gz"
	EXTRACT_PATH="$TEMP_ROOT/extract"
	mkdir -p "$EXTRACT_PATH"

	curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"
	tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_PATH"

	ARCHIVE_ROOT="$EXTRACT_PATH/.dotfiles-main"
	mkdir -p "$DOTFILES_FOLDER"
	cp -a "$ARCHIVE_ROOT"/. "$DOTFILES_FOLDER"/
	chmod 755 "$DOTFILES_FOLDER/setup/$MAIN_FILEPATH"
	MAIN_SCRIPT="$DOTFILES_FOLDER/setup/$MAIN_FILEPATH"
fi

exec bash "$MAIN_SCRIPT" "$@"
