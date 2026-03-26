#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared.sh"

assert_running_arch() {
    if ! grep -qi "arch" /etc/os-release 2>/dev/null; then
        error "This script is intended for Arch Linux."
        exit 1
    fi
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

setup_pacman_keys() {
    [[ "$(whoami)" != "root" ]] && return 0

    if pacman-key --list-keys &>/dev/null && pacman-key --list-keys archlinux &>/dev/null; then
        success "Pacman keyring is already initialised and populated."
        return 0
    fi

    info "Initialising pacman keyring..."
    pacman-key --init &>/dev/null

    info "Populating archlinux keys..."
    pacman-key --populate archlinux &>/dev/null

    success "Pacman keyring setup complete."
}

setup_sudo() {
    [[ "$(whoami)" != "root" ]] && return 0

    if ! command -v sudo >/dev/null 2>&1; then
        info "Installing sudo..."
        pacman -Sy --noconfirm --needed sudo
    fi

    if ! getent group sudo >/dev/null 2>&1; then
        info "Adding sudo group..."
        groupadd sudo
    fi

    if grep -q "^#[[:space:]]*%sudo[[:space:]]\+ALL=(ALL:ALL)[[:space:]]\+ALL" /etc/sudoers 2>/dev/null; then
        sed -i 's/^#[[:space:]]*%sudo[[:space:]]\+ALL=(ALL:ALL)[[:space:]]\+ALL/%sudo ALL=(ALL:ALL) ALL/' /etc/sudoers
    elif ! grep -q "^%sudo[[:space:]]\+ALL=(ALL:ALL)[[:space:]]\+ALL" /etc/sudoers 2>/dev/null; then
        echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers
    fi

    success "sudo is configured."
}

setup_user() {
    local script_dir="$1"

    if [ -z "$script_dir" ]; then
        error "setup_user requires <script_dir> argument"
        return 1
    fi

    [[ "$(whoami)" != "root" ]] && return 0

    if ! id -u fabi >/dev/null 2>&1; then
        info "Creating user fabi..."
        useradd -m -G sudo -u 1000 fabi

        info "Please set a password for the new user 'fabi'."
        passwd fabi || { error "Failed to set password. Setup cannot continue securely."; exit 1; }
    fi

    #set_wsl_default_user "fabi"

    if [[ "$(id -un)" != "fabi" ]]; then
        info "Switching to user fabi for the rest of the script..."
        exec su - fabi -c "DOTFILES_FOLDER='$DOTFILES_FOLDER' DOTFILES_LOG_FILE='$DOTFILES_LOG_FILE' DOTFILES_TEMP_LOG_FILE='$DOTFILES_TEMP_LOG_FILE' \"$script_dir/$(basename "${BASH_SOURCE[0]}")\""
    fi
}

change_wsl_distribution_conf() {
    local conf_file="/etc/wsl-distribution.conf"
    local desired
    desired=$(cat <<'EOF'
[oobe]
defaultUid = 1000
defaultName = archlinux

[shortcut]
icon = /usr/lib/wsl/archlinux.ico
EOF
    )

    if [ -f "$conf_file" ] && [ "$(cat "$conf_file")" = "$desired" ]; then
        success "$conf_file already has the desired content."
        return 0
    fi

    info "Writing $conf_file..."
    echo "$desired" | safe_sudo tee "$conf_file" > /dev/null
    success "$conf_file has been updated."
}

set_wsl_default_user() {
    local CURRENT_USER
    CURRENT_USER=$(whoami)
    local TARGET_USER="${1:-$CURRENT_USER}"
    local WSL_CONF="/etc/wsl.conf"

    info "Setting $TARGET_USER as WSL default user."

    if [ ! -f "$WSL_CONF" ]; then
        info "Creating $WSL_CONF..."
        echo -e "[user]\ndefault=$TARGET_USER" | safe_sudo tee "$WSL_CONF" > /dev/null
        return 0
    fi

    if grep -q "default=$TARGET_USER" "$WSL_CONF"; then
        success "Success: Default user is already set to $TARGET_USER."
        return 0
    fi

    if grep -q "\[user\]" "$WSL_CONF"; then
        info "Updating [user] section in $WSL_CONF..."
        safe_sudo sed -i "/\[user\]/a default=$TARGET_USER" "$WSL_CONF"
    else
        info "Adding [user] section to $WSL_CONF..."
        echo -e "\n[user]\ndefault=$TARGET_USER" | safe_sudo tee -a "$WSL_CONF" > /dev/null
    fi

    success "Done. WSL default user has been set to $TARGET_USER."
}

install_packages() {
    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo is not available; cannot install packages."
        exit 1
    fi

    info "Updating package cache..."
    safe_sudo pacman -Syu --noconfirm

    info "Installing base packages..."
    safe_sudo pacman -S --noconfirm --needed \
        git base-devel curl neovim chafa ueberzugpp viu unzip wget gzip tar rsync openssh fish ripgrep fd bat zoxide git-delta zellij mise wl-clipboard yazi ffmpeg p7zip jq poppler fzf resvg imagemagick

    info "Enabling sshd service..."
    safe_sudo systemctl enable --now sshd || warning "Failed to enable / start sshd."

    install_shared_tooling

    info "Package installation complete."
}

main() {
    init_logging
    assert_running_in_wsl
    assert_running_arch
    unlock_root
    setup_pacman_keys
    setup_sudo
    echo "sudo before"
    sudo -v
    setup_user "$SCRIPT_DIR"
    echo "sudo after"
    sudo -v
    change_wsl_distribution_conf
    install_packages
    setup_dotfiles "$DOTFILES_FOLDER"
    set_fish_default_shell
    finalize_logging

    info "System setup complete. Rebooting to apply changes..."
    safe_sudo reboot
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" || "$0" == *"bash"* ]]; then
    main "$@"
fi
