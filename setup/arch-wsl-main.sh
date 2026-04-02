#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared.sh"

TEMP_SUDOERS="/etc/sudoers.d/passwordless-bootstrap"

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
        pacman -Sy --noconfirm --needed sudo &> /dev/null
    fi

    if ! getent group sudo >/dev/null 2>&1; then
        info "Adding sudo group..."
        groupadd --gid 27 sudo
    fi

    if grep -q "^#[[:space:]]*%sudo[[:space:]]\+ALL=(ALL:ALL)[[:space:]]\+ALL" /etc/sudoers 2>/dev/null; then
        info "Configuring sudoers..."
        sed -i 's/^#[[:space:]]*%sudo[[:space:]]\+ALL=(ALL:ALL)[[:space:]]\+ALL/%sudo ALL=(ALL:ALL) ALL/' /etc/sudoers
    elif ! grep -q "^%sudo[[:space:]]\+ALL=(ALL:ALL)[[:space:]]\+ALL" /etc/sudoers 2>/dev/null; then
        info "Configuring sudoers..."
        echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers
    fi

    success "sudo is configured."
}

setup_user() {
    [[ "$(whoami)" != "root" ]] && return 0

    if ! id -u fabi >/dev/null 2>&1; then
        info "Creating user fabi..."
        groupadd --gid 1000 fabi
        useradd --create-home --groups sudo --uid 1000 --gid 1000 fabi

        info "Please set a password for the new user 'fabi'."
        passwd fabi || { error "Failed to set password. Setup cannot continue securely."; exit 1; }
    fi

    echo "fabi ALL=(ALL:ALL) NOPASSWD: ALL" > "$TEMP_SUDOERS"
    chmod 0440 "$TEMP_SUDOERS"

    info "Switching to user fabi for the rest of the script..."
    exec sudo -u fabi env DOTFILES_FOLDER="$DOTFILES_FOLDER" DOTFILES_LOG_FILE="$DOTFILES_LOG_FILE" bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
}

remount_c() {
    if [ "$#" -eq 0 ]; then
        echo "Usage: remount_c <uid> [gid]"
        return 1
    fi

    local TARGET_UID=$1
    local TARGET_GID=${2:-$1}
    local CURRENT_UID
    CURRENT_UID=$(stat -c '%u' /mnt/c)
    local CURRENT_GID
    CURRENT_GID=$(stat -c '%g' /mnt/c)

    if [ "$CURRENT_UID" -ne "$TARGET_UID" ] || [ "$CURRENT_GID" -ne "$TARGET_GID" ]; then
        cd / || return 1
        sudo mount -t "drvfs" "C:\\" "/mnt/c" -o "rw,noatime,uid=$TARGET_UID,gid=$TARGET_GID,cache=5,access=client,msize=65536"
    else
        echo "Already mounted with correct UID/GID."
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
    echo "$desired" | sudo tee "$conf_file" > /dev/null
    success "$conf_file has been updated."
}

install_packages() {
    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo is not available; cannot install packages."
        exit 1
    fi

    info "Updating package cache..."
    sudo pacman -Syu --noconfirm &> /dev/null

    info "Installing base packages..."
    sudo pacman -S --noconfirm --needed \
        git base-devel curl docker neovim chafa ueberzugpp viu unzip wget gzip tar rsync openssh fish ripgrep fd bat zoxide git-delta zellij mise wl-clipboard yazi ffmpeg p7zip jq poppler fzf resvg imagemagick

    info "Installing mise..."
    curl https://mise.run | sh

    info "Enabling sshd service..."
    sudo systemctl enable --now sshd || warning "Failed to enable / start sshd."

    info "Configuring Docker..."
    sudo groupadd docker
    sudo usermod -aG docker $USER
    sudo systemctl enable docker.service
    sudo systemctl enable containerd.service

    install_shared_tooling

    info "Package installation complete."
}

main() {
    init_logging
    assert_running_in_wsl
    assert_running_arch

    # Only run as root
    unlock_root
    setup_pacman_keys
    setup_sudo
    setup_user

    trap "sudo rm -f $TEMP_SUDOERS > /dev/null 2>&1" EXIT
    remount_c 1000
    change_wsl_distribution_conf
    install_packages
    setup_dotfiles
    set_fish_default_shell
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" || "$0" == *"bash"* ]]; then
    main "$@"
fi
