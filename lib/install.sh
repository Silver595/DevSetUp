#!/usr/bin/env bash
# =============================================================================
# lib/install.sh — Robust installer with retry, lock detection, uninstall
# =============================================================================

# ── Package management helpers ────────────────────────────────────────────────

# Wait for dpkg/apt lock (apt only) — max 60 seconds
_wait_pkg_lock() {
    [[ "$PKG_MANAGER" != "apt" ]] && return 0
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; do
        if (( waited == 0 )); then
            log_warn "Package manager is locked (another process using apt). Waiting..."
            spinner_start "Waiting for apt lock"
        fi
        sleep 2; (( waited += 2 ))
        if (( waited > 60 )); then
            spinner_stop fail
            log_error "apt lock held for >60s. Run: sudo rm /var/lib/dpkg/lock-frontend"
            return 1
        fi
    done
    [[ $waited -gt 0 ]] && spinner_stop ok
    return 0
}

# curl with retry (3 attempts, exponential backoff)
_curl_retry() {
    local attempt=0 delay=1 max=3
    while (( attempt < max )); do
        curl "$@" && return 0
        (( attempt++ ))
        if (( attempt < max )); then
            log_warn "curl failed (attempt $attempt/$max). Retrying in ${delay}s..."
            sleep "$delay"; (( delay *= 2 ))
        fi
    done
    log_error "curl failed after $max attempts."
    return 1
}

_pkg_install() {
    _wait_pkg_lock || return 1
    case "$PKG_MANAGER" in
        apt)    run_cmd $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        dnf)    run_cmd $SUDO dnf install -y "$@" ;;
        yum)    run_cmd $SUDO yum install -y "$@" ;;
        pacman) run_cmd $SUDO pacman -S --noconfirm "$@" ;;
        zypper) run_cmd $SUDO zypper install -y "$@" ;;
        brew)   run_cmd brew install "$@" ;;
        *)      log_error "Unknown package manager: $PKG_MANAGER"; return 1 ;;
    esac
}

_pkg_remove() {
    _wait_pkg_lock || return 1
    case "$PKG_MANAGER" in
        apt)    run_cmd $SUDO apt-get remove -y "$@"; run_cmd $SUDO apt-get autoremove -y ;;
        dnf)    run_cmd $SUDO dnf remove -y "$@" ;;
        yum)    run_cmd $SUDO yum remove -y "$@" ;;
        pacman) run_cmd $SUDO pacman -Rns --noconfirm "$@" ;;
        zypper) run_cmd $SUDO zypper remove -y "$@" ;;
        brew)   run_cmd brew uninstall "$@" ;;
    esac
}

_pkg_update() {
    log_step "Refreshing package index..."
    _wait_pkg_lock || return 1
    case "$PKG_MANAGER" in
        apt)    run_cmd $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true ;;
        dnf)    run_cmd $SUDO dnf check-update -q || true ;;
        yum)    run_cmd $SUDO yum check-update -q || true ;;
        pacman) run_cmd $SUDO pacman -Sy --noconfirm || true ;;
        zypper) run_cmd $SUDO zypper refresh || true ;;
        brew)   run_cmd brew update || true ;;
    esac
}

_pkg_enable_service() {
    command -v systemctl &>/dev/null && run_cmd $SUDO systemctl enable --now "$1" || true
}

# ── Guards ────────────────────────────────────────────────────────────────────
_already_installed() {
    local cmd="$1"
    if command -v "$cmd" &>/dev/null; then
        log_skip "$cmd already installed → $(command -v "$cmd")"
        return 0
    fi
    return 1
}
_dry_run() { [[ "${DRY_RUN:-false}" == "true" ]]; }

# Core install wrapper — skips body in dry-run; catches failures cleanly
_do_install() {
    local tool="$1"; shift
    if _dry_run; then
        printf "  ${ORANGE}${BOLD}[dry-run]${RESET}  ${DIM}Would install: ${CYAN}%s${RESET}\n" "$tool" >&2
        return 0
    fi
    local rc=0; "$@" || rc=$?
    if [[ $rc -ne 0 ]]; then
        spinner_stop fail
        log_error "Failed to install $tool (exit $rc). See: $LOG_FILE"
        return $rc
    fi
}

_installed_ok() { _dry_run && return 0; spinner_stop ok; log_ok "$*"; }

# =============================================================================
# ══════════════════════════ DEVOPS & CONTAINERS ══════════════════════════════
# =============================================================================

install_git() {
    _already_installed git && { summary_skip "git"; return 0; }
    log_step "Installing Git..."
    spinner_start "Installing git"
    _do_install git _pkg_install git || { summary_fail "git"; return 1; }
    _installed_ok "Git → $(git --version 2>/dev/null)"
    summary_ok "git → $(git --version 2>/dev/null | awk '{print $3}')"
}

_install_docker_body() {
    case "$OS_FAMILY" in
        debian)
            $SUDO apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl gnupg lsb-release
            $SUDO mkdir -p /etc/apt/keyrings
            _curl_retry -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
                | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} $(lsb_release -cs) stable" \
                | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
            _wait_pkg_lock
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
                docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        rhel)
            $SUDO dnf remove -y docker docker-client docker-client-latest \
                docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
            $SUDO dnf install -y dnf-plugins-core
            $SUDO dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            $SUDO dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch) $SUDO pacman -S --noconfirm docker docker-compose ;;
        *)    log_warn "Docker install not supported on $OS_ID"; return 1 ;;
    esac
    _pkg_enable_service docker
    $SUDO usermod -aG docker "${SUDO_USER:-$USER}" 2>/dev/null || true
    log_info "Re-login or run: newgrp docker"
}

install_docker() {
    _already_installed docker && { summary_skip "docker"; return 0; }
    log_step "Installing Docker..."
    spinner_start "Installing Docker"
    _do_install docker _install_docker_body || { summary_fail "docker"; return 1; }
    _installed_ok "Docker → $(docker --version 2>/dev/null)"
    summary_ok "docker → $(docker --version 2>/dev/null | grep -oP '[\d.]+'| head -1)"
}

uninstall_docker() {
    log_step "Removing Docker..."
    spinner_start "Removing Docker"
    _do_install docker _pkg_remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker || true
    _installed_ok "Docker removed."
}

_install_kubectl_body() {
    local ver; ver="$(_curl_retry -fsSL https://dl.k8s.io/release/stable.txt)" \
        || { log_error "Cannot fetch kubectl version"; return 1; }
    local arch="${ARCH/x86_64/amd64}"; arch="${arch/aarch64/arm64}"
    _curl_retry -fsSL "https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubectl" -o /tmp/kubectl || return 1
    chmod +x /tmp/kubectl; $SUDO mv /tmp/kubectl /usr/local/bin/kubectl
}

install_kubectl() {
    _already_installed kubectl && { summary_skip "kubectl"; return 0; }
    log_step "Installing kubectl..."
    spinner_start "Installing kubectl"
    _do_install kubectl _install_kubectl_body || { summary_fail "kubectl"; return 1; }
    _installed_ok "kubectl → $(kubectl version --client 2>/dev/null | head -1)"
    summary_ok "kubectl"
}

uninstall_kubectl() { _do_install kubectl run_cmd $SUDO rm -f /usr/local/bin/kubectl; }

_install_helm_body() {
    _curl_retry -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm.sh || return 1
    chmod +x /tmp/get-helm.sh && DESIRED_VERSION="" /tmp/get-helm.sh
}

install_helm() {
    _already_installed helm && { summary_skip "helm"; return 0; }
    log_step "Installing Helm..."
    spinner_start "Installing Helm"
    _do_install helm _install_helm_body || { summary_fail "helm"; return 1; }
    _installed_ok "Helm → $(helm version --short 2>/dev/null)"
    summary_ok "helm → $(helm version --short 2>/dev/null)"
}

uninstall_helm() { _do_install helm run_cmd $SUDO rm -f /usr/local/bin/helm; }

_install_k9s_body() {
    local ver; ver="$(_curl_retry -fsSL https://api.github.com/repos/derailed/k9s/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)" || { log_error "Cannot fetch k9s version"; return 1; }
    local arch="${ARCH/x86_64/amd64}"; arch="${arch/aarch64/arm64}"
    _curl_retry -fsSL "https://github.com/derailed/k9s/releases/download/${ver}/k9s_Linux_${arch}.tar.gz" \
        -o /tmp/k9s.tar.gz || return 1
    tar -xzf /tmp/k9s.tar.gz -C /tmp k9s 2>/dev/null || tar -xzf /tmp/k9s.tar.gz -C /tmp
    $SUDO mv /tmp/k9s /usr/local/bin/k9s; rm -f /tmp/k9s.tar.gz
}

install_k9s() {
    _already_installed k9s && { summary_skip "k9s"; return 0; }
    log_step "Installing k9s (Kubernetes TUI)..."
    spinner_start "Installing k9s"
    _do_install k9s _install_k9s_body || { summary_fail "k9s"; return 1; }
    _installed_ok "k9s → $(k9s version --short 2>/dev/null | head -1)"
    summary_ok "k9s"
}

_install_minikube_body() {
    local arch="${ARCH/x86_64/amd64}"; arch="${arch/aarch64/arm64}"
    _curl_retry -fsSL "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${arch}" \
        -o /tmp/minikube || return 1
    $SUDO install -m 755 /tmp/minikube /usr/local/bin/minikube
}

install_minikube() {
    _already_installed minikube && { summary_skip "minikube"; return 0; }
    log_step "Installing minikube..."
    spinner_start "Installing minikube"
    _do_install minikube _install_minikube_body || { summary_fail "minikube"; return 1; }
    _installed_ok "minikube → $(minikube version 2>/dev/null | head -1)"
    summary_ok "minikube"
}

# =============================================================================
# ══════════════════════════ INFRASTRUCTURE AS CODE ═══════════════════════════
# =============================================================================

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
            $SUDO dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
            $SUDO dnf install -y terraform
            ;;
        arch)
            if command -v yay &>/dev/null; then yay -S --noconfirm terraform
            elif command -v paru &>/dev/null; then paru -S --noconfirm terraform
            else log_warn "AUR helper not found. Install terraform manually."; return 1; fi
            ;;
        *) log_warn "Terraform not supported on $OS_ID."; return 1 ;;
    esac
}

install_terraform() {
    _already_installed terraform && { summary_skip "terraform"; return 0; }
    log_step "Installing Terraform..."
    spinner_start "Installing Terraform"
    _do_install terraform _install_terraform_body || { summary_fail "terraform"; return 1; }
    _installed_ok "Terraform → $(terraform version 2>/dev/null | head -1)"
    summary_ok "terraform → $(terraform version 2>/dev/null | head -1 | grep -oP '[\d.]+')"
}

uninstall_terraform() { _do_install terraform _pkg_remove terraform; }

_install_ansible_body() {
    case "$PKG_MANAGER" in
        apt)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
            if command -v pipx &>/dev/null; then pipx install ansible-core
            else $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y ansible; fi
            ;;
        dnf|yum) $SUDO dnf install -y ansible ;;
        pacman)  $SUDO pacman -S --noconfirm ansible ;;
        zypper)  $SUDO zypper install -y ansible ;;
        brew)    brew install ansible ;;
    esac
}

install_ansible() {
    _already_installed ansible && { summary_skip "ansible"; return 0; }
    log_step "Installing Ansible..."
    spinner_start "Installing Ansible"
    _do_install ansible _install_ansible_body || { summary_fail "ansible"; return 1; }
    _installed_ok "Ansible → $(ansible --version 2>/dev/null | head -1)"
    summary_ok "ansible"
}

_install_vagrant_body() {
    case "$OS_FAMILY" in
        debian)
            wget -qO- https://apt.releases.hashicorp.com/gpg \
                | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg 2>/dev/null || true
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
                | $SUDO tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y vagrant
            ;;
        rhel)
            $SUDO dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo 2>/dev/null || true
            $SUDO dnf install -y vagrant
            ;;
        arch)  $SUDO pacman -S --noconfirm vagrant ;;
        *) log_warn "Vagrant not supported on $OS_ID."; return 1 ;;
    esac
}

install_vagrant() {
    _already_installed vagrant && { summary_skip "vagrant"; return 0; }
    log_step "Installing Vagrant..."
    spinner_start "Installing Vagrant"
    _do_install vagrant _install_vagrant_body || { summary_fail "vagrant"; return 1; }
    _installed_ok "Vagrant → $(vagrant --version 2>/dev/null)"
    summary_ok "vagrant"
}

# =============================================================================
# ══════════════════════════ CLOUD CLIs ═══════════════════════════════════════
# =============================================================================

_install_awscli_body() {
    local tmp; tmp="$(mktemp -d)"
    local url
    case "$ARCH" in
        x86_64)  url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
        aarch64) url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
        *) log_warn "AWS CLI unsupported on $ARCH"; rm -rf "$tmp"; return 1 ;;
    esac
    _curl_retry -fsSo "$tmp/awscliv2.zip" "$url" || { rm -rf "$tmp"; return 1; }
    unzip -q "$tmp/awscliv2.zip" -d "$tmp" || { rm -rf "$tmp"; return 1; }
    $SUDO "$tmp/aws/install" --update; rm -rf "$tmp"
}

install_awscli() {
    _already_installed aws && { summary_skip "awscli"; return 0; }
    log_step "Installing AWS CLI v2..."
    spinner_start "Installing AWS CLI"
    _do_install awscli _install_awscli_body || { summary_fail "awscli"; return 1; }
    _installed_ok "AWS CLI → $(aws --version 2>/dev/null)"
    summary_ok "awscli → $(aws --version 2>/dev/null | awk '{print $1}')"
}

_install_gcloud_body() {
    case "$OS_FAMILY" in
        debian)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates gnupg
            echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
https://packages.cloud.google.com/apt cloud-sdk main" \
                | $SUDO tee /etc/apt/sources.list.d/google-cloud-sdk.list
            _curl_retry -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
                | $SUDO gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y google-cloud-cli
            ;;
        rhel)
            $SUDO tee /etc/yum.repos.d/google-cloud-sdk.repo << 'EOF'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el8-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
            $SUDO dnf install -y google-cloud-cli
            ;;
        *) log_warn "gcloud not supported on $OS_ID."; return 1 ;;
    esac
}

install_gcloud() {
    _already_installed gcloud && { summary_skip "gcloud"; return 0; }
    log_step "Installing Google Cloud CLI..."
    spinner_start "Installing gcloud"
    _do_install gcloud _install_gcloud_body || { summary_fail "gcloud"; return 1; }
    _installed_ok "gcloud → $(gcloud --version 2>/dev/null | head -1)"
    summary_ok "gcloud"
}

_install_azure_body() {
    case "$OS_FAMILY" in
        debian)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl apt-transport-https gnupg lsb-release
            _curl_retry -fsSL https://packages.microsoft.com/keys/microsoft.asc \
                | $SUDO gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft.gpg] \
https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
                | $SUDO tee /etc/apt/sources.list.d/azure-cli.list
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y azure-cli
            ;;
        rhel)
            $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc
            $SUDO dnf install -y https://packages.microsoft.com/config/rhel/9/packages-microsoft-prod.rpm
            $SUDO dnf install -y azure-cli
            ;;
        *) log_warn "Azure CLI not supported on $OS_ID."; return 1 ;;
    esac
}

install_azure() {
    _already_installed az && { summary_skip "azure"; return 0; }
    log_step "Installing Azure CLI..."
    spinner_start "Installing Azure CLI"
    _do_install azure _install_azure_body || { summary_fail "azure"; return 1; }
    _installed_ok "Azure CLI → $(az --version 2>/dev/null | head -1)"
    summary_ok "azure-cli"
}

_install_gh_body() {
    case "$OS_FAMILY" in
        debian)
            _curl_retry -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
                | $SUDO tee /etc/apt/sources.list.d/github-cli.list
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y gh
            ;;
        rhel)
            $SUDO dnf install -y 'dnf-command(config-manager)'
            $SUDO dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
            $SUDO dnf install -y gh
            ;;
        arch) $SUDO pacman -S --noconfirm github-cli ;;
        *) log_warn "gh CLI not supported on $OS_ID."; return 1 ;;
    esac
}

install_gh() {
    _already_installed gh && { summary_skip "gh"; return 0; }
    log_step "Installing GitHub CLI..."
    spinner_start "Installing GitHub CLI"
    _do_install gh _install_gh_body || { summary_fail "gh"; return 1; }
    _installed_ok "GitHub CLI → $(gh --version 2>/dev/null | head -1)"
    summary_ok "gh → $(gh --version 2>/dev/null | head -1 | grep -oP '[\d.]+')"
}

# =============================================================================
# ══════════════════════════ WEB SERVERS ══════════════════════════════════════
# =============================================================================

install_nginx() {
    _already_installed nginx && { summary_skip "nginx"; return 0; }
    log_step "Installing Nginx..."
    spinner_start "Installing Nginx"
    _do_install nginx _pkg_install nginx || { summary_fail "nginx"; return 1; }
    _pkg_enable_service nginx
    _installed_ok "Nginx → $(nginx -v 2>&1)"
    summary_ok "nginx → $(nginx -v 2>&1 | grep -oP '[\d.]+')"
}

uninstall_nginx() { _do_install nginx _pkg_remove nginx; }

_install_apache_body() {
    case "$PKG_MANAGER" in
        apt)     $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y apache2; _pkg_enable_service apache2 ;;
        dnf|yum) $SUDO dnf install -y httpd; _pkg_enable_service httpd ;;
        pacman)  $SUDO pacman -S --noconfirm apache; _pkg_enable_service httpd ;;
        zypper)  $SUDO zypper install -y apache2; _pkg_enable_service apache2 ;;
        brew)    brew install httpd ;;
    esac
}

install_apache() {
    if command -v apache2 &>/dev/null || command -v httpd &>/dev/null; then
        log_skip "Apache already installed."; summary_skip "apache"; return 0
    fi
    log_step "Installing Apache..."
    spinner_start "Installing Apache"
    _do_install apache _install_apache_body || { summary_fail "apache"; return 1; }
    _installed_ok "Apache installed and service enabled."
    summary_ok "apache"
}

# =============================================================================
# ══════════════════════════ PHP ECOSYSTEM ════════════════════════════════════
# =============================================================================

_install_php_body() {
    case "$OS_FAMILY" in
        debian)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
            if command -v add-apt-repository &>/dev/null; then
                $SUDO add-apt-repository -y ppa:ondrej/php 2>/dev/null || true
            fi
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y \
                php php-cli php-common php-curl php-mbstring php-xml php-zip php-json php-mysql php-pgsql
            ;;
        rhel)
            $SUDO dnf install -y php php-cli php-common php-curl php-mbstring php-xml php-zip php-json php-mysqlnd
            ;;
        arch) $SUDO pacman -S --noconfirm php ;;
        *) log_warn "PHP not supported on $OS_ID."; return 1 ;;
    esac
}

install_php() {
    _already_installed php && { summary_skip "php"; return 0; }
    log_step "Installing PHP..."
    spinner_start "Installing PHP"
    _do_install php _install_php_body || { summary_fail "php"; return 1; }
    _installed_ok "PHP → $(php --version 2>/dev/null | head -1)"
    summary_ok "php → $(php --version 2>/dev/null | head -1 | grep -oP '[\d.]+'  | head -1)"
}

uninstall_php() { _do_install php _pkg_remove php; }

_install_phpfpm_body() {
    case "$OS_FAMILY" in
        debian)
            local v; v="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo '8.2')"
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "php${v}-fpm"
            _pkg_enable_service "php${v}-fpm"
            ;;
        rhel)   $SUDO dnf install -y php-fpm; _pkg_enable_service php-fpm ;;
        arch)   $SUDO pacman -S --noconfirm php-fpm; _pkg_enable_service php-fpm ;;
        *) log_warn "PHP-FPM not supported on $OS_ID."; return 1 ;;
    esac
}

install_phpfpm() {
    log_step "Installing PHP-FPM..."
    spinner_start "Installing PHP-FPM"
    if ! command -v php &>/dev/null; then
        log_warn "PHP not installed — installing it first..."; install_php || return 1
    fi
    _do_install phpfpm _install_phpfpm_body || { summary_fail "php-fpm"; return 1; }
    _installed_ok "PHP-FPM installed and service enabled."
    summary_ok "php-fpm"
}

_install_composer_body() {
    local tmp; tmp="$(mktemp)"
    _curl_retry -fsSL https://getcomposer.org/installer -o "$tmp" || { rm -f "$tmp"; return 1; }
    php "$tmp" --install-dir=/tmp --filename=composer || { rm -f "$tmp"; return 1; }
    $SUDO mv /tmp/composer /usr/local/bin/composer; rm -f "$tmp"
}

install_composer() {
    _already_installed composer && { summary_skip "composer"; return 0; }
    if ! command -v php &>/dev/null; then
        log_warn "PHP not installed — installing it first..."; install_php || return 1
    fi
    log_step "Installing Composer..."
    spinner_start "Installing Composer"
    _do_install composer _install_composer_body || { summary_fail "composer"; return 1; }
    _installed_ok "Composer → $(composer --version 2>/dev/null)"
    summary_ok "composer"
}

# =============================================================================
# ══════════════════════════ DATABASES ════════════════════════════════════════
# =============================================================================

_install_mysql_body() {
    case "$PKG_MANAGER" in
        apt)     $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server; _pkg_enable_service mysql ;;
        dnf|yum) $SUDO dnf install -y mysql-server; _pkg_enable_service mysqld ;;
        pacman)
            $SUDO pacman -S --noconfirm mariadb
            $SUDO mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql 2>/dev/null || true
            _pkg_enable_service mariadb
            ;;
        *) log_warn "MySQL not supported on $OS_ID."; return 1 ;;
    esac
}

install_mysql() {
    if command -v mysql &>/dev/null || command -v mysqld &>/dev/null; then
        log_skip "MySQL/MariaDB already installed."; summary_skip "mysql"; return 0
    fi
    log_step "Installing MySQL..."
    spinner_start "Installing MySQL"
    _do_install mysql _install_mysql_body || { summary_fail "mysql"; return 1; }
    _installed_ok "MySQL installed. Run: sudo mysql_secure_installation"
    summary_ok "mysql"
}

_install_postgresql_body() {
    case "$PKG_MANAGER" in
        apt)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib
            _pkg_enable_service postgresql
            ;;
        dnf|yum)
            $SUDO dnf install -y postgresql-server postgresql-contrib
            $SUDO postgresql-setup --initdb 2>/dev/null || true; _pkg_enable_service postgresql
            ;;
        pacman)
            $SUDO pacman -S --noconfirm postgresql
            $SUDO -u postgres initdb -D /var/lib/postgres/data 2>/dev/null || true
            _pkg_enable_service postgresql
            ;;
        *) log_warn "PostgreSQL not supported on $OS_ID."; return 1 ;;
    esac
}

install_postgresql() {
    _already_installed psql && { summary_skip "postgresql"; return 0; }
    log_step "Installing PostgreSQL..."
    spinner_start "Installing PostgreSQL"
    _do_install postgresql _install_postgresql_body || { summary_fail "postgresql"; return 1; }
    _installed_ok "PostgreSQL → $(psql --version 2>/dev/null)"
    summary_ok "postgresql → $(psql --version 2>/dev/null | grep -oP '[\d.]+')"
}

_install_redis_body() {
    case "$PKG_MANAGER" in
        apt)     $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server; _pkg_enable_service redis-server ;;
        dnf|yum) $SUDO dnf install -y redis; _pkg_enable_service redis ;;
        pacman)  $SUDO pacman -S --noconfirm redis; _pkg_enable_service redis ;;
        zypper)  $SUDO zypper install -y redis; _pkg_enable_service redis ;;
        brew)    brew install redis && brew services start redis ;;
    esac
}

install_redis() {
    if command -v redis-server &>/dev/null || command -v redis-cli &>/dev/null; then
        log_skip "Redis already installed."; summary_skip "redis"; return 0
    fi
    log_step "Installing Redis..."
    spinner_start "Installing Redis"
    _do_install redis _install_redis_body || { summary_fail "redis"; return 1; }
    _installed_ok "Redis → $(redis-server --version 2>/dev/null)"
    summary_ok "redis"
}

_install_mongodb_body() {
    case "$OS_FAMILY" in
        debian)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg curl
            _curl_retry -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
                | $SUDO gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
            local codename; codename="$(lsb_release -cs)"
            echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/7.0 multiverse" \
                | $SUDO tee /etc/apt/sources.list.d/mongodb-org-7.0.list
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get update -qq || true
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-org
            _pkg_enable_service mongod
            ;;
        rhel)
            $SUDO tee /etc/yum.repos.d/mongodb-org-7.0.repo << 'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-7.0.asc
EOF
            $SUDO dnf install -y mongodb-org; _pkg_enable_service mongod
            ;;
        *) log_warn "MongoDB not supported on $OS_ID."; return 1 ;;
    esac
}

install_mongodb() {
    if command -v mongod &>/dev/null || command -v mongosh &>/dev/null; then
        log_skip "MongoDB already installed."; summary_skip "mongodb"; return 0
    fi
    log_step "Installing MongoDB..."
    spinner_start "Installing MongoDB"
    _do_install mongodb _install_mongodb_body || { summary_fail "mongodb"; return 1; }
    _installed_ok "MongoDB installed."
    summary_ok "mongodb"
}

# =============================================================================
# ══════════════════════════ LANGUAGES & RUNTIMES ═════════════════════════════
# =============================================================================

_install_nvm_body() {
    local ver; ver="$(_curl_retry -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)" || { log_error "Cannot fetch nvm version"; return 1; }
    _curl_retry -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${ver}/install.sh" | bash
}

install_nvm() {
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$nvm_dir/nvm.sh" ]]; then
        log_skip "nvm already installed at $nvm_dir."; summary_skip "nvm"; return 0
    fi
    log_step "Installing nvm (Node Version Manager)..."
    spinner_start "Installing nvm"
    _do_install nvm _install_nvm_body || { summary_fail "nvm"; return 1; }
    spinner_stop ok; log_ok "nvm installed."
    export NVM_DIR="$nvm_dir"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    log_step "Installing Node.js LTS..."
    nvm install --lts && nvm use --lts \
        || log_warn "Node LTS setup failed. Run: nvm install --lts"
    log_ok "Node.js → $(node --version 2>/dev/null || echo 'restart terminal')"
    summary_ok "nvm + node LTS"
}

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
    if _already_installed python3 && _already_installed pip3; then
        summary_skip "python"; return 0
    fi
    log_step "Installing Python 3 & pip..."
    spinner_start "Installing Python"
    _do_install python _install_python_body || { summary_fail "python"; return 1; }
    _installed_ok "Python → $(python3 --version 2>/dev/null)"
    summary_ok "python → $(python3 --version 2>/dev/null | grep -oP '[\d.]+')"
}

_install_golang_body() {
    local ver; ver="$(_curl_retry -fsSL 'https://go.dev/VERSION?m=text' | head -1)" || ver="go1.22.0"
    local arch="${ARCH/x86_64/amd64}"; arch="${arch/aarch64/arm64}"
    _curl_retry -fsSL "https://go.dev/dl/${ver}.linux-${arch}.tar.gz" -o /tmp/go.tar.gz || return 1
    $SUDO rm -rf /usr/local/go
    $SUDO tar -C /usr/local -xzf /tmp/go.tar.gz; rm -f /tmp/go.tar.gz
    local profile="$HOME/.bashrc"
    [[ -n "${ZSH_VERSION:-}" ]] && profile="$HOME/.zshrc"
    grep -q '/usr/local/go/bin' "$profile" 2>/dev/null \
        || echo 'export PATH=$PATH:/usr/local/go/bin' >> "$profile"
    export PATH="$PATH:/usr/local/go/bin"
}

install_golang() {
    _already_installed go && { summary_skip "golang"; return 0; }
    log_step "Installing Go..."
    spinner_start "Installing Go"
    _do_install golang _install_golang_body || { summary_fail "golang"; return 1; }
    _installed_ok "Go → $(/usr/local/go/bin/go version 2>/dev/null)"
    summary_ok "golang → $(/usr/local/go/bin/go version 2>/dev/null | grep -oP '[\d.]+')"
}

_install_rust_body() {
    _curl_retry -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path || return 1
    # shellcheck source=/dev/null
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
}

install_rust() {
    if _already_installed rustc || [[ -f "$HOME/.cargo/bin/rustc" ]]; then
        log_skip "Rust already installed."; summary_skip "rust"; return 0
    fi
    log_step "Installing Rust (via rustup)..."
    spinner_start "Installing Rust"
    _do_install rust _install_rust_body || { summary_fail "rust"; return 1; }
    spinner_stop ok
    source "$HOME/.cargo/env" 2>/dev/null || true
    log_ok "Rust → $(rustc --version 2>/dev/null)"
    summary_ok "rust → $(rustc --version 2>/dev/null | grep -oP '[\d.]+')"
}

# =============================================================================
# ══════════════════════════ CLI UTILITIES ════════════════════════════════════
# =============================================================================

install_fzf() {
    _already_installed fzf && { summary_skip "fzf"; return 0; }
    log_step "Installing fzf..."; spinner_start "Installing fzf"
    _do_install fzf _pkg_install fzf || { summary_fail "fzf"; return 1; }
    _installed_ok "fzf → $(fzf --version 2>/dev/null)"; summary_ok "fzf"
}

install_bat() {
    _already_installed bat && { summary_skip "bat"; return 0; }
    log_step "Installing bat..."; spinner_start "Installing bat"
    _do_install bat _pkg_install bat || { summary_fail "bat"; return 1; }
    _installed_ok "bat → $(bat --version 2>/dev/null)"; summary_ok "bat"
}

install_eza() {
    _already_installed eza && { summary_skip "eza"; return 0; }
    log_step "Installing eza..."; spinner_start "Installing eza"
    _do_install eza _pkg_install eza 2>/dev/null || {
        if command -v cargo &>/dev/null; then
            _do_install eza cargo install eza || { summary_fail "eza"; return 1; }
        else
            log_warn "eza not in repos. Install Rust first, then: cargo install eza"
            spinner_stop skip; summary_skip "eza (needs rust)"; return 1
        fi
    }
    _installed_ok "eza → $(eza --version 2>/dev/null | head -1)"; summary_ok "eza"
}

install_ripgrep() {
    _already_installed rg && { summary_skip "ripgrep"; return 0; }
    log_step "Installing ripgrep..."; spinner_start "Installing ripgrep"
    _do_install ripgrep _pkg_install ripgrep || { summary_fail "ripgrep"; return 1; }
    _installed_ok "ripgrep → $(rg --version 2>/dev/null | head -1)"; summary_ok "ripgrep"
}

install_jq() {
    _already_installed jq && { summary_skip "jq"; return 0; }
    log_step "Installing jq..."; spinner_start "Installing jq"
    _do_install jq _pkg_install jq || { summary_fail "jq"; return 1; }
    _installed_ok "jq → $(jq --version 2>/dev/null)"; summary_ok "jq"
}

install_yq() {
    _already_installed yq && { summary_skip "yq"; return 0; }
    log_step "Installing yq..."; spinner_start "Installing yq"
    local ver; ver="$(_curl_retry -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 2>/dev/null || echo 'v4.40.5')"
    _do_install yq bash -c "
        curl -fsSL 'https://github.com/mikefarah/yq/releases/download/${ver}/yq_linux_amd64' -o /tmp/yq \
        && chmod +x /tmp/yq \
        && $SUDO mv /tmp/yq /usr/local/bin/yq
    " || { summary_fail "yq"; return 1; }
    _installed_ok "yq → $(yq --version 2>/dev/null)"; summary_ok "yq"
}

install_httpie() {
    _already_installed http && { summary_skip "httpie"; return 0; }
    log_step "Installing HTTPie..."; spinner_start "Installing HTTPie"
    _do_install httpie _pkg_install httpie || { summary_fail "httpie"; return 1; }
    _installed_ok "HTTPie → $(http --version 2>/dev/null)"; summary_ok "httpie"
}

install_tmux() {
    _already_installed tmux && { summary_skip "tmux"; return 0; }
    log_step "Installing tmux..."; spinner_start "Installing tmux"
    _do_install tmux _pkg_install tmux || { summary_fail "tmux"; return 1; }
    _installed_ok "tmux → $(tmux -V 2>/dev/null)"; summary_ok "tmux"
}

install_neovim() {
    _already_installed nvim && { summary_skip "neovim"; return 0; }
    log_step "Installing Neovim..."; spinner_start "Installing Neovim"
    _do_install neovim _pkg_install neovim || { summary_fail "neovim"; return 1; }
    _installed_ok "Neovim → $(nvim --version 2>/dev/null | head -1)"; summary_ok "neovim"
}

install_btop() {
    _already_installed btop && { summary_skip "btop"; return 0; }
    log_step "Installing btop..."; spinner_start "Installing btop"
    _do_install btop _pkg_install btop || { summary_fail "btop"; return 1; }
    _installed_ok "btop → $(btop --version 2>/dev/null | head -1)"; summary_ok "btop"
}

# =============================================================================
# ══════════════════════════ STATUS & UNINSTALL ═══════════════════════════════
# =============================================================================

# Print version info for all known tools
show_status() {
    _load_tools_conf 2>/dev/null || true
    local cols; cols="$(tput cols 2>/dev/null || echo 80)"
    local w=$(( cols < 64 ? cols - 4 : 60 ))
    local line; line="$(printf '─%.0s' $(seq 1 $w))"

    echo -e "" >&2
    echo -e "${INDIGO}  ╭${line}╮${RESET}" >&2
    printf "${INDIGO}  │${RESET}%*s${BWHITE}${BOLD} Installed Tool Versions ${RESET}%*s${INDIGO}│${RESET}\n" \
        "$(( (w - 26) / 2 ))" "" "$(( (w - 26) / 2 ))" "" >&2
    echo -e "${INDIGO}  ├${line}┤${RESET}" >&2

    local -A VERSIONS=(
        [git]="$(git --version 2>/dev/null | awk '{print $3}')"
        [docker]="$(docker --version 2>/dev/null | awk -F'[ ,]+' '{print $3}')"
        [kubectl]="$(kubectl version --client 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
        [helm]="$(helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')"
        [k9s]="$(k9s version --short 2>/dev/null | head -1)"
        [minikube]="$(minikube version --short 2>/dev/null)"
        [terraform]="$(terraform version 2>/dev/null | head -1 | awk '{print $2}')"
        [ansible]="$(ansible --version 2>/dev/null | head -1 | awk '{print $NF}' | tr -d ']')"
        [aws]="$(aws --version 2>/dev/null | awk '{print $1}')"
        [gcloud]="$(gcloud --version 2>/dev/null | head -1)"
        [az]="$(az --version 2>/dev/null | head -1 | awk '{print $1, $2}')"
        [gh]="$(gh --version 2>/dev/null | head -1 | awk '{print $3}')"
        [nginx]="$(nginx -v 2>&1 | awk -F'/' '{print $2}')"
        [php]="$(php --version 2>/dev/null | head -1 | awk '{print $2}')"
        [composer]="$(composer --version 2>/dev/null | awk '{print $3}')"
        [mysql]="$(mysql --version 2>/dev/null | awk '{print $5}' | tr -d ',')"
        [psql]="$(psql --version 2>/dev/null | awk '{print $3}')"
        [redis-cli]="$(redis-cli --version 2>/dev/null | awk '{print $2}')"
        [node]="$(node --version 2>/dev/null)"
        [python3]="$(python3 --version 2>/dev/null | awk '{print $2}')"
        [go]="$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}' || go version 2>/dev/null | awk '{print $3}')"
        [rustc]="$(rustc --version 2>/dev/null | awk '{print $2}')"
        [fzf]="$(fzf --version 2>/dev/null | awk '{print $1}')"
        [bat]="$(bat --version 2>/dev/null | awk '{print $2}')"
        [rg]="$(rg --version 2>/dev/null | head -1 | awk '{print $2}')"
        [jq]="$(jq --version 2>/dev/null)"
        [nvim]="$(nvim --version 2>/dev/null | head -1 | awk '{print $2}')"
        [tmux]="$(tmux -V 2>/dev/null | awk '{print $2}')"
        [btop]="$(btop --version 2>/dev/null | awk '{print $2}')"
    )

    local -a sorted_cmds=()
    IFS=$'\n' read -ra sorted_cmds <<< "$(printf '%s\n' "${!VERSIONS[@]}" | sort)"

    for cmd in "${sorted_cmds[@]}"; do
        local ver="${VERSIONS[$cmd]}"
        if command -v "$cmd" &>/dev/null && [[ -n "$ver" ]]; then
            printf "${INDIGO}  │${RESET}  ${BGREEN}${ICON_OK}${RESET}  ${GREEN}%-16s${RESET}  ${DIM}%s${RESET}\n" \
                "$cmd" "$ver" >&2
        elif command -v "$cmd" &>/dev/null; then
            printf "${INDIGO}  │${RESET}  ${BGREEN}${ICON_OK}${RESET}  ${GREEN}%-16s${RESET}  ${DIM}(version unknown)${RESET}\n" \
                "$cmd" >&2
        fi
    done

    echo -e "${INDIGO}  ╰${line}╯${RESET}" >&2
    echo -e "" >&2
}

# ── Dispatcher ────────────────────────────────────────────────────────────────
install_tool() {
    local tool="${1,,}"
    local fn="install_${tool}"
    if declare -f "$fn" > /dev/null; then "$fn"
    else
        log_error "No installer for: ${BOLD}$tool${RESET}"
        log_info  "Run 'devsetup --list' to see all available tools."
        summary_fail "$tool (unknown)"
        return 1
    fi
}

uninstall_tool() {
    local tool="${1,,}"
    local fn="uninstall_${tool}"
    if declare -f "$fn" > /dev/null; then "$fn"
    else
        # Generic fallback: try package manager remove
        log_warn "No specific uninstall for '$tool'. Trying package manager..."
        _do_install "$tool" _pkg_remove "$tool" || return 1
    fi
}

list_tools() {
    declare -F | awk '{print $3}' | grep '^install_' | sed 's/^install_//' | sort
}
