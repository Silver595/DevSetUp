#!/usr/bin/env bash
# =============================================================================
# lib/install.sh — Idempotent install function dispatcher
# =============================================================================
# Dependencies: lib/logger.sh, lib/detect.sh must be sourced first.
# All install_* functions honour DRY_RUN=true.
# =============================================================================

# ── Low-level package install helpers ────────────────────────────────────────

_pkg_install() {
    case "$PKG_MANAGER" in
        apt)    run_cmd $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        dnf)    run_cmd $SUDO dnf install -y "$@" ;;
        yum)    run_cmd $SUDO yum install -y "$@" ;;
        pacman) run_cmd $SUDO pacman -S --noconfirm "$@" ;;
        zypper) run_cmd $SUDO zypper install -y "$@" ;;
        brew)   run_cmd brew install "$@" ;;
        *)
            log_error "Unknown package manager: $PKG_MANAGER"
            return 1
            ;;
    esac
}

_pkg_update() {
    log_step "Updating package index..."
    case "$PKG_MANAGER" in
        # always || true — a stale index should never abort the entire install
        apt)    run_cmd $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true ;;
        dnf)    run_cmd $SUDO dnf check-update -q || true ;;
        yum)    run_cmd $SUDO yum check-update -q || true ;;
        pacman) run_cmd $SUDO pacman -Sy --noconfirm || true ;;
        zypper) run_cmd $SUDO zypper refresh || true ;;
        brew)   run_cmd brew update || true ;;
    esac
}

# ── Guard: skip if already installed ─────────────────────────────────────────
_already_installed() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        log_skip "$cmd is already installed ($(command -v "$cmd")). Skipping."
        return 0   # true  → already there, skip
    fi
    return 1       # false → not found, proceed
}

# ── Guard: returns 0 (true) when DRY_RUN is active ───────────────────────────
_dry_run() { [[ "${DRY_RUN:-false}" == "true" ]]; }

# ── Wrapper: run install body, catch failures, always stop spinner ────────────
# In dry-run mode the body is skipped entirely — avoids any rogue $SUDO calls
# inside body functions that run_cmd doesn't intercept.
_do_install() {
    local tool="$1"; shift

    if _dry_run; then
        echo -e "  ${DIM}[dry-run]${RESET} Would install: ${CYAN}${tool}${RESET}"
        return 0
    fi

    local exit_code=0
    "$@" || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        spinner_stop fail
        log_error "Failed to install $tool (exit code $exit_code)."
        log_info  "Tip: check internet connection, sudo access, and the log above."
        return $exit_code
    fi
}

# ── Post-install confirmation (skipped in dry-run) ───────────────────────────
_installed_ok() {
    _dry_run && return 0
    spinner_stop ok
    log_ok "$*"
}

# =============================================================================
# ── Individual tool installers ────────────────────────────────────────────────
# =============================================================================

install_git() {
    _already_installed git && return 0
    log_step "Installing Git..."
    spinner_start "Installing git"
    _do_install git _pkg_install git || return 1
    _installed_ok "Git installed: $(git --version 2>/dev/null)"
}

# ─ Docker ────────────────────────────────────────────────────────────────────
_install_docker_body() {
    case "$OS_FAMILY" in
        debian)
            $SUDO apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg lsb-release
            $SUDO mkdir -p /etc/apt/keyrings
            curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
                | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} $(lsb_release -cs) stable" \
                | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
                docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        rhel)
            $SUDO dnf remove -y docker docker-client docker-client-latest \
                docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
            $SUDO dnf install -y dnf-plugins-core
            $SUDO dnf config-manager --add-repo \
                https://download.docker.com/linux/fedora/docker-ce.repo
            $SUDO dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch)
            $SUDO pacman -S --noconfirm docker docker-compose
            ;;
        *)
            log_warn "Docker auto-install not supported on $OS_ID. Install manually: https://docs.docker.com/engine/install/"
            return 1
            ;;
    esac

    $SUDO systemctl enable --now docker || true
    local real_user="${SUDO_USER:-$USER}"
    $SUDO usermod -aG docker "$real_user" 2>/dev/null || true
    log_info "Added $real_user to the docker group. Re-login or run: newgrp docker"
}

install_docker() {
    _already_installed docker && return 0
    log_step "Installing Docker..."
    spinner_start "Installing Docker"
    _do_install docker _install_docker_body || return 1
    _installed_ok "Docker installed: $(docker --version 2>/dev/null)"
}

# ─ kubectl ───────────────────────────────────────────────────────────────────
_install_kubectl_body() {
    local stable_ver
    stable_ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)" \
        || { log_error "Could not fetch kubectl stable version — check internet."; return 1; }

    local kube_arch="${ARCH/x86_64/amd64}"
    kube_arch="${kube_arch/aarch64/arm64}"

    curl -fsSL "https://dl.k8s.io/release/${stable_ver}/bin/linux/${kube_arch}/kubectl" \
        -o /tmp/kubectl || return 1
    chmod +x /tmp/kubectl
    $SUDO mv /tmp/kubectl /usr/local/bin/kubectl
}

install_kubectl() {
    _already_installed kubectl && return 0
    log_step "Installing kubectl..."
    spinner_start "Installing kubectl"
    _do_install kubectl _install_kubectl_body || return 1
    _installed_ok "kubectl installed: $(kubectl version --client 2>/dev/null | head -1)"
}

# ─ Helm ──────────────────────────────────────────────────────────────────────
_install_helm_body() {
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
        -o /tmp/get-helm.sh || return 1
    chmod +x /tmp/get-helm.sh
    DESIRED_VERSION="" /tmp/get-helm.sh
}

install_helm() {
    _already_installed helm && return 0
    log_step "Installing Helm..."
    spinner_start "Installing Helm"
    _do_install helm _install_helm_body || return 1
    _installed_ok "Helm installed: $(helm version --short 2>/dev/null)"
}

# ─ Terraform ─────────────────────────────────────────────────────────────────
_install_terraform_body() {
    case "$OS_FAMILY" in
        debian)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg software-properties-common wget
            wget -qO- https://apt.releases.hashicorp.com/gpg \
                | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
                | $SUDO tee /etc/apt/sources.list.d/hashicorp.list
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y terraform
            ;;
        rhel)
            $SUDO dnf install -y dnf-plugins-core
            $SUDO dnf config-manager --add-repo \
                https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
            $SUDO dnf install -y terraform
            ;;
        arch)
            if command -v yay &>/dev/null; then
                yay -S --noconfirm terraform
            elif command -v paru &>/dev/null; then
                paru -S --noconfirm terraform
            else
                log_warn "Install terraform from AUR manually (yay/paru not found)."
                return 1
            fi
            ;;
        *)
            log_warn "Terraform auto-install not supported on $OS_ID."
            return 1
            ;;
    esac
}

install_terraform() {
    _already_installed terraform && return 0
    log_step "Installing Terraform..."
    spinner_start "Installing Terraform"
    _do_install terraform _install_terraform_body || return 1
    _installed_ok "Terraform installed: $(terraform version 2>/dev/null | head -1)"
}

# ─ AWS CLI ───────────────────────────────────────────────────────────────────
_install_awscli_body() {
    local tmp_dir; tmp_dir="$(mktemp -d)"
    local archive_url

    case "$ARCH" in
        x86_64)  archive_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
        aarch64) archive_url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
        *)
            log_warn "AWS CLI auto-install unsupported for arch: $ARCH"
            rm -rf "$tmp_dir"
            return 1
            ;;
    esac

    curl -fsSo "$tmp_dir/awscliv2.zip" "$archive_url" || { rm -rf "$tmp_dir"; return 1; }
    unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir" || { rm -rf "$tmp_dir"; return 1; }
    $SUDO "$tmp_dir/aws/install"
    rm -rf "$tmp_dir"
}

install_awscli() {
    _already_installed aws && return 0
    log_step "Installing AWS CLI v2..."
    spinner_start "Installing AWS CLI"
    _do_install awscli _install_awscli_body || return 1
    _installed_ok "AWS CLI installed: $(aws --version 2>/dev/null)"
}

# ─ Node.js / nvm ─────────────────────────────────────────────────────────────
_install_nvm_body() {
    local nvm_version
    nvm_version="$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)" \
        || { log_error "Could not fetch nvm version — check internet."; return 1; }
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh" | bash
}

install_nvm() {
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$nvm_dir/nvm.sh" ]]; then
        log_skip "nvm already installed at $nvm_dir. Skipping."
        return 0
    fi
    log_step "Installing nvm (Node Version Manager)..."
    spinner_start "Installing nvm"
    _do_install nvm _install_nvm_body || return 1
    spinner_stop ok
    log_ok "nvm installed. Loading it now..."

    export NVM_DIR="$nvm_dir"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

    log_step "Installing Node.js LTS..."
    nvm install --lts && nvm use --lts \
        || log_warn "nvm installed but Node LTS setup failed. Run: nvm install --lts"
    log_ok "Node.js: $(node --version 2>/dev/null || echo 'open a new terminal and run: nvm install --lts')"
}

# ─ Python / pip ──────────────────────────────────────────────────────────────
_install_python_body() {
    case "$PKG_MANAGER" in
        apt)     $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3-venv ;;
        dnf|yum) $SUDO dnf install -y python3 python3-pip ;;
        pacman)  $SUDO pacman -S --noconfirm python python-pip ;;
        zypper)  $SUDO zypper install -y python3 python3-pip ;;
        brew)    brew install python3 ;;
    esac
}

install_python() {
    if _already_installed python3 && _already_installed pip3; then return 0; fi
    log_step "Installing Python3 & pip..."
    spinner_start "Installing Python3 & pip"
    _do_install python _install_python_body || return 1
    _installed_ok "Python: $(python3 --version 2>/dev/null)  |  pip: $(pip3 --version 2>/dev/null | awk '{print $1,$2}')"
}

# ── Dispatcher ────────────────────────────────────────────────────────────────
install_tool() {
    local tool="${1,,}"
    local fn="install_${tool}"
    if declare -f "$fn" > /dev/null; then
        "$fn"
    else
        log_error "No installer defined for: $tool"
        log_info  "Run 'devsetup --list' to see available tools."
        return 1
    fi
}

# ── List available tools ──────────────────────────────────────────────────────
list_tools() {
    declare -F | awk '{print $3}' | grep '^install_' | sed 's/^install_//' | sort
}
