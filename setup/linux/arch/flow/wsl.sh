#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
DOTFILES_FOLDER="${DOTFILES_FOLDER:-$HOME/.dotfiles}"
readonly DOTFILES_FOLDER

source "$SCRIPT_DIR/shared.sh"

main() {
	init_logging

	if [[ "$(whoami)" == "root" ]]; then
		unlock_root
		setup_pacman_keys
		install_sudo_if_missing
		setup_sudo
		ensure_bootstrap_user
		enable_bootstrap_sudo
		trap cleanup_temp_sudoers EXIT
		run_as_bootstrap_user
		return
	fi

	remount_c
	change_wsl_distribution_conf
	install_packages
	setup_dotfiles "$DOTFILES_FOLDER"
	set_fish_default_shell
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
	main "$@"
fi
