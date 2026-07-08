ARCH_FLOW_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH_DOTFILES_ROOT="$(cd "$ARCH_FLOW_DIRECTORY/../../../.." && pwd)"
source "$ARCH_FLOW_DIRECTORY/../../shared.sh"

setup_pacman_keys() {
	[[ "$(whoami)" != "root" ]] && return 0

	if pacman-key --list-keys &>/dev/null && pacman-key --list-keys archlinux &>/dev/null; then
		success "Pacman keyring is already initialised and populated."
		return 0
	fi

	info "Initialising pacman keyring..."
	pacman-key --init &>/dev/null || abort "Could not initialize pacman keyring."

	info "Populating archlinux keys..."
	pacman-key --populate archlinux &>/dev/null || abort "Could not populate pacman keyring."

	success "Pacman keyring setup complete."
}

install_sudo_if_missing() {
	[[ "$(whoami)" != "root" ]] && return 0

	if command -v sudo >/dev/null 2>&1; then
		return 0
	fi

	info "Installing sudo..."
	pacman -Syu --noconfirm --needed sudo >/dev/null || abort "Could not install sudo."
}

change_wsl_distribution_conf() {
	local config_file="/etc/wsl-distribution.conf"
	local template_file="$ARCH_DOTFILES_ROOT/wsl-distribution/arch/wsl-distribution.conf"
	local temp_directory
	local staged_config_file

	if [[ ! -f "$template_file" ]]; then
		abort "Could not find WSL distribution config template at $template_file."
	fi

	temp_directory="$(mktemp -d)"
	staged_config_file="$temp_directory/wsl-distribution.conf"

	copy_path "$template_file" "$staged_config_file"
	sed -i "s|\${UID}|$BOOTSTRAP_UID|g" "$staged_config_file"

	if [[ -f "$config_file" ]] && sudo cmp -s "$staged_config_file" "$config_file"; then
		success "$config_file already has the desired content."
		rm -rf -- "$temp_directory"
		return 0
	fi

	info "Copying $config_file..."
	copy_path "$staged_config_file" "$config_file"
	rm -rf -- "$temp_directory"
	success "$config_file has been updated."
}

install_packages() {
	if ! command -v sudo >/dev/null 2>&1; then
		abort "sudo is not available; cannot install packages."
	fi

	info "Updating package cache..."
	sudo pacman -Syu --noconfirm >/dev/null

	info "Installing packages..."
	sudo pacman -S --noconfirm --needed \
		mise git base-devel re2c plocate gd postgresql-libs libzip curl docker neovim chafa ueberzugpp viu unzip wget gzip tar rsync fish ripgrep fd bat zoxide git-delta zellij wl-clipboard yazi ffmpeg p7zip jq poppler fzf resvg imagemagick

	success "Package installation complete."
}
