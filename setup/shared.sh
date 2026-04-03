#!/usr/bin/env bash

set -euo pipefail

DOTFILES_FOLDER="${DOTFILES_FOLDER:-$HOME/.dotfiles}"
DOTFILES_LOG_FILE="${DOTFILES_LOG_FILE:-$DOTFILES_FOLDER/setup_$(date +%Y%m%d_%H%M%S).log}"

init_logging() {
	local log_dir
	log_dir="$(dirname "$DOTFILES_LOG_FILE")"
	if [ ! -d "$log_dir" ]; then
		mkdir -p "$log_dir" 2>/dev/null
	fi

	if [ ! -e "$DOTFILES_LOG_FILE" ]; then
		touch "$DOTFILES_LOG_FILE" 2>/dev/null || true
	fi

	if [ "${DOTFILES_USE_TEE:-1}" -eq 1 ]; then
		export DOTFILES_USE_TEE=0
		exec > >(tee -a "$DOTFILES_LOG_FILE") 2>&1
	fi
}

write_log() {
	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	local formatted="[$level] $message"

	case "$level" in
	INFO) printf "\033[0;36m[%s] %s\033[0m\n" "$timestamp" "$formatted" ;;
	SUCCESS) printf "\033[0;32m[%s] %s\033[0m\n" "$timestamp" "$formatted" ;;
	WARNING) printf "\033[0;33m[%s] %s\033[0m\n" "$timestamp" "$formatted" ;;
	ERROR) printf "\033[0;31m[%s] %s\033[0m\n" "$timestamp" "$formatted" ;;
	*) printf "[%s] %s\n" "$timestamp" "$formatted" ;;
	esac
}

info() {
	write_log "INFO" "$*"
}

success() {
	write_log "SUCCESS" "$*"
}

warning() {
	write_log "WARNING" "$*"
}

error() {
	write_log "ERROR" "$*" >&2
}

assert_running_in_wsl() {
	if ! grep -qi "microsoft" /proc/version 2>/dev/null && [ -z "${WSL_DISTRO_NAME-}" ]; then
		error "This script is intended to run inside WSL."
		exit 1
	fi
}

ensure_dotfiles_cloned() {
	if [ -d "$DOTFILES_FOLDER/.git" ]; then
		info "Dotfiles already cloned at $DOTFILES_FOLDER."
		return
	fi

	info "Cloning dotfiles into $DOTFILES_FOLDER..."
	mkdir -p "$DOTFILES_FOLDER"
	cd "$DOTFILES_FOLDER" || return 1

	git init
	git remote add origin "https://github.com/fabibyte/.dotfiles.git" || true
	git fetch origin
	git reset --hard origin/main
	git branch -M main || true
	git branch --set-upstream-to=origin/main main || true

	success "Dotfiles cloned."
}

create_symlink() {
	local src="$1"
	local tgt="$2"

	if [ -z "$src" ] || [ -z "$tgt" ]; then
		error "create_symlink requires <src> and <target> arguments"
		return 1
	fi

	if [ ! -e "$src" ]; then
		warning "Source does not exist: $src"
		return
	fi

	if [ -L "$tgt" ]; then
		local current
		current=$(readlink -f "$tgt" || true)
		if [ "$current" = "$src" ]; then
			info "Symlink already correct: $tgt -> $src"
			return
		fi

		rm -f "$tgt"
	fi

	if [ -e "$tgt" ]; then
		warning "Target exists and is not a symlink; skipping: $tgt"
		return
	fi

	mkdir -p "$(dirname "$tgt")"
	ln -s "$src" "$tgt"
	success "Linked $tgt -> $src"
}

link_tree() {
	local src_dir="$1"
	local tgt_dir="$2"

	if [ ! -d "$src_dir" ]; then
		warning "Source directory does not exist: $src_dir"
		return
	fi

	find "$src_dir" -type f -print0 | while IFS= read -r -d '' file; do
		local rel_path
		rel_path="${file#"$src_dir"/}"
		local tgt_file="$tgt_dir/$rel_path"
		create_symlink "$file" "$tgt_file"
	done
}

fetch_file() {
	local url="$1"
	local target="$2"

	mkdir -p "$(dirname "$target")"
	if curl -fsSL "$url" -o "$target"; then
		success "Fetched $url -> $target"
	else
		error "Failed to fetch $url"
		return 1
	fi
}

decrypt_ssh_keys() {
	local encrypted="$DOTFILES_FOLDER/.ssh/id_ed25519.enc"
	local decrypted="$DOTFILES_FOLDER/.ssh/id_ed25519"

	if [ -f "$decrypted" ]; then
		info "SSH key already decrypted."
		return
	fi

	if [ ! -f "$encrypted" ]; then
		warning "Encrypted SSH key not found: $encrypted"
		return
	fi

	info "Decrypting SSH keys..."
	openssl aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "$encrypted" -out "$decrypted"
	chmod 600 "$decrypted"
	success "SSH key decrypted."

	link_tree "$DOTFILES_FOLDER/.ssh" "$HOME/.ssh"
}

set_fish_default_shell() {
	if ! command -v sudo >/dev/null 2>&1; then
		warning "sudo is not available; cannot set fish as default shell."
		return
	fi

	if ! command -v fish >/dev/null 2>&1; then
		warning "fish not installed; skipping shell change."
		return
	fi

	local fish_shell
	fish_shell=$(command -v fish)

	if ! grep -qx "$fish_shell" /etc/shells; then
		info "Registering fish shell in /etc/shells..."
		echo "$fish_shell" | sudo tee -a /etc/shells >/dev/null
	fi

	if [ "$(basename "$SHELL")" = "fish" ]; then
		info "fish is already the default shell."
		return
	fi

	info "Setting fish as default shell..."
	sudo chsh -s "$fish_shell" "$(whoami)" || warning "Failed to change shell. You may need to run this manually."
	success "Default shell set to fish."
}

install_shared_tooling() {
	info "Installing additional tooling (Yazi plugins, runtimes, etc.)..."

	if command -v ya >/dev/null 2>&1; then
		info "Installing Yazi plugins..."
		ya pkg add imsi32/yatline || warning "Failed to install Yazi plugin: imsi32/yatline"
		ya pkg add imsi32/yatline-catppuccin || warning "Failed to install Yazi plugin: imsi32/yatline-catppuccin"
		ya pkg add yazi-rs/plugins:full-border || warning "Failed to install Yazi plugin: yazi-rs/plugins:full-border"
	else
		warning "ya (Yazi plugin installer) not found; skipping plugin installs."
	fi

	if [ ! -d "$HOME/.config/yazi/plugins/whoosh.yazi" ]; then
		git clone https://gitlab.com/WhoSowSee/whoosh.yazi.git "$HOME/.config/yazi/plugins/whoosh.yazi"
		success "Installed whoosh.yazi plugin."
	else
		info "whoosh.yazi plugin already cloned."
	fi

	info "Selecting global language runtimes via mise..."
	if command -v mise >/dev/null 2>&1; then
		eval "$(mise activate bash)"

		for runtime in rust python ruby php go julia node java tree-sitter; do
			if mise use -g "$runtime"; then
				success "Global runtime set: $runtime"
			else
				warning "Failed to set global runtime for $runtime"
			fi
		done
	else
		warning "mise not found; skipping language runtime selection."
	fi

	if command -v pip >/dev/null 2>&1; then
		info "Installing hererocks..."
		pip install --user hererocks || warning "Failed to install hererocks."
		if command -v hererocks >/dev/null 2>&1; then
			hererocks "$HOME/.local/share/nvim/lazy-rocks/hererocks" -l5.1 -rlatest || warning "Failed to initialize hererocks."
		else
			warning "hererocks not available after installation."
		fi
	else
		warning "pip not found; skipping hererocks installation."
	fi

	success "Shared tooling installation complete."
}

setup_dotfiles() {
	ensure_dotfiles_cloned
	decrypt_ssh_keys

	info "Linking config files..."
	link_tree "$DOTFILES_FOLDER/fish" "$HOME/.config/fish"
	link_tree "$DOTFILES_FOLDER/yazi" "$HOME/.config/yazi"
	link_tree "$DOTFILES_FOLDER/zellij" "$HOME/.config/zellij"
	link_tree "$DOTFILES_FOLDER/nvim" "$HOME/.config/nvim"
	create_symlink "$DOTFILES_FOLDER/.gitconfig" "$HOME/.gitconfig"

	info "Fetching themes..."
	fetch_file "https://raw.githubusercontent.com/catppuccin/yazi/refs/heads/main/themes/macchiato/catppuccin-macchiato-blue.toml" "$HOME/.config/yazi/theme.toml"

	success "Shared dotfiles setup completed."
}

main() {
	init_logging
	install_shared_tooling
	setup_dotfiles
	set_fish_default_shell
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
fi
