#!/usr/bin/env bash

set -euo pipefail

ARCHIVE_URL="https://github.com/fabibyte/.dotfiles/archive/refs/heads/main.tar.gz"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
FLOW_SCRIPT_RELATIVE_PATH="linux/arch/flow/wsl.sh"
DOTFILES_FOLDER="${DOTFILES_FOLDER:-$HOME/.dotfiles}"
SETUP_ROOT=""
FLOW_SCRIPT_PATH=""

if [[ -n "$SCRIPT_SOURCE" && -f "$SCRIPT_SOURCE" ]]; then
	SETUP_ROOT="$(cd "$(dirname "$SCRIPT_SOURCE")/../../.." && pwd)"
	FLOW_SCRIPT_PATH="$SETUP_ROOT/$FLOW_SCRIPT_RELATIVE_PATH"

	if [[ ! -f "$FLOW_SCRIPT_PATH" ]]; then
		printf "\033[0;31mCould not find %s locally.\033[0m\n" "$FLOW_SCRIPT_PATH"
		exit 1
	fi
else
	printf '\033[0;36mRunning remotely... Downloading dotfiles archive.\033[0m\n'
	TEMP_DIRECTORY="$(mktemp -d)"
	trap 'rm -rf -- "$TEMP_DIRECTORY"' EXIT

	ARCHIVE_PATH="$TEMP_DIRECTORY/dotfiles.tar.gz"
	EXTRACT_PATH="$TEMP_DIRECTORY/extract"
	mkdir -p "$EXTRACT_PATH"

	curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"
	tar -xzf "$ARCHIVE_PATH" -C "$EXTRACT_PATH"

	ARCHIVE_ROOT="$EXTRACT_PATH/.dotfiles-main"
	mkdir -p "$DOTFILES_FOLDER"
	cp -a "$ARCHIVE_ROOT"/. "$DOTFILES_FOLDER"/
	chmod 755 "$DOTFILES_FOLDER/setup/$FLOW_SCRIPT_RELATIVE_PATH"
	FLOW_SCRIPT_PATH="$DOTFILES_FOLDER/setup/$FLOW_SCRIPT_RELATIVE_PATH"
fi

exec bash "$FLOW_SCRIPT_PATH" "$@"
