#!/usr/bin/env bash
# =============================================================================
#  install.sh — One-liner curl installer for devsetup v1.0.5
#
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/Silver595/DevSetUp/main/install.sh | bash
#    curl -fsSL https://raw.githubusercontent.com/Silver595/DevSetUp/main/install.sh | sudo bash
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/Silver595/DevSetUp"
RAW_URL="https://raw.githubusercontent.com/Silver595/DevSetUp/main"
INSTALL_BIN="/usr/local/bin/devsetup"
INSTALL_SHARE="/usr/share/devsetup"
INSTALLER_VERSION="1.0.5"

# ── Colors ────────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'

info()  { printf "${CYAN}  ➜${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}  ✔${RESET}  %s\n" "$*"; }
warn()  { printf "${YELLOW}  ⚠${RESET}  %s\n" "$*"; }
die()   { printf "${RED}  ✘  ERROR:${RESET} %s\n" "$*" >&2; exit 1; }
step()  { printf "\n${BOLD}  ── %s${RESET}\n" "$*"; }

# ── Privilege detection ───────────────────────────────────────────────────────
SUDO_CMD=""
if [[ "$EUID" -ne 0 ]]; then
    command -v sudo &>/dev/null || die "This script must be run as root or with sudo."
    SUDO_CMD="sudo"
fi

# ── Pre-flight ────────────────────────────────────────────────────────────────
printf "\n${BOLD}  ╔══════════════════════════════════════╗\n"
printf "  ║   devsetup Installer  v%-12s  ║\n" "$INSTALLER_VERSION"
printf "  ╚══════════════════════════════════════╝${RESET}\n\n"

step "Pre-flight checks"

# curl is mandatory
command -v curl &>/dev/null || die "curl is required. Install it: sudo apt install curl"
ok "curl found"

# Internet check
if curl -fsSL --max-time 6 --retry 2 https://1.1.1.1 &>/dev/null \
   || curl -fsSL --max-time 6 --retry 2 https://google.com &>/dev/null; then
    ok "Internet connection OK"
else
    die "No internet connection. Cannot download devsetup."
fi

# OS detection
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    _os="${ID,,}"
else
    _os="$(uname -s | tr '[:upper:]' '[:lower:]')"
fi

case "$_os" in
    ubuntu|debian|linuxmint|pop|kali|elementary|zorin|raspbian)
        _pkg_mgr="apt" ;;
    fedora|rhel|centos|almalinux|rocky)
        command -v dnf &>/dev/null && _pkg_mgr="dnf" || _pkg_mgr="yum" ;;
    arch|manjaro|endeavouros|garuda|artix)
        _pkg_mgr="pacman" ;;
    opensuse*|sles)
        _pkg_mgr="zypper" ;;
    darwin|macos)
        _pkg_mgr="brew" ;;
    *)
        _pkg_mgr="unknown"
        warn "Unknown OS: $_os — installation may have issues."
        ;;
esac
ok "OS detected: $_os (package manager: $_pkg_mgr)"

# ── Download ──────────────────────────────────────────────────────────────────
step "Downloading devsetup"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/devsetup"

if command -v git &>/dev/null; then
    info "Cloning repository (git)..."
    git clone --depth=1 --quiet "$REPO_URL" "$SRC" \
        || die "Failed to clone $REPO_URL — check your internet connection."
    ok "Repository cloned"
else
    info "git not found — downloading individual files..."
    mkdir -p "$SRC/lib" "$SRC/config"

    _files=(
        "devsetup"
        "lib/logger.sh"
        "lib/detect.sh"
        "lib/install.sh"
        "lib/aliases.sh"
        "lib/scaffold.sh"
        "lib/tui.sh"
        "config/tools.conf"
        "config/aliases.conf"
        "config/folders.conf"
    )
    for _f in "${_files[@]}"; do
        mkdir -p "$SRC/$(dirname "$_f")"
        curl -fsSL --retry 3 "$RAW_URL/$_f" -o "$SRC/$_f" \
            || die "Failed to download $_f — check your internet connection."
    done
    ok "${#_files[@]} files downloaded"
fi

# Basic sanity check — make sure we got the right thing
[[ -f "$SRC/devsetup" ]] || die "Download failed: main script not found in $SRC"
[[ -d "$SRC/lib" ]]      || die "Download failed: lib/ directory not found in $SRC"
[[ -d "$SRC/config" ]]   || die "Download failed: config/ directory not found in $SRC"

# ── Install ───────────────────────────────────────────────────────────────────
step "Installing to system"

$SUDO_CMD mkdir -p "$INSTALL_SHARE/lib" "$INSTALL_SHARE/config"

# Rewrite the path vars so the installed binary finds its libs correctly
sed \
    -e "s|^DEVSETUP_DIR=.*|DEVSETUP_DIR=\"${INSTALL_SHARE}\"|" \
    -e "s|^LIB_DIR=.*|LIB_DIR=\"\${DEVSETUP_DIR}/lib\"|" \
    -e "s|^CONF_DIR=.*|CONF_DIR=\"\${DEVSETUP_DIR}/config\"|" \
    "$SRC/devsetup" > "$TMP_DIR/devsetup_patched"

$SUDO_CMD install -m 755 "$TMP_DIR/devsetup_patched" "$INSTALL_BIN"
$SUDO_CMD cp -r  "$SRC/lib/."    "$INSTALL_SHARE/lib/"
$SUDO_CMD cp -r  "$SRC/config/." "$INSTALL_SHARE/config/"
$SUDO_CMD chmod +x "$INSTALL_SHARE/lib/"*.sh

ok "Binary:   $INSTALL_BIN"
ok "Data dir: $INSTALL_SHARE"

# ── Make sure /usr/local/bin is in PATH ───────────────────────────────────────
if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
    warn "/usr/local/bin is not in your PATH — adding it..."
    export PATH="/usr/local/bin:$PATH"
    warn "Add this to your ~/.bashrc or ~/.zshrc to make it permanent:"
    warn "  export PATH=\"/usr/local/bin:\$PATH\""
fi

# ── Final verification ────────────────────────────────────────────────────────
step "Verification"

if "$INSTALL_BIN" --version &>/dev/null; then
    _ver="$("$INSTALL_BIN" --version 2>/dev/null)"
    ok "$_ver installed successfully"
else
    die "Installation verification failed. Try running: $INSTALL_BIN --version"
fi

printf "\n${BOLD}${GREEN}  ✨ Done! Run:${RESET}  ${CYAN}${BOLD}devsetup${RESET}\n\n"
printf "  ${DIM}Tip: run 'devsetup --doctor' first to verify your system is ready.${RESET}\n\n"
