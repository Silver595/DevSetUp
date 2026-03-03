#!/usr/bin/env bash
# =============================================================================
# lib/detect.sh — OS/arch/pkg detection + doctor pre-flight checks
# =============================================================================

detect_os() {
    ARCH="$(uname -m)"
    SUDO=""; [[ "$EUID" -ne 0 ]] && SUDO="sudo"

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="${ID,,}"; OS_VERSION="${VERSION_ID:-unknown}"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        OS_ID="macos"; OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
    else
        OS_ID="unknown"; OS_VERSION="unknown"
    fi

    case "$OS_ID" in
        ubuntu|debian|linuxmint|pop|kali|elementary|zorin|raspbian)
            OS_FAMILY="debian"; PKG_MANAGER="apt" ;;
        fedora|rhel|centos|almalinux|rocky|ol)
            OS_FAMILY="rhel"
            command -v dnf &>/dev/null && PKG_MANAGER="dnf" || PKG_MANAGER="yum" ;;
        arch|manjaro|endeavouros|garuda|artix)
            OS_FAMILY="arch"; PKG_MANAGER="pacman" ;;
        opensuse*|sles)
            OS_FAMILY="suse"; PKG_MANAGER="zypper" ;;
        macos)
            OS_FAMILY="macos"; PKG_MANAGER="brew" ;;
        *)
            OS_FAMILY="unknown"; PKG_MANAGER="unknown" ;;
    esac

    export OS_ID OS_FAMILY OS_VERSION PKG_MANAGER ARCH SUDO
}

detect_print_summary() {
    detect_os
    printf "  %-14s %s\n" "OS:"         "$OS_ID ($OS_VERSION)"
    printf "  %-14s %s\n" "Family:"     "$OS_FAMILY"
    printf "  %-14s %s\n" "Arch:"       "$ARCH"
    printf "  %-14s %s\n" "Pkg Mgr:"    "$PKG_MANAGER"
    printf "  %-14s %s\n" "Privilege:"  "${SUDO:-running as root}"
}

assert_supported_os() {
    detect_os
    if [[ "$PKG_MANAGER" == "unknown" ]]; then
        echo "ERROR: Unsupported OS: $OS_ID" >&2; exit 1
    fi
}

cmd_exists() { command -v "$1" &>/dev/null; }

# =============================================================================
# ── Doctor pre-flight checks ──────────────────────────────────────────────────
# =============================================================================

_check_pass() { printf "  ${BGREEN}✔${RESET}  %-30s ${GREEN}%s${RESET}\n" "$1" "${2:-}" >&2; }
_check_fail() { printf "  ${BRED}✘${RESET}  %-30s ${RED}%s${RESET}\n"   "$1" "${2:-}" >&2; }
_check_warn() { printf "  ${GOLD}⚠${RESET}  %-30s ${YELLOW}%s${RESET}\n" "$1" "${2:-}" >&2; }

check_internet() {
    if curl -fsSL --max-time 4 https://1.1.1.1 &>/dev/null \
       || curl -fsSL --max-time 4 https://google.com &>/dev/null; then
        _check_pass "Internet connectivity" "reachable"
        return 0
    else
        _check_fail "Internet connectivity" "OFFLINE — installs will fail"
        return 1
    fi
}

check_sudo() {
    if [[ "$EUID" -eq 0 ]]; then
        _check_pass "Privilege" "running as root"
        return 0
    elif sudo -n true 2>/dev/null; then
        _check_pass "Sudo access" "passwordless sudo available"
        return 0
    else
        _check_warn "Sudo access" "will prompt for password during installs"
        return 0   # warn only, not fatal
    fi
}

check_disk_space() {
    local mount="${1:-/}"
    local avail_mb
    avail_mb=$(df -m "$mount" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -z "$avail_mb" ]]; then
        _check_warn "Disk space ($mount)" "could not determine"
        return 0
    fi
    if (( avail_mb >= 1024 )); then
        _check_pass "Disk space ($mount)" "${avail_mb}MB free"
    elif (( avail_mb >= 500 )); then
        _check_warn "Disk space ($mount)" "${avail_mb}MB free — low"
    else
        _check_fail "Disk space ($mount)" "${avail_mb}MB free — critically low!"
        return 1
    fi
}

check_pkg_manager() {
    if [[ "$PKG_MANAGER" == "unknown" ]]; then
        _check_fail "Package manager" "not detected (unsupported OS: $OS_ID)"
        return 1
    fi
    _check_pass "Package manager" "$PKG_MANAGER (OS: $OS_ID $OS_VERSION)"
}

check_required_tools() {
    local missing=()
    for t in curl bash; do
        command -v "$t" &>/dev/null || missing+=("$t")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        _check_pass "Required tools" "curl, bash present"
        return 0
    else
        _check_fail "Required tools" "MISSING: ${missing[*]}"
        return 1
    fi
}

check_pkg_lock() {
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        if fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; then
            _check_warn "Package lock" "dpkg/apt is locked by another process"
            return 1
        fi
    fi
    _check_pass "Package lock" "no lock detected"
}

check_memory() {
    local mem_mb
    mem_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $7}')
    if [[ -z "$mem_mb" ]]; then
        _check_warn "Available memory" "could not determine"
        return 0
    fi
    if (( mem_mb >= 512 )); then
        _check_pass "Available memory" "${mem_mb}MB free"
    elif (( mem_mb >= 256 )); then
        _check_warn "Available memory" "${mem_mb}MB free — low, installs may be slow"
    else
        _check_fail "Available memory" "${mem_mb}MB free — critically low!"
        return 1
    fi
}

check_bash_version() {
    if (( BASH_VERSINFO[0] >= 4 )); then
        _check_pass "Bash version" "$BASH_VERSION"
    else
        _check_fail "Bash version" "$BASH_VERSION (need 4.0+)"
        return 1
    fi
}

run_doctor() {
    detect_os
    echo -e "" >&2
    printf "  ${BWHITE}${BOLD}devsetup --doctor${RESET}  ${DIM}Pre-flight system check${RESET}\n" >&2
    echo -e "" >&2

    local issues=0
    check_bash_version   || (( issues++ ))
    check_internet       || (( issues++ ))
    check_sudo
    check_disk_space /   || (( issues++ ))
    check_memory         || (( issues++ ))
    check_pkg_manager    || (( issues++ ))
    check_required_tools || (( issues++ ))
    check_pkg_lock

    echo -e "" >&2
    if (( issues == 0 )); then
        printf "  ${BGREEN}✔  All checks passed — ready to install!${RESET}\n\n" >&2
    else
        printf "  ${BRED}✘  %d issue(s) found — resolve before installing.${RESET}\n\n" "$issues" >&2
    fi
    return "$issues"
}
