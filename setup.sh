#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_error() { printf "${RED}ERROR: %s${NC}\n" "$1" >&2; }
log_success() { printf "${GREEN}✓ %s${NC}\n" "$1"; }
log_info() { printf "${BLUE}ℹ %s${NC}\n" "$1"; }
log_warning() { printf "${YELLOW}⚠ %s${NC}\n" "$1"; }

# Check if command exists
has_command() { command -v "$1" >/dev/null 2>&1; }

# Check if package is installed
is_installed() { dpkg -l "$1" 2>/dev/null | grep -q "^ii"; }

# Check if snap is installed
is_snap_installed() { snap list "$1" >/dev/null 2>&1; }

# Install apt package if not present
install_apt() {
    local pkg="$1"
    if is_installed "$pkg"; then
        log_info "$pkg already installed"
    else
        log_info "Installing $pkg..."
        sudo apt install -y "$pkg"
        log_success "$pkg installed"
    fi
}

# Install snap package if not present
install_snap() {
    local pkg="$1"
    local flags="${2:-}"
    if is_snap_installed "$pkg"; then
        log_info "$pkg already installed"
    else
        log_info "Installing $pkg via snap..."
        sudo snap install "$pkg" $flags
        log_success "$pkg installed"
    fi
}

# Append to file if line doesn't exist
append_if_missing() {
    local line="$1"
    local file="$2"
    if ! grep -Fxq "$line" "$file" 2>/dev/null; then
        echo "$line" >> "$file"
        log_success "Added to $file"
    fi
}

log_info "Starting development environment setup..."

# Update system first
log_info "Updating system packages..."
sudo apt update && sudo apt upgrade -y
sudo snap refresh

# Install basic tools
install_apt wget
install_apt neovim

# Install applications
install_snap mattermost-desktop
install_snap spotify
install_snap code --classic
install_apt tilix
install_apt network-manager-l2tp-gnome

# Install Chrome
if ! has_command google-chrome; then
    log_info "Installing Chrome..."
    chrome_deb="google-chrome-stable_current_amd64.deb"
    wget "https://dl.google.com/linux/direct/$chrome_deb"
    sudo dpkg -i "$chrome_deb" || sudo apt-get install -f -y
    rm -f "$chrome_deb"
    log_success "Chrome installed"
fi

# Remove Firefox (after Chrome install)
if is_snap_installed firefox || is_installed firefox; then
    log_info "Removing Firefox..."
    sudo snap remove firefox 2>/dev/null || true
    sudo apt remove --purge -y firefox* 2>/dev/null || true
    log_success "Firefox removed"
fi

# Install mise
if ! is_installed mise; then
    log_info "Installing mise..."
    sudo install -dm 755 /etc/apt/keyrings
    wget -qO- https://mise.jdx.dev/gpg-key.pub | gpg --dearmor | sudo tee /etc/apt/keyrings/mise-archive-keyring.gpg >/dev/null
    echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=amd64] https://mise.jdx.dev/deb stable main" | sudo tee /etc/apt/sources.list.d/mise.list
    sudo apt update && sudo apt install -y mise
    append_if_missing 'eval "$(~/.local/bin/mise activate bash)"' "$HOME/.bashrc"
    log_success "mise installed"
fi

# Install development tools via mise
if has_command mise; then
    log_info "Installing development tools via mise..."
    mise use --global node@latest deno@latest python@latest lazydocker@latest lazygit@latest || log_warning "Some mise tools failed"
fi

# Install Docker
if ! is_installed docker-ce; then
    log_info "Installing Docker..."
    sudo apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list
    sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER"
    log_success "Docker installed"
    log_warning "Log out/in for docker group to take effect"
fi

# Install Claude Code
if ! has_command claude; then
    log_info "Installing Claude Code..."
    npm install --global @anthropic-ai/claude-code && log_success "Claude Code installed"
fi

# Generate SSH key
ssh_key="$HOME/.ssh/id_rsa"
if [[ ! -f "$ssh_key" ]]; then
    log_info "Generating SSH key..."
    ssh-keygen -t rsa -f "$ssh_key" -N ""
    log_success "SSH key generated at $ssh_key"
fi

# Enable GNOME per-monitor scaling
log_info "Enabling per-monitor scaling..."
gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']"
log_success "Per-monitor scaling enabled"

log_success "Setup completed!"
