#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
	set -euo pipefail
fi

readonly TEMP_SUDOERS_FILE="/etc/sudoers.d/zzz-passwordless-bootstrap"
readonly BOOTSTRAP_UID="1000"
readonly BOOTSTRAP_GID="1000"
readonly SUDO_GROUP_GID="27"
readonly BOOTSTRAP_USER="fabi"

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

	if ! command -v git >/dev/null 2>&1; then
		abort "git is not available; cannot initialize dotfiles repository."
	fi

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

copy_path() {
	local source_path="$1"
	local target_path="$2"
	local target_parent
	local writable_parent
	local copy_source
	local copy_target
	local command_prefix=()

	if [[ -z "$source_path" || -z "$target_path" ]]; then
		error "copy_path requires <source-path> and <target-path> arguments"
		return 1
	fi

	if [[ ! -e "$source_path" ]]; then
		warning "Source does not exist: $source_path"
		return 0
	fi

	if [[ -d "$source_path" ]]; then
		target_parent="$target_path"
		copy_source="${source_path}/."
		copy_target="${target_path}/"
	else
		target_parent="$(dirname -- "$target_path")"
		copy_source="$source_path"
		copy_target="$target_path"
	fi

	writable_parent="$target_parent"
	while [[ ! -e "$writable_parent" && "$writable_parent" != "/" ]]; do
		writable_parent="$(dirname -- "$writable_parent")"
	done

	if [[ "$EUID" -ne 0 && ! -w "$writable_parent" ]]; then
		if ! command -v sudo >/dev/null 2>&1; then
			error "sudo is required to copy to $target_path"
			return 1
		fi

		command_prefix=(sudo)
	fi

	"${command_prefix[@]}" mkdir -p -- "$target_parent"
	"${command_prefix[@]}" cp -a --remove-destination -- "$copy_source" "$copy_target"

	success "Copied $source_path -> $target_path"
}

fetch_file() {
	local url="$1"
	local target_path="$2"

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
		local password=""

		printf 'enter AES-256-CBC decryption password: ' >/dev/tty
		if ! IFS= read -r -s password </dev/tty; then
			printf '\n' >/dev/tty
			return 1
		fi
		printf '\n' >/dev/tty

		if openssl aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "$input_path" -out "$output_path" -pass fd:3 3<<<"$password"; then
			unset password
			return 0
		fi

		unset password
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

set_default_shell() {
	local shell="$1"

	if ! command -v sudo >/dev/null 2>&1; then
		warning "sudo is not available; cannot set default shell to $shell."
		return 0
	fi

	if ! command -v $shell >/dev/null 2>&1; then
		warning "$shell not installed; skip skip setting default shell to $shell."
		return 0
	fi

	local shell_path
	local current_shell
	shell_path=$(command -v $shell)
	current_shell="$(getent passwd "$(id -un)" | cut -d: -f7)"

	if [ "$current_shell" = "$shell_path" ]; then
		info "$shell is already the default shell."
		return 0
	fi

	if ! grep -qx "$shell_path" /etc/shells; then
		info "Registering $shell in /etc/shells..."
		echo "$shell_path" | sudo tee -a /etc/shells >/dev/null
	fi

	info "Setting $shell as default shell..."
	sudo chsh -s "$shell_path" "$(whoami)"
	success "Default shell set to $shell."
}

unlock_root() {
	[[ "$(whoami)" != "root" ]] && return 0

	local root_hash
	root_hash=$(awk -F: '$1 == "root" {print $2}' /etc/shadow)
	if [[ "$root_hash" =~ ^[\*!]*$ ]]; then
		info "Root password is not set. Please set it now."
		passwd root
	else
		success "Root password is already set."
	fi
}

ensure_bootstrap_user() {
	[[ "$(whoami)" != "root" ]] && return 0

	if ! getent group "$BOOTSTRAP_USER" >/dev/null 2>&1; then
		groupadd --gid "$BOOTSTRAP_GID" "$BOOTSTRAP_USER"
	fi

	if ! id -u "$BOOTSTRAP_USER" >/dev/null 2>&1; then
		info "Creating user $BOOTSTRAP_USER..."
		useradd --create-home --groups sudo --uid "$BOOTSTRAP_UID" --gid "$BOOTSTRAP_GID" "$BOOTSTRAP_USER"

		info "Please set a password for the new user '$BOOTSTRAP_USER'."
		passwd "$BOOTSTRAP_USER"
	fi
}

enable_bootstrap_sudo() {
	[[ "$(whoami)" != "root" ]] && return 0

	printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$BOOTSTRAP_USER" >"$TEMP_SUDOERS_FILE"
	chmod 0440 "$TEMP_SUDOERS_FILE"
	visudo -cf "$TEMP_SUDOERS_FILE" >/dev/null || abort "Could not validate $TEMP_SUDOERS_FILE."
}

disable_bootstrap_sudo() {
	if [[ -f "$TEMP_SUDOERS_FILE" ]]; then
		rm -f -- "$TEMP_SUDOERS_FILE"
	fi
}

rerun_as_bootstrap_user() {
	[[ "$(whoami)" != "root" ]] && return 0

	local script="$1"
	local dotfiles_folder="$2"

	info "Switching to user $BOOTSTRAP_USER for the rest of the script..."
	sudo -u "$BOOTSTRAP_USER" env \
		DOTFILES_FOLDER="$dotfiles_folder" \
		DOTFILES_LOG_FILE="$DOTFILES_LOG_FILE" \
		bash "$script"
}

remount_c_with_permissions() {
	if ! command -v sudo >/dev/null 2>&1; then
		warning "sudo is not available; cannot remount"
		return
	fi

	local target_uid="$BOOTSTRAP_UID"
	local target_gid="$BOOTSTRAP_GID"
	local current_mount_uid
	local current_mount_gid
	current_mount_uid=$(stat -c '%u' /mnt/c)
	current_mount_gid=$(stat -c '%g' /mnt/c)

	if [[ "$current_mount_uid" -ne "$target_uid" || "$current_mount_gid" -ne "$target_gid" ]]; then
		sudo mount -t "drvfs" "C:\\" "/mnt/c" -o "rw,noatime,uid=$target_uid,gid=$target_gid,cache=5,access=client,msize=65536"
	else
		info "Already mounted with correct UID/GID."
	fi
}

configure_sudo() {
	[[ "$(whoami)" != "root" ]] && return 0

	local dotfiles_folder="$1"

	if ! getent group sudo >/dev/null 2>&1; then
		info "Adding sudo group..."
		groupadd --gid "$SUDO_GROUP_GID" sudo
	fi

	info "Configuring sudoers..."
	local base_target_path="/etc/sudoers.d"

	for file in "$dotfiles_folder"/sudo/*; do
		[ -f "$file" ] || continue

		local filename=$(basename "$file")
		local target_path="$base_target_path/$filename"

		copy_path "$file" "$target_path"
		chmod 0440 "$target_path"

		if ! visudo -cf "$target_path" >/dev/null; then
			warning "Could not validate $file. Removing it again."
			rm "$target_path"
			continue
		fi
	done

	success "sudo is configured."
}

configure_yazi() {
	local dotfiles_folder="$1"

	info "Copying yazi config ..."
	copy_path "$dotfiles_folder/yazi" "$HOME/.config/yazi"

	if ! command -v ya >/dev/null 2>&1; then
		warning "ya (Yazi plugin installer) not found; skipping further yazi configuration."
		return 0
	fi

	if ! command -v git >/dev/null 2>&1; then
		warning "git not found; skipping further yazi configuration."
		return 0
	fi

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

	info "Fetching theme..."
	fetch_file "https://raw.githubusercontent.com/catppuccin/yazi/refs/heads/main/themes/macchiato/catppuccin-macchiato-blue.toml" "$HOME/.config/yazi/theme.toml"

	success "yazi configuration complete!"
}

configure_mise() {
	local dotfiles_folder="$1"
	local mise_path="$HOME/.local/bin/mise"

	if ! command -v "$mise_path" >/dev/null 2>&1; then
		warning "mise not found; skipping mise configuration."
		return 0
	fi

	info "Activating mise..."
	eval "$("$mise_path" activate bash --shims)"

	info "Copying mise config file..."
	copy_path "$dotfiles_folder/mise/config.toml" "$HOME/.config/mise/config.toml"

	info "Installing global language runtimes via mise..."

	if mise install; then
		success "Global runtimes installed."
	else
		warning "Failed to install global runtimes."
	fi

	success "mise configuration complete!"
}

configure_nvim() {
	local dotfiles_folder="$1"

	info "Copying nvim config files..."
	copy_path "$dotfiles_folder/nvim" "$HOME/.config/nvim"

	if ! command -v pip >/dev/null 2>&1; then
		warning "pip not found; skipping hererocks installation."
		return 0
	fi

	info "Installing hererocks..."
	pip install --user hererocks

	if ! command -v hererocks >/dev/null 2>&1; then
		warning "hererocks not available after installation; skipping hererocks installation."
		return 0
	fi

	hererocks "$HOME/.local/share/nvim/lazy-rocks/hererocks" -l5.1 -rlatest

	success "nvim configuration complete!"
}

configure_sshd() {
	if ! command -v sudo >/dev/null 2>&1; then
		warning "sudo is not available; cannot setup ssh."
		return 0
	fi

	info "Enabling sshd service..."
	sudo systemctl enable --now sshd &>/dev/null || abort "Failed enable sshd."

	success "sshd configuration complete!"
}

configure_docker() {
	if ! command -v sudo >/dev/null 2>&1; then
		warning "sudo is not available; cannot configure docker."
		return 0
	fi

	if ! command -v docker >/dev/null 2>&1; then
		warning "docker is not available; cannot configure docker."
		return 0
	fi

	info "Configuring Docker..."

	if ! getent group docker >/dev/null 2>&1; then
		sudo groupadd docker
	fi

	sudo usermod -aG docker "$USER"
	sudo systemctl enable --now docker.service &>/dev/null || abort "Failed enable docker.service."
	sudo systemctl enable --now containerd.service &>/dev/null || abort "Failed enable containerd.service."

	success "docker configuration complete!"
}

configure_ssh_keys() {
	local dotfiles_folder="$1"

	decrypt "SSH key decryption" "$dotfiles_folder/.ssh/id_ed25519.enc" "$dotfiles_folder/.ssh/id_ed25519"
	copy_path "$dotfiles_folder/.ssh/config" "$HOME/.ssh/config"
	copy_path "$dotfiles_folder/.ssh/authorized_keys" "$HOME/.ssh/authorized_keys"
	copy_path "$dotfiles_folder/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519"
	copy_path "$dotfiles_folder/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ed25519.pub"
	chmod 600 "$HOME/.ssh/"*

	success "ssh key configuration complete!"
}
