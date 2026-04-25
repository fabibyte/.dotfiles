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
    local code=1
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        code="$1"
        shift
    fi
    error "$*"
    exit "$code"
}

assert_running_in_wsl() {
    if ! grep -qi "microsoft" /proc/version 2>/dev/null && [ -z "${WSL_DISTRO_NAME-}" ]; then
        abort "This script is intended to run inside WSL."
    fi
}

ensure_dotfiles_cloned() {
    if [ -d "$DOTFILES_FOLDER/.git" ]; then
        info "Dotfiles already cloned at $DOTFILES_FOLDER."
        return
    fi

    info "Cloning dotfiles into $DOTFILES_FOLDER..."
    mkdir -p "$DOTFILES_FOLDER"

    {
        git -C "$DOTFILES_FOLDER" init &&
            git -C "$DOTFILES_FOLDER" remote add origin "https://github.com/fabibyte/.dotfiles.git" &&
            git -C "$DOTFILES_FOLDER" fetch origin main &&
            git -C "$DOTFILES_FOLDER" checkout -B main --track origin/main
    } &>/dev/null || abort "Failed to clone dotfiles."

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
        current=$(readlink -f "$tgt")
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

    if [ -f "$target" ]; then
        info "File already present, skipping fetch: $target"
        return
    fi

    mkdir -p "$(dirname "$target")"
    if curl -fsSL "$url" -o "$target"; then
        success "Fetched $url -> $target"
    else
        error "Failed to fetch $url"
        return 1
    fi
}

cleanup_bootstrap_dir_if_present() {
    local bootstrap_dir="$1"
    local expected_name="$2"

    if [[ -z "$bootstrap_dir" || -z "$expected_name" ]]; then
        error "cleanup_bootstrap_dir_if_present requires <dir> and <expected-name> arguments"
        return 1
    fi

    if [[ ! -d "$bootstrap_dir" ]]; then
        return 0
    fi

    if [[ "$(basename "$bootstrap_dir")" != "$expected_name" ]]; then
        return 0
    fi

    nohup sh -c 'sleep 1; rm -rf -- "$1"' _ "$bootstrap_dir" >/dev/null 2>&1 &
}

decrypt_ssh_keys() {
    local encrypted="$DOTFILES_FOLDER/.ssh/id_ed25519.enc"
    local decrypted="$DOTFILES_FOLDER/.ssh/id_ed25519"
    local max_attempts=3
    local attempt
    local passphrase

    if [ -f "$decrypted" ]; then
        info "SSH key already decrypted."
        return
    fi

    if [ ! -f "$encrypted" ]; then
        warning "Encrypted SSH key not found: $encrypted"
        return
    fi

    info "Decrypting SSH keys..."

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        if [ ! -r /dev/tty ]; then
            error "SSH key decryption failed after $max_attempts attempts."
            return 1
        fi

        read -r -s -p "enter AES-256-CBC decryption password: " passphrase </dev/tty
        printf '\n' >/dev/tty

        if printf '%s' "$passphrase" | openssl aes-256-cbc -d -salt -pbkdf2 -iter 100000 -pass stdin -in "$encrypted" -out "$decrypted" >/dev/null 2>&1; then
            chmod 600 "$decrypted"
            success "SSH key decrypted."
            link_tree "$DOTFILES_FOLDER/.ssh" "$HOME/.ssh"
            return
        fi

        rm -f "$decrypted"

        if [ "$attempt" -lt "$max_attempts" ]; then
            warning "SSH key decryption failed. $((max_attempts - attempt)) attempt(s) remaining."
        else
            error "SSH key decryption failed after $max_attempts attempts."
            return 1
        fi
    done
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
            echo "Fuck"
			#hererocks "$HOME/.local/share/nvim/lazy-rocks/hererocks" -l5.1 -rlatest
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
