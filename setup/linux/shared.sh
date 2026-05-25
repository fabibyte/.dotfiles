#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
	set -euo pipefail
fi

DOTFILES_LOG_FILE="${DOTFILES_LOG_FILE:-}"

init_logging() {
	local new_log_file_base_path="${1:-${DOTFILES_FOLDER:-$HOME/.dotfiles}}"
	local resume_log_file_path="${2:-$DOTFILES_LOG_FILE}"
	local resolved_log_path
	local log_dir

	if [[ -n "$resume_log_file_path" ]]; then
		resolved_log_path="$resume_log_file_path"
	else
		resolved_log_path="$new_log_file_base_path/setup_$(date +%Y%m%d_%H%M%S).log"
	fi

	DOTFILES_LOG_FILE="$resolved_log_path"
	export DOTFILES_LOG_FILE

	log_dir="$(dirname "$DOTFILES_LOG_FILE")"
	if [[ ! -d "$log_dir" ]]; then
		mkdir -p "$log_dir" 2>/dev/null
	fi

	if [[ ! -e "$DOTFILES_LOG_FILE" ]]; then
		touch "$DOTFILES_LOG_FILE" 2>/dev/null
	fi

	exec > >(tee >(sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g' >>"$DOTFILES_LOG_FILE")) 2>&1
}

write_log() {
	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	local formatted="[$level] $message"
	local color=""
	local reset="\033[0m"

	case "$level" in
	INFO) color="\033[0;36m" ;;
	SUCCESS) color="\033[0;32m" ;;
	WARNING) color="\033[1;33m" ;;
	ERROR) color="\033[0;31m" ;;
	*) reset="" ;;
	esac

	printf "%b[%s] %s%b\n" "$color" "$timestamp" "$formatted" "$reset"
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

abort() {
	local exit_code=1
	if [[ "$1" =~ ^[0-9]+$ ]]; then
		exit_code="$1"
		shift
	fi
	error "$*"
	exit "$exit_code"
}

ensure_dotfiles_git_repo() {
	local dotfiles_folder="$1"

	if [ -d "$dotfiles_folder/.git" ]; then
		info "Dotfiles Git repository already initialized at $dotfiles_folder."
		return
	fi

	if [ ! -f "$dotfiles_folder/setup/linux/shared.sh" ]; then
		abort "Dotfiles are not present at $dotfiles_folder."
	fi

	info "Initializing dotfiles Git repository at $dotfiles_folder..."

	{
		git -C "$dotfiles_folder" init &&
			git -C "$dotfiles_folder" remote add origin "https://github.com/fabibyte/.dotfiles.git" &&
			git -C "$dotfiles_folder" fetch origin main &&
			git -C "$dotfiles_folder" symbolic-ref HEAD refs/heads/main &&
			git -C "$dotfiles_folder" reset --mixed origin/main &&
			git -C "$dotfiles_folder" branch --set-upstream-to=origin/main main
	} &>/dev/null || abort "Failed to initialize dotfiles Git repository."

	success "Dotfiles Git repository initialized."
}

create_symlink() {
	local source_path="$1"
	local target_path="$2"

	if [[ -z "$source_path" || -z "$target_path" ]]; then
		error "create_symlink requires <source-path> and <target-path> arguments"
		return 1
	fi

	if [[ ! -e "$source_path" ]]; then
		warning "Source does not exist: $source_path"
		return
	fi

	if [[ -L "$target_path" ]]; then
		local current_target_path
		current_target_path=$(readlink -f "$target_path")
		if [[ "$current_target_path" = "$source_path" ]]; then
			info "Symlink already correct: $target_path -> $source_path"
			return
		fi

		rm -f "$target_path"
	fi

	if [[ -e "$target_path" ]]; then
		warning "Target exists and is not a symlink; skipping: $target_path"
		return
	fi

	mkdir -p "$(dirname "$target_path")"
	ln -s "$source_path" "$target_path"
	success "Linked $target_path -> $source_path"
}

link_tree() {
	local source_directory="$1"
	local target_directory="$2"

	if [[ ! -d "$source_directory" ]]; then
		warning "Source directory does not exist: $source_directory"
		return
	fi

	find "$source_directory" -type f -print0 | while IFS= read -r -d '' source_file_path; do
		local relative_path
		relative_path="${source_file_path#"$source_directory"/}"
		local target_file_path="$target_directory/$relative_path"
		create_symlink "$source_file_path" "$target_file_path"
	done
}

fetch_file() {
	local url="$1"
	local target_path="$2"

	if [[ -f "$target_path" ]]; then
		info "File already present, skipping fetch: $target_path"
		return
	fi

	mkdir -p "$(dirname "$target_path")"
	if curl -fsSL "$url" -o "$target_path"; then
		success "Fetched $url -> $target_path"
	else
		error "Failed to fetch $url"
		return 1
	fi
}

invoke_with_retries() {
	if [[ "$#" -lt 3 ]]; then
		error "invoke_with_retries requires <description>, <max-attempts>, and a command to execute."
		return 1
	fi

	local description="$1"
	local max_attempts="${2:-3}"
	shift 2

	if [[ ! "$max_attempts" =~ ^[0-9]+$ || "$max_attempts" -lt 1 ]]; then
		error "invoke_with_retries requires max-attempts to be a positive integer."
		return 1
	fi

	local attempt
	local last_error=""

	for ((attempt = 1; attempt <= max_attempts; attempt++)); do
		if "$@"; then
			return 0
		fi

		last_error="$description failed."

		if [[ "$attempt" -lt "$max_attempts" ]]; then
			warning "$description failed. $((max_attempts - attempt)) attempt(s) remaining."
		fi
	done

	error "$description failed after $max_attempts attempts. Last error: $last_error"
	return 1
}

decrypt() {
	if [[ "$#" -lt 3 ]]; then
		error "decrypt requires <description>, <input-path>, and <output-path> arguments."
		return 1
	fi

	local description="$1"
	local input_path="$2"
	local output_path="$3"
	local max_attempts="${4:-3}"

	if [[ -f "$output_path" ]]; then
		info "$description output already exists: $output_path"
		return 0
	fi

	if [[ ! -f "$input_path" ]]; then
		error "Encrypted input not found: $input_path"
		return 1
	fi

	mkdir -p "$(dirname "$output_path")"

	decrypt_action() {
		if openssl aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "$input_path" -out "$output_path"; then
			return 0
		fi

		rm -f -- "$output_path"
		return 1
	}

	local retry_result=0
	invoke_with_retries "$description" "$max_attempts" decrypt_action || retry_result="$?"
	unset -f decrypt_action

	if [[ "$retry_result" -ne 0 ]]; then
		return "$retry_result"
	fi

	success "Decryption successful."
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
	local current_shell
	fish_shell=$(command -v fish)
	current_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"

	if ! grep -qx "$fish_shell" /etc/shells; then
		info "Registering fish shell in /etc/shells..."
		echo "$fish_shell" | sudo tee -a /etc/shells >/dev/null
	fi

	if [ "$current_shell" = "$fish_shell" ]; then
		info "fish is already the default shell."
		return
	fi

	info "Setting fish as default shell..."
	sudo chsh -s "$fish_shell" "$(whoami)"
	success "Default shell set to fish."
}

install_shared_tooling() {
	info "Installing additional tooling (Yazi plugins, runtimes, etc.)..."

	if command -v ya >/dev/null 2>&1; then
		info "Installing Yazi plugins..."

		ya pkg add imsi32/yatline &>/dev/null || abort "Failed to install yatline plugin."
		success "Installed yatline plugin."

		ya pkg add imsi32/yatline-catppuccin &>/dev/null || abort "Failed to install yatline-catppuccin plugin."
		success "Installed yatline-catppuccin plugin."

		ya pkg add yazi-rs/plugins:full-border &>/dev/null || abort "Failed to install full-border plugin."
		success "Installed full-border plugin."

		if [ ! -d "$HOME/.config/yazi/plugins/whoosh.yazi" ]; then
			git clone https://gitlab.com/WhoSowSee/whoosh.yazi.git "$HOME/.config/yazi/plugins/whoosh.yazi" &>/dev/null || abort "Failed to install whoosh plugin."
			success "Installed whoosh plugin."
		fi
	else
		warning "ya (Yazi plugin installer) not found; skipping plugin installs."
	fi

	info "Selecting global language runtimes via mise..."
	if command -v mise >/dev/null 2>&1; then
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
		pip install --user hererocks
		if command -v hererocks >/dev/null 2>&1; then
			hererocks "$HOME/.local/share/nvim/lazy-rocks/hererocks" -l5.1 -rlatest
		else
			warning "hererocks not available after installation."
		fi
	else
		warning "pip not found; skipping hererocks installation."
	fi

	success "Shared tooling installation complete."
}

setup_dotfiles() {
	local dotfiles_folder="$1"
	local encrypted_ssh_key="$dotfiles_folder/.ssh/id_ed25519.enc"
	local ssh_key="$dotfiles_folder/.ssh/id_ed25519"

	ensure_dotfiles_git_repo "$dotfiles_folder"

	decrypt "SSH key decryption" "$encrypted_ssh_key" "$ssh_key"
	chmod 600 "$ssh_key"
	link_tree "$dotfiles_folder/.ssh" "$HOME/.ssh"

	info "Linking config files..."
	link_tree "$dotfiles_folder/fish" "$HOME/.config/fish"
	link_tree "$dotfiles_folder/yazi" "$HOME/.config/yazi"
	link_tree "$dotfiles_folder/zellij" "$HOME/.config/zellij"
	link_tree "$dotfiles_folder/nvim" "$HOME/.config/nvim"
	create_symlink "$dotfiles_folder/.gitconfig" "$HOME/.gitconfig"

	info "Fetching themes..."
	fetch_file "https://raw.githubusercontent.com/catppuccin/yazi/refs/heads/main/themes/macchiato/catppuccin-macchiato-blue.toml" "$HOME/.config/yazi/theme.toml"

	success "Shared dotfiles setup completed."
}
