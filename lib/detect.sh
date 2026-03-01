#!/usr/bin/env bash
# =============================================================================
# lib/detect.sh — OS, architecture, and package manager detection
# =============================================================================

# Exports after detect_os():
#   OS_ID        e.g. ubuntu, fedora, arch, debian, centos
#   OS_FAMILY    debian | rhel | arch
#   OS_VERSION   version string from /etc/os-release
#   PKG_MANAGER  apt | dnf | yum | pacman
#   ARCH         x86_64 | aarch64 | armv7l
#   SUDO         "sudo" or "" (if already root)

detect_os() {
    # ── Architecture ─────────────────────────────────────────────────────────
    ARCH="$(uname -m)"

    # ── Privilege ─────────────────────────────────────────────────────────────
    if [[ "$EUID" -eq 0 ]]; then
        SUDO=""
    else
        SUDO="sudo"
    fi

    # ── OS detection from /etc/os-release ─────────────────────────────────────
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="${ID,,}"       # lowercase; e.g. ubuntu, fedora, arch
        OS_VERSION="${VERSION_ID:-unknown}"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        OS_ID="macos"
        OS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
    fi

    # ── Family & package manager ───────────────────────────────────────────────
    case "$OS_ID" in
        ubuntu|debian|linuxmint|pop|kali|elementary|zorin|raspbian)
            OS_FAMILY="debian"
            PKG_MANAGER="apt"
            ;;
        fedora|rhel|centos|almalinux|rocky|ol)
            OS_FAMILY="rhel"
            if command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            ;;
        arch|manjaro|endeavouros|garuda|artix)
            OS_FAMILY="arch"
            PKG_MANAGER="pacman"
            ;;
        opensuse*|sles)
            OS_FAMILY="suse"
            PKG_MANAGER="zypper"
            ;;
        macos)
            OS_FAMILY="macos"
            PKG_MANAGER="brew"
            ;;
        *)
            OS_FAMILY="unknown"
            PKG_MANAGER="unknown"
            ;;
    esac

    export OS_ID OS_FAMILY OS_VERSION PKG_MANAGER ARCH SUDO
}

# Print a short detection summary
detect_print_summary() {
    detect_os
    echo "  OS         : $OS_ID ($OS_VERSION)"
    echo "  OS Family  : $OS_FAMILY"
    echo "  Arch       : $ARCH"
    echo "  Pkg Mgr    : $PKG_MANAGER"
    echo "  Sudo       : ${SUDO:-'(running as root)'}"
}

# Assert that the current OS is supported; exit with message if not.
assert_supported_os() {
    detect_os
    if [[ "$PKG_MANAGER" == "unknown" ]]; then
        echo "ERROR: Unsupported OS: $OS_ID. Supported: Debian/Ubuntu, Fedora/RHEL, Arch, openSUSE." >&2
        exit 1
    fi
}

# Check if a command exists on PATH
cmd_exists() { command -v "$1" &>/dev/null; }

# Return the installed version of a command (first arg after version flag)
cmd_version() {
    local cmd="$1"; shift
    local ver_flag="${1:---version}"
    "$cmd" "$ver_flag" 2>&1 | head -1
}
