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
        *)      log_error "Unknown package manager: $PKG_MANAGER"; return 1 ;;
    esac
}

_pkg_update() {
    log_step "Refreshing package index..."
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
    local svc="$1"
    if command -v systemctl &>/dev/null; then
        $SUDO systemctl enable --now "$svc" 2>/dev/null || true
    fi
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

_do_install() {
    local tool="$1"; shift
    if _dry_run; then
        printf "  ${ORANGE}${BOLD}[dry-run]${RESET}  ${DIM}Would install: ${CYAN}%s${RESET}\n" "$tool" >&2
        return 0
    fi
    local exit_code=0
    "$@" || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        spinner_stop fail
        log_error "Failed to install $tool (exit $exit_code). Check logs above."
        return $exit_code
    fi
}

_installed_ok() {
    _dry_run && return 0
    spinner_stop ok
    log_ok "$*"
}

# =============================================================================
# ══════════════════════════ DEVOPS & CONTAINERS ══════════════════════════════
# =============================================================================

install_git() {
    _already_installed git && return 0
    log_step "Installing Git..."
    spinner_start "Installing git"
    _do_install git _pkg_install git || return 1
    _installed_ok "Git → $(git --version 2>/dev/null)"
}

# ─ Docker ─────────────────────────────────────────────────────────────────────
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
            $SUDO dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            $SUDO dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        arch)
            $SUDO pacman -S --noconfirm docker docker-compose
            ;;
        *)
            log_warn "Docker install not supported on $OS_ID. See: https://docs.docker.com/engine/install/"
            return 1
            ;;
    esac
    _pkg_enable_service docker
    $SUDO usermod -aG docker "${SUDO_USER:-$USER}" 2>/dev/null || true
    log_info "Re-login or run: newgrp docker"
}

install_docker() {
    _already_installed docker && return 0
    log_step "Installing Docker..."
    spinner_start "Installing Docker"
    _do_install docker _install_docker_body || return 1
    _installed_ok "Docker → $(docker --version 2>/dev/null)"
}

# ─ kubectl ────────────────────────────────────────────────────────────────────
_install_kubectl_body() {
    local ver; ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)" \
        || { log_error "Cannot fetch kubectl version"; return 1; }
    local arch="${ARCH/x86_64/amd64}"; arch="${arch/aarch64/arm64}"
    curl -fsSL "https://dl.k8s.io/release/${ver}/bin/linux/${arch}/kubectl" -o /tmp/kubectl || return 1
    chmod +x /tmp/kubectl
    $SUDO mv /tmp/kubectl /usr/local/bin/kubectl
}

install_kubectl() {
    _already_installed kubectl && return 0
    log_step "Installing kubectl..."
    spinner_start "Installing kubectl"
    _do_install kubectl _install_kubectl_body || return 1
    _installed_ok "kubectl → $(kubectl version --client 2>/dev/null | head -1)"
}

# ─ Helm ───────────────────────────────────────────────────────────────────────
_install_helm_body() {
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm.sh || return 1
    chmod +x /tmp/get-helm.sh && DESIRED_VERSION="" /tmp/get-helm.sh
}

install_helm() {
    _already_installed helm && return 0
    log_step "Installing Helm..."
    spinner_start "Installing Helm"
    _do_install helm _install_helm_body || return 1
    _installed_ok "Helm → $(helm version --short 2>/dev/null)"
}

# ─ k9s ────────────────────────────────────────────────────────────────────────
_install_k9s_body() {
    local ver; ver="$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)" || { log_error "Cannot fetch k9s version"; return 1; }
    local arch="${ARCH/x86_64/amd64}"; arch="${arch/aarch64/arm64}"
    curl -fsSL "https://github.com/derailed/k9s/releases/download/${ver}/k9s_Linux_${arch}.tar.gz" \
        -o /tmp/k9s.tar.gz || return 1
    tar -xzf /tmp/k9s.tar.gz -C /tmp k9s
    $SUDO mv /tmp/k9s /usr/local/bin/k9s
    rm -f /tmp/k9s.tar.gz
}

install_k9s() {
    _already_installed k9s && return 0
    log_step "Installing k9s (Kubernetes TUI)..."
    spinner_start "Installing k9s"
    _do_install k9s _install_k9s_body || return 1
    _installed_ok "k9s → $(k9s version --short 2>/dev/null | head -1)"
}

# ─ minikube ───────────────────────────────────────────────────────────────────
_install_minikube_body() {
    local arch="${ARCH/x86_64/amd64}"; arch="${arch/aarch64/arm64}"
    curl -fsSL "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${arch}" \
        -o /tmp/minikube || return 1
    $SUDO install -m 755 /tmp/minikube /usr/local/bin/minikube
}

install_minikube() {
    _already_installed minikube && return 0
    log_step "Installing minikube..."
    spinner_start "Installing minikube"
    _do_install minikube _install_minikube_body || return 1
    _installed_ok "minikube → $(minikube version 2>/dev/null | head -1)"
}

# =============================================================================
# ══════════════════════════ INFRASTRUCTURE AS CODE ═══════════════════════════
# =============================================================================

# ─ Terraform ──────────────────────────────────────────────────────────────────
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
            else log_warn "AUR helper (yay/paru) not found. Install terraform manually."; return 1
            fi
            ;;
        *) log_warn "Terraform not supported on $OS_ID."; return 1 ;;
    esac
}

install_terraform() {
    _already_installed terraform && return 0
    log_step "Installing Terraform..."
    spinner_start "Installing Terraform"
    _do_install terraform _install_terraform_body || return 1
    _installed_ok "Terraform → $(terraform version 2>/dev/null | head -1)"
}

# ─ Ansible ────────────────────────────────────────────────────────────────────
_install_ansible_body() {
    case "$PKG_MANAGER" in
        apt)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common
            # Use pipx if available for latest version, otherwise apt
            if command -v pipx &>/dev/null; then
                pipx install ansible-core
            else
                $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y ansible
            fi
            ;;
        dnf|yum) $SUDO dnf install -y ansible ;;
        pacman)  $SUDO pacman -S --noconfirm ansible ;;
        zypper)  $SUDO zypper install -y ansible ;;
        brew)    brew install ansible ;;
    esac
}

install_ansible() {
    _already_installed ansible && return 0
    log_step "Installing Ansible..."
    spinner_start "Installing Ansible"
    _do_install ansible _install_ansible_body || return 1
    _installed_ok "Ansible → $(ansible --version 2>/dev/null | head -1)"
}

# ─ Vagrant ────────────────────────────────────────────────────────────────────
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
    _already_installed vagrant && return 0
    log_step "Installing Vagrant..."
    spinner_start "Installing Vagrant"
    _do_install vagrant _install_vagrant_body || return 1
    _installed_ok "Vagrant → $(vagrant --version 2>/dev/null)"
}

# =============================================================================
# ══════════════════════════ CLOUD CLIs ═══════════════════════════════════════
# =============================================================================

# ─ AWS CLI ────────────────────────────────────────────────────────────────────
_install_awscli_body() {
    local tmp_dir; tmp_dir="$(mktemp -d)"
    local url
    case "$ARCH" in
        x86_64)  url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
        aarch64) url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
        *) log_warn "AWS CLI unsupported on $ARCH"; rm -rf "$tmp_dir"; return 1 ;;
    esac
    curl -fsSo "$tmp_dir/awscliv2.zip" "$url" || { rm -rf "$tmp_dir"; return 1; }
    unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir" || { rm -rf "$tmp_dir"; return 1; }
    $SUDO "$tmp_dir/aws/install"
    rm -rf "$tmp_dir"
}

install_awscli() {
    _already_installed aws && return 0
    log_step "Installing AWS CLI v2..."
    spinner_start "Installing AWS CLI"
    _do_install awscli _install_awscli_body || return 1
    _installed_ok "AWS CLI → $(aws --version 2>/dev/null)"
}

# ─ Google Cloud CLI ───────────────────────────────────────────────────────────
_install_gcloud_body() {
    case "$OS_FAMILY" in
        debian)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates gnupg
            echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
https://packages.cloud.google.com/apt cloud-sdk main" \
                | $SUDO tee /etc/apt/sources.list.d/google-cloud-sdk.list
            curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
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
        arch)
            if command -v yay &>/dev/null; then yay -S --noconfirm google-cloud-cli
            else log_warn "Install google-cloud-cli from AUR manually."; return 1
            fi
            ;;
        *) log_warn "gcloud not supported on $OS_ID."; return 1 ;;
    esac
}

install_gcloud() {
    _already_installed gcloud && return 0
    log_step "Installing Google Cloud CLI..."
    spinner_start "Installing gcloud"
    _do_install gcloud _install_gcloud_body || return 1
    _installed_ok "gcloud → $(gcloud --version 2>/dev/null | head -1)"
}

# ─ Azure CLI ──────────────────────────────────────────────────────────────────
_install_azure_body() {
    case "$OS_FAMILY" in
        debian)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl apt-transport-https gnupg lsb-release
            curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
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
        arch)
            if command -v yay &>/dev/null; then yay -S --noconfirm azure-cli
            else log_warn "Install azure-cli from AUR manually."; return 1
            fi
            ;;
        *) log_warn "Azure CLI not supported on $OS_ID."; return 1 ;;
    esac
}

install_azure() {
    _already_installed az && return 0
    log_step "Installing Azure CLI..."
    spinner_start "Installing Azure CLI"
    _do_install azure _install_azure_body || return 1
    _installed_ok "Azure CLI → $(az --version 2>/dev/null | head -1)"
}

# ─ GitHub CLI ─────────────────────────────────────────────────────────────────
_install_gh_body() {
    case "$OS_FAMILY" in
        debian)
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
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
        arch)  $SUDO pacman -S --noconfirm github-cli ;;
        brew)  brew install gh ;;
        *) log_warn "gh CLI not supported on $OS_ID."; return 1 ;;
    esac
}

install_gh() {
    _already_installed gh && return 0
    log_step "Installing GitHub CLI..."
    spinner_start "Installing GitHub CLI"
    _do_install gh _install_gh_body || return 1
    _installed_ok "GitHub CLI → $(gh --version 2>/dev/null | head -1)"
}

# =============================================================================
# ══════════════════════════ WEB SERVERS ══════════════════════════════════════
# =============================================================================

install_nginx() {
    _already_installed nginx && return 0
    log_step "Installing Nginx..."
    spinner_start "Installing Nginx"
    _do_install nginx _pkg_install nginx || return 1
    _pkg_enable_service nginx
    _installed_ok "Nginx → $(nginx -v 2>&1)"
}

_install_apache_body() {
    case "$PKG_MANAGER" in
        apt)    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 ;;
        dnf|yum) $SUDO dnf install -y httpd ;;
        pacman) $SUDO pacman -S --noconfirm apache ;;
        zypper) $SUDO zypper install -y apache2 ;;
        brew)   brew install httpd ;;
    esac
    case "$PKG_MANAGER" in
        apt)    _pkg_enable_service apache2 ;;
        dnf|yum) _pkg_enable_service httpd ;;
    esac
}

install_apache() {
    if command -v apache2 &>/dev/null || command -v httpd &>/dev/null; then
        log_skip "Apache already installed. Skipping."; return 0
    fi
    log_step "Installing Apache..."
    spinner_start "Installing Apache"
    _do_install apache _install_apache_body || return 1
    _installed_ok "Apache installed and service enabled."
}

# =============================================================================
# ══════════════════════════ PHP ECOSYSTEM ════════════════════════════════════
# =============================================================================

_install_php_body() {
    case "$OS_FAMILY" in
        debian)
            # Use ondrej/php PPA for latest versions on Ubuntu/Debian
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
        arch)  $SUDO pacman -S --noconfirm php php-fpm ;;
        *) log_warn "PHP install not fully supported on $OS_ID."; return 1 ;;
    esac
}

install_php() {
    _already_installed php && return 0
    log_step "Installing PHP..."
    spinner_start "Installing PHP"
    _do_install php _install_php_body || return 1
    _installed_ok "PHP → $(php --version 2>/dev/null | head -1)"
}

_install_phpfpm_body() {
    case "$OS_FAMILY" in
        debian)
            # Detect installed PHP version to install matching fpm
            local php_ver; php_ver="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo '8.2')"
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "php${php_ver}-fpm"
            _pkg_enable_service "php${php_ver}-fpm"
            ;;
        rhel)
            $SUDO dnf install -y php-fpm
            _pkg_enable_service php-fpm
            ;;
        arch)
            $SUDO pacman -S --noconfirm php-fpm
            _pkg_enable_service php-fpm
            ;;
        *) log_warn "PHP-FPM not supported on $OS_ID."; return 1 ;;
    esac
}

install_phpfpm() {
    log_step "Installing PHP-FPM..."
    spinner_start "Installing PHP-FPM"
    _do_install phpfpm _install_phpfpm_body || return 1
    _installed_ok "PHP-FPM installed and service enabled."
}

_install_composer_body() {
    local tmp; tmp="$(mktemp)"
    curl -fsSL https://getcomposer.org/installer -o "$tmp" || { rm -f "$tmp"; return 1; }
    php "$tmp" --install-dir=/tmp --filename=composer || { rm -f "$tmp"; return 1; }
    $SUDO mv /tmp/composer /usr/local/bin/composer
    rm -f "$tmp"
}

install_composer() {
    _already_installed composer && return 0
    if ! command -v php &>/dev/null; then
        log_warn "PHP is not installed. Installing PHP first..."
        install_php || return 1
    fi
    log_step "Installing Composer..."
    spinner_start "Installing Composer"
    _do_install composer _install_composer_body || return 1
    _installed_ok "Composer → $(composer --version 2>/dev/null)"
}

# =============================================================================
# ══════════════════════════ DATABASES ════════════════════════════════════════
# =============================================================================

_install_mysql_body() {
    case "$PKG_MANAGER" in
        apt)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
            _pkg_enable_service mysql
            ;;
        dnf|yum)
            $SUDO dnf install -y mysql-server
            _pkg_enable_service mysqld
            ;;
        pacman)
            $SUDO pacman -S --noconfirm mariadb
            $SUDO mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql 2>/dev/null || true
            _pkg_enable_service mariadb
            ;;
        *) log_warn "MySQL not supported on $OS_ID."; return 1 ;;
    esac
}

install_mysql() {
    if command -v mysql &>/dev/null || command -v mysqld &>/dev/null || command -v mariadbd &>/dev/null; then
        log_skip "MySQL/MariaDB already installed. Skipping."; return 0
    fi
    log_step "Installing MySQL..."
    spinner_start "Installing MySQL"
    _do_install mysql _install_mysql_body || return 1
    _installed_ok "MySQL installed and service enabled."
    log_info "Run: sudo mysql_secure_installation"
}

_install_postgresql_body() {
    case "$PKG_MANAGER" in
        apt)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib
            _pkg_enable_service postgresql
            ;;
        dnf|yum)
            $SUDO dnf install -y postgresql-server postgresql-contrib
            $SUDO postgresql-setup --initdb 2>/dev/null || true
            _pkg_enable_service postgresql
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
    _already_installed psql && return 0
    log_step "Installing PostgreSQL..."
    spinner_start "Installing PostgreSQL"
    _do_install postgresql _install_postgresql_body || return 1
    _installed_ok "PostgreSQL → $(psql --version 2>/dev/null)"
}

_install_redis_body() {
    case "$PKG_MANAGER" in
        apt)    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server; _pkg_enable_service redis-server ;;
        dnf|yum) $SUDO dnf install -y redis; _pkg_enable_service redis ;;
        pacman) $SUDO pacman -S --noconfirm redis; _pkg_enable_service redis ;;
        zypper) $SUDO zypper install -y redis; _pkg_enable_service redis ;;
        brew)   brew install redis && brew services start redis ;;
    esac
}

install_redis() {
    _already_installed redis-server || _already_installed redis-cli && {
        log_skip "Redis already installed. Skipping."; return 0
    }
    log_step "Installing Redis..."
    spinner_start "Installing Redis"
    _do_install redis _install_redis_body || return 1
    _installed_ok "Redis → $(redis-server --version 2>/dev/null)"
}

_install_mongodb_body() {
    case "$OS_FAMILY" in
        debian)
            $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg curl
            curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
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
            $SUDO dnf install -y mongodb-org
            _pkg_enable_service mongod
            ;;
        arch)
            if command -v yay &>/dev/null; then yay -S --noconfirm mongodb-bin
            else log_warn "Install mongodb-bin from AUR manually."; return 1
            fi
            ;;
        *) log_warn "MongoDB not supported on $OS_ID."; return 1 ;;
    esac
}

install_mongodb() {
    _already_installed mongod || _already_installed mongosh && {
        log_skip "MongoDB already installed. Skipping."; return 0
    }
    log_step "Installing MongoDB..."
    spinner_start "Installing MongoDB"
    _do_install mongodb _install_mongodb_body || return 1
    _installed_ok "MongoDB installed and service enabled."
}

# =============================================================================
# ══════════════════════════ LANGUAGES & RUNTIMES ═════════════════════════════
# =============================================================================

# ─ nvm / Node.js ──────────────────────────────────────────────────────────────
_install_nvm_body() {
    local ver; ver="$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)" \
        || { log_error "Cannot fetch nvm version"; return 1; }
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${ver}/install.sh" | bash
}

install_nvm() {
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [[ -s "$nvm_dir/nvm.sh" ]]; then
        log_skip "nvm already installed at $nvm_dir. Skipping."; return 0
    fi
    log_step "Installing nvm (Node Version Manager)..."
    spinner_start "Installing nvm"
    _do_install nvm _install_nvm_body || return 1
    spinner_stop ok
    log_ok "nvm installed."
    export NVM_DIR="$nvm_dir"
    # shellcheck source=/dev/null
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    log_step "Installing Node.js LTS..."
    nvm install --lts && nvm use --lts \
        || log_warn "Node LTS setup failed. Run: nvm install --lts"
    log_ok "Node.js → $(node --version 2>/dev/null || echo 'restart terminal first')"
}

# ─ Python / pip ───────────────────────────────────────────────────────────────
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
    log_step "Installing Python 3 & pip..."
    spinner_start "Installing Python"
    _do_install python _install_python_body || return 1
    _installed_ok "Python → $(python3 --version 2>/dev/null)  |  pip → $(pip3 --version 2>/dev/null | awk '{print $1,$2}')"
}

# ─ Go ─────────────────────────────────────────────────────────────────────────
_install_golang_body() {
    local ver; ver="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)" \
        || ver="go1.22.0"
    local arch="${ARCH/x86_64/amd64}"; arch="${arch/aarch64/arm64}"
    curl -fsSL "https://go.dev/dl/${ver}.linux-${arch}.tar.gz" -o /tmp/go.tar.gz || return 1
    $SUDO rm -rf /usr/local/go
    $SUDO tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    # Add to PATH hints
    local profile="$HOME/.bashrc"
    [[ -n "${ZSH_VERSION:-}" ]] && profile="$HOME/.zshrc"
    if ! grep -q '/usr/local/go/bin' "$profile" 2>/dev/null; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> "$profile"
    fi
    export PATH="$PATH:/usr/local/go/bin"
}

install_golang() {
    _already_installed go && return 0
    log_step "Installing Go..."
    spinner_start "Installing Go"
    _do_install golang _install_golang_body || return 1
    _installed_ok "Go → $(/usr/local/go/bin/go version 2>/dev/null)"
}

# ─ Rust / Cargo ───────────────────────────────────────────────────────────────
_install_rust_body() {
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path || return 1
    # shellcheck source=/dev/null
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
}

install_rust() {
    if _already_installed rustc || [[ -f "$HOME/.cargo/bin/rustc" ]]; then
        log_skip "Rust already installed. Skipping."; return 0
    fi
    log_step "Installing Rust (via rustup)..."
    spinner_start "Installing Rust"
    _do_install rust _install_rust_body || return 1
    spinner_stop ok
    source "$HOME/.cargo/env" 2>/dev/null || true
    log_ok "Rust → $(rustc --version 2>/dev/null)"
}

# =============================================================================
# ══════════════════════════ CLI UTILITIES ════════════════════════════════════
# =============================================================================

install_fzf() {
    _already_installed fzf && return 0
    log_step "Installing fzf..."
    spinner_start "Installing fzf"
    _do_install fzf _pkg_install fzf || return 1
    _installed_ok "fzf → $(fzf --version 2>/dev/null)"
}

install_bat() {
    _already_installed bat && return 0
    log_step "Installing bat (better cat)..."
    spinner_start "Installing bat"
    case "$PKG_MANAGER" in
        apt)    _do_install bat _pkg_install bat || return 1 ;;
        dnf|yum) _do_install bat _pkg_install bat || return 1 ;;
        pacman) _do_install bat _pkg_install bat || return 1 ;;
        brew)   _do_install bat _pkg_install bat || return 1 ;;
        *)      log_warn "bat not available on $OS_ID"; return 1 ;;
    esac
    _installed_ok "bat → $(bat --version 2>/dev/null)"
}

install_eza() {
    _already_installed eza && return 0
    log_step "Installing eza (modern ls)..."
    spinner_start "Installing eza"
    case "$OS_FAMILY" in
        debian)
            _do_install eza _pkg_install eza 2>/dev/null || {
                # Fallback: install via cargo if apt doesn't have it
                if command -v cargo &>/dev/null; then
                    _do_install eza cargo install eza || return 1
                else
                    log_warn "eza not in apt repos. Install Rust first, then: cargo install eza"
                    spinner_stop skip; return 1
                fi
            }
            ;;
        arch)   _do_install eza _pkg_install eza || return 1 ;;
        *)      _do_install eza _pkg_install eza || return 1 ;;
    esac
    _installed_ok "eza → $(eza --version 2>/dev/null | head -1)"
}

install_ripgrep() {
    _already_installed rg && return 0
    log_step "Installing ripgrep..."
    spinner_start "Installing ripgrep"
    _do_install ripgrep _pkg_install ripgrep || return 1
    _installed_ok "ripgrep → $(rg --version 2>/dev/null | head -1)"
}

install_jq() {
    _already_installed jq && return 0
    log_step "Installing jq..."
    spinner_start "Installing jq"
    _do_install jq _pkg_install jq || return 1
    _installed_ok "jq → $(jq --version 2>/dev/null)"
}

install_yq() {
    _already_installed yq && return 0
    log_step "Installing yq..."
    spinner_start "Installing yq"
    local ver; ver="$(curl -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 2>/dev/null)"
    _do_install yq bash -c "
        curl -fsSL 'https://github.com/mikefarah/yq/releases/download/${ver}/yq_linux_amd64' -o /tmp/yq \
        && chmod +x /tmp/yq \
        && $SUDO mv /tmp/yq /usr/local/bin/yq
    " || return 1
    _installed_ok "yq → $(yq --version 2>/dev/null)"
}

install_httpie() {
    _already_installed http && return 0
    log_step "Installing HTTPie..."
    spinner_start "Installing HTTPie"
    _do_install httpie _pkg_install httpie || return 1
    _installed_ok "HTTPie → $(http --version 2>/dev/null)"
}

install_tmux() {
    _already_installed tmux && return 0
    log_step "Installing tmux..."
    spinner_start "Installing tmux"
    _do_install tmux _pkg_install tmux || return 1
    _installed_ok "tmux → $(tmux -V 2>/dev/null)"
}

install_neovim() {
    _already_installed nvim && return 0
    log_step "Installing Neovim..."
    spinner_start "Installing Neovim"
    _do_install neovim _pkg_install neovim || return 1
    _installed_ok "Neovim → $(nvim --version 2>/dev/null | head -1)"
}

install_btop() {
    _already_installed btop && return 0
    log_step "Installing btop (system monitor)..."
    spinner_start "Installing btop"
    _do_install btop _pkg_install btop || return 1
    _installed_ok "btop → $(btop --version 2>/dev/null | head -1)"
}

# =============================================================================
# ══════════════════════════ DISPATCHER ═══════════════════════════════════════
# =============================================================================

install_tool() {
    local tool="${1,,}"
    local fn="install_${tool}"
    if declare -f "$fn" > /dev/null; then
        "$fn"
    else
        log_error "No installer for: ${BOLD}$tool${RESET}"
        log_info  "Run 'devsetup --list' to see all available tools."
        return 1
    fi
}

list_tools() {
    declare -F | awk '{print $3}' | grep '^install_' | sed 's/^install_//' | sort
}
