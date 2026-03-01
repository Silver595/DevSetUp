#!/usr/bin/env bash
# =============================================================================
# lib/install.sh — Idempotent install function dispatcher
# =============================================================================
# Dependencies: lib/logger.sh, lib/detect.sh must be sourced first.
# All install_* functions honour DRY_RUN=true.
# =============================================================================

# ── Low-level package install helpers ────────────────────────────────────────

_pkg_install() {
    # Install one or more packages with the detected package manager.
    case "$PKG_MANAGER" in
        apt)
            run_cmd $SUDO apt-get install -y "$@"
            ;;
        dnf)
            run_cmd $SUDO dnf install -y "$@"
            ;;
        yum)
            run_cmd $SUDO yum install -y "$@"
            ;;
        pacman)
            run_cmd $SUDO pacman -S --noconfirm "$@"
            ;;
        zypper)
            run_cmd $SUDO zypper install -y "$@"
            ;;
        brew)
            run_cmd brew install "$@"
            ;;
        *)
            log_error "Unknown package manager: $PKG_MANAGER"
            return 1
            ;;
    esac
}

_pkg_update() {
    case "$PKG_MANAGER" in
        apt)    run_cmd $SUDO apt-get update -qq ;;
        dnf)    run_cmd $SUDO dnf check-update -q || true ;;
        yum)    run_cmd $SUDO yum check-update -q || true ;;
        pacman) run_cmd $SUDO pacman -Sy --noconfirm ;;
        zypper) run_cmd $SUDO zypper refresh ;;
        brew)   run_cmd brew update ;;
    esac
}

# ── Guard: skip if already installed ─────────────────────────────────────────
_already_installed() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        log_skip "$cmd is already installed ($(command -v "$cmd")). Skipping."
        return 0   # true  → skip
    fi
    return 1       # false → proceed
}

# =============================================================================
# ── Individual tool installers ────────────────────────────────────────────────
# =============================================================================

install_git() {
    _already_installed git && return 0
    log_step "Installing Git..."
    spinner_start "Installing git"
    _pkg_install git
    spinner_stop ok
    log_ok "Git installed: $(git --version 2>/dev/null)"
}

# ─ Docker ────────────────────────────────────────────────────────────────────
install_docker() {
    _already_installed docker && return 0
    log_step "Installing Docker..."
    spinner_start "Installing Docker"

    case "$OS_FAMILY" in
        debian)
            run_cmd $SUDO apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            _pkg_install ca-certificates curl gnupg lsb-release
            run_cmd $SUDO mkdir -p /etc/apt/keyrings
            run_cmd curl -fsSL https://download.docker.com/linux/"${OS_ID}"/gpg \
                | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} $(lsb_release -cs) stable" \
                | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
            _pkg_update
            _pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        rhel)
            run_cmd $SUDO dnf remove -y docker docker-client docker-client-latest \
                docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
            run_cmd $SUDO dnf install -y dnf-plugins-core
            run_cmd $SUDO dnf config-manager --add-repo \
                https://download.docker.com/linux/fedora/docker-ce.repo
            _pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch)
            _pkg_install docker docker-compose
            ;;
        *)
            log_warn "Docker auto-install not supported on $OS_ID. Please install manually."
            spinner_stop skip; return 1
            ;;
    esac

    # Enable & start service
    run_cmd $SUDO systemctl enable --now docker
    # Add current user to docker group
    if [[ -n "$SUDO_USER" || "$EUID" -ne 0 ]]; then
        local real_user="${SUDO_USER:-$USER}"
        run_cmd $SUDO usermod -aG docker "$real_user"
        log_info "Added $real_user to the docker group. Re-login or run: newgrp docker"
    fi

    spinner_stop ok
    log_ok "Docker installed: $(docker --version 2>/dev/null)"
}

# ─ kubectl ───────────────────────────────────────────────────────────────────
install_kubectl() {
    _already_installed kubectl && return 0
    log_step "Installing kubectl..."
    spinner_start "Installing kubectl"

    local stable_ver
    stable_ver="$(curl -s https://dl.k8s.io/release/stable.txt)"
    run_cmd curl -Lo /tmp/kubectl \
        "https://dl.k8s.io/release/${stable_ver}/bin/linux/${ARCH/x86_64/amd64}/kubectl"
    run_cmd chmod +x /tmp/kubectl
    run_cmd $SUDO mv /tmp/kubectl /usr/local/bin/kubectl

    spinner_stop ok
    log_ok "kubectl installed: $(kubectl version --client --short 2>/dev/null)"
}

# ─ Helm ──────────────────────────────────────────────────────────────────────
install_helm() {
    _already_installed helm && return 0
    log_step "Installing Helm..."
    spinner_start "Installing Helm"

    run_cmd curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm.sh
    run_cmd chmod +x /tmp/get-helm.sh
    run_cmd /tmp/get-helm.sh

    spinner_stop ok
    log_ok "Helm installed: $(helm version --short 2>/dev/null)"
}

# ─ Terraform ─────────────────────────────────────────────────────────────────
install_terraform() {
    _already_installed terraform && return 0
    log_step "Installing Terraform..."
    spinner_start "Installing Terraform"

    case "$OS_FAMILY" in
        debian)
            _pkg_install gnupg software-properties-common
            run_cmd wget -O- https://apt.releases.hashicorp.com/gpg \
                | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
                | $SUDO tee /etc/apt/sources.list.d/hashicorp.list
            _pkg_update
            _pkg_install terraform
            ;;
        rhel)
            run_cmd $SUDO dnf install -y dnf-plugins-core
            run_cmd $SUDO dnf config-manager --add-repo \
                https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
            _pkg_install terraform
            ;;
        arch)
            # AUR helper assumed to be yay or paru
            if command -v yay &>/dev/null; then
                run_cmd yay -S --noconfirm terraform
            elif command -v paru &>/dev/null; then
                run_cmd paru -S --noconfirm terraform
            else
                log_warn "Install terraform from AUR manually (yay/paru not found)."
                spinner_stop skip; return 1
            fi
            ;;
        *)
            log_warn "Terraform auto-install not supported on $OS_ID."
            spinner_stop skip; return 1
            ;;
    esac

    spinner_stop ok
    log_ok "Terraform installed: $(terraform version 2>/dev/null | head -1)"
}

# ─ AWS CLI ───────────────────────────────────────────────────────────────────
install_awscli() {
    _already_installed aws && return 0
    log_step "Installing AWS CLI v2..."
    spinner_start "Installing AWS CLI"

    local tmp_dir; tmp_dir="$(mktemp -d)"
    local archive_url

    case "$ARCH" in
        x86_64)  archive_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
        aarch64) archive_url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
        *)
            log_warn "AWS CLI auto-install unsupported for arch: $ARCH"
            spinner_stop skip; return 1
            ;;
    esac

    run_cmd curl -fsSo "$tmp_dir/awscliv2.zip" "$archive_url"
    run_cmd unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir"
    run_cmd $SUDO "$tmp_dir/aws/install"
    rm -rf "$tmp_dir"

    spinner_stop ok
    log_ok "AWS CLI installed: $(aws --version 2>/dev/null)"
}

# ─ Node.js / nvm ─────────────────────────────────────────────────────────────
install_nvm() {
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$nvm_dir/nvm.sh" ]]; then
        log_skip "nvm already installed at $nvm_dir. Skipping."
        return 0
    fi
    log_step "Installing nvm (Node Version Manager)..."
    spinner_start "Installing nvm"

    local nvm_version
    nvm_version="$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)"
    run_cmd curl -fsSo- "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" | bash

    spinner_stop ok
    log_ok "nvm installed. Load it with: source ~/.nvm/nvm.sh"
    log_info "Installing Node.js LTS via nvm..."
    # shellcheck source=/dev/null
    export NVM_DIR="$nvm_dir"
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    run_cmd nvm install --lts
    run_cmd nvm use --lts
    log_ok "Node.js installed: $(node --version 2>/dev/null)"
}

# ─ Python / pip ──────────────────────────────────────────────────────────────
install_python() {
    if _already_installed python3 && _already_installed pip3; then return 0; fi
    log_step "Installing Python3 & pip..."
    spinner_start "Installing Python3 & pip"

    case "$PKG_MANAGER" in
        apt)    _pkg_install python3 python3-pip python3-venv ;;
        dnf|yum) _pkg_install python3 python3-pip ;;
        pacman) _pkg_install python python-pip ;;
        zypper) _pkg_install python3 python3-pip ;;
        brew)   run_cmd brew install python3 ;;
    esac

    spinner_stop ok
    log_ok "Python installed: $(python3 --version 2>/dev/null)"
    log_ok "pip installed: $(pip3 --version 2>/dev/null)"
}

# ── Dispatcher ────────────────────────────────────────────────────────────────
# install_tool TOOL_NAME — calls install_<name>
install_tool() {
    local tool="${1,,}"   # lowercase
    local fn="install_${tool}"
    if declare -f "$fn" > /dev/null; then
        "$fn"
    else
        log_error "No installer defined for: $tool"
        return 1
    fi
}

# ── List available tools ──────────────────────────────────────────────────────
list_tools() {
    declare -F | awk '{print $3}' | grep '^install_' | sed 's/^install_//' | sort
}
