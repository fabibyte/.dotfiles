#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
readonly DOTFILES_FOLDER="${DOTFILES_FOLDER:-$HOME/.dotfiles}"
readonly DEFAULT_SHELL="fish"

source "$SCRIPT_DIR/shared.sh"

main() {
	init_logging

	if [[ "$(whoami)" == "root" ]]; then
		unlock_root
		setup_pacman_keys
		install_sudo_if_missing
		configure_sudo "$DOTFILES_FOLDER"
		ensure_bootstrap_user
		enable_bootstrap_sudo
		trap disable_bootstrap_sudo EXIT
		rerun_as_bootstrap_user "$SCRIPT_PATH" "$DOTFILES_FOLDER"
		return
	fi

	remount_c_with_permissions "$BOOTSTRAP_UID" "$BOOTSTRAP_GID"
	change_wsl_distribution_conf
	install_packages
	install_mise
	ensure_dotfiles_git_repo "$DOTFILES_FOLDER"

	configure_docker
	configure_mise "$DOTFILES_FOLDER"
	configure_yazi "$DOTFILES_FOLDER"
	configure_nvim "$DOTFILES_FOLDER"
	configure_ssh_keys "$DOTFILES_FOLDER"

	info "Copying other config files..."
	copy_path "$DOTFILES_FOLDER/zellij" "$HOME/.config/zellij"
	copy_path "$DOTFILES_FOLDER/fish" "$HOME/.config/fish"
	copy_path "$DOTFILES_FOLDER/.gitconfig" "$HOME/.gitconfig"

	set_default_shell "$DEFAULT_SHELL"
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
	main "$@"
fi
