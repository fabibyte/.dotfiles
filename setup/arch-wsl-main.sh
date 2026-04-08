#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/shared.sh"

readonly BOOTSTRAP_USER="fabi"
readonly BOOTSTRAP_UID="1000"
readonly BOOTSTRAP_GID="1000"
readonly SUDO_GROUP_GID="27"
readonly TEMP_SUDOERS="/etc/sudoers.d/passwordless-bootstrap"
readonly SUDO_GROUP_CONFIG="/etc/sudoers.d/10-sudo-group"
SETUP_COMPLETED="false"

cleanup_temp_sudoers() {
    if [[ -f "$TEMP_SUDOERS" ]]; then
        rm -f -- "$TEMP_SUDOERS"
    fi
}

assert_running_arch() {
    if ! grep -qi "arch" /etc/os-release 2>/dev/null; then
        abort "This script is intended for Arch Linux."
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

setup_sudo() {
    [[ "$(whoami)" != "root" ]] && return 0

    if ! getent group sudo >/dev/null 2>&1; then
        info "Adding sudo group..."
        groupadd --gid "$SUDO_GROUP_GID" sudo
    fi

    info "Configuring sudoers..."
    printf '%%sudo ALL=(ALL:ALL) ALL\n' >"$SUDO_GROUP_CONFIG"
    chmod 0440 "$SUDO_GROUP_CONFIG"
    visudo -cf "$SUDO_GROUP_CONFIG" >/dev/null || abort "Could not validate $SUDO_GROUP_CONFIG."

    success "sudo is configured."
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

    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$BOOTSTRAP_USER" >"$TEMP_SUDOERS"
    chmod 0440 "$TEMP_SUDOERS"
    visudo -cf "$TEMP_SUDOERS" >/dev/null || abort "Could not validate $TEMP_SUDOERS."
}

run_as_bootstrap_user() {
    [[ "$(whoami)" != "root" ]] && return 0

    info "Switching to user $BOOTSTRAP_USER for the rest of the script..."
    sudo -u "$BOOTSTRAP_USER" env \
        DOTFILES_FOLDER="$DOTFILES_FOLDER" \
        DOTFILES_LOG_FILE="$DOTFILES_LOG_FILE" \
        bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
}

remount_c() {
    if [ "$#" -eq 0 ]; then
        echo "Usage: remount_c <uid> [gid]"
        return 1
    fi

    local target_uid="$1"
    local target_gid="${2:-$1}"
    local current_uid
    local current_gid
    current_uid=$(stat -c '%u' /mnt/c)
    current_gid=$(stat -c '%g' /mnt/c)

    if [ "$current_uid" -ne "$target_uid" ] || [ "$current_gid" -ne "$target_gid" ]; then
        sudo mount -t "drvfs" "C:\\" "/mnt/c" -o "rw,noatime,uid=$target_uid,gid=$target_gid,cache=5,access=client,msize=65536"
    else
        info "Already mounted with correct UID/GID."
    fi
}

change_wsl_distribution_conf() {
    local conf_file="/etc/wsl-distribution.conf"
    local desired
    desired=$(
        cat <<EOF
[oobe]
defaultUid = $BOOTSTRAP_UID
defaultName = archlinux

[shortcut]
icon = /usr/lib/wsl/archlinux.ico
EOF
    )

    if [ -f "$conf_file" ] && [ "$(<"$conf_file")" = "$desired" ]; then
        success "$conf_file already has the desired content."
        return 0
    fi

    info "Writing $conf_file..."
    printf '%s\n' "$desired" | sudo tee "$conf_file" >/dev/null
    success "$conf_file has been updated."
}

install_packages() {
    if ! command -v sudo >/dev/null 2>&1; then
        abort "sudo is not available; cannot install packages."
    fi

    info "Updating package cache..."
    sudo pacman -Syu --noconfirm >/dev/null

    info "Installing base packages..."
    sudo pacman -S --noconfirm --needed \
        git base-devel curl docker neovim chafa ueberzugpp viu unzip wget gzip tar rsync openssh fish ripgrep fd bat zoxide git-delta zellij wl-clipboard yazi ffmpeg p7zip jq poppler fzf resvg imagemagick

    info "Installing mise..."
    curl -fsSL https://mise.run | sh &>/dev/null || abort "Failed to install mise."

    info "Activating mise..."
    export PATH="$HOME/.local/bin:$PATH"
    eval "$(mise activate bash --shims)"

    info "Enabling sshd service..."
    sudo systemctl enable --now sshd &>/dev/null || abort "Failed enable sshd."

    info "Configuring Docker..."

    if ! getent group docker >/dev/null 2>&1; then
        sudo groupadd docker
    fi

    sudo usermod -aG docker "$USER"
    sudo systemctl enable --now docker.service &>/dev/null || abort "Failed enable docker.service."
    sudo systemctl enable --now containerd.service &>/dev/null || abort "Failed enable containerd.service."

    install_shared_tooling

    info "Package installation complete."
}

main() {
    init_logging
    assert_running_in_wsl
    assert_running_arch

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

    remount_c "$BOOTSTRAP_UID" "$BOOTSTRAP_GID"
    change_wsl_distribution_conf
    install_packages
    setup_dotfiles
    set_fish_default_shell
    SETUP_COMPLETED="true"
    cleanup_bootstrap_dir_if_present "$SCRIPT_DIR" '.arch-wsl-bootstrap'
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" || "$0" == *"bash"* ]]; then
    main "$@"
fi
