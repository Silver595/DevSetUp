#!/usr/bin/env bash
# =============================================================================
#  install.sh — One-liner curl installer for devsetup v1.0.5
#
<<<<<<< HEAD
#  Usage (once hosted on a server or GitHub):
#    curl -fsSL https://raw.githubusercontent.com/Silver595/DevSetUp/main/install.sh | bash
#
#  What it does:
#    1. Checks prerequisites (bash 4+, curl, internet)
#    2. Downloads the devsetup repo (or just the required files)
#    3. Installs to /usr/local/bin/devsetup
#    4. Puts lib/ and config/ into /usr/share/devsetup/
#    5. Fixes PATH if needed
#    6. Verifies installation
=======
#  Usage:
#    curl -fsSL https://raw.githubusercontent.com/Silver595/DevSetUp/main/install.sh | bash
#    curl -fsSL https://raw.githubusercontent.com/Silver595/DevSetUp/main/install.sh | sudo bash
>>>>>>> refs/remotes/origin/main
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/Silver595/DevSetUp"
RAW_URL="https://raw.githubusercontent.com/Silver595/DevSetUp/main"
INSTALL_BIN="/usr/local/bin/devsetup"
INSTALL_SHARE="/usr/share/devsetup"
<<<<<<< HEAD
INSTALLER_VERSION="1.1.0"
=======
INSTALLER_VERSION="1.0.5"
>>>>>>> refs/remotes/origin/main

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

<<<<<<< HEAD
# ── Preflight ─────────────────────────────────────────────────────────────────
# Check bash version
if (( BASH_VERSINFO[0] < 4 )); then
    die "bash 4.0+ required (you have $BASH_VERSION). Upgrade with: $SUDO_CMD apt install bash"
fi

command -v curl &>/dev/null || die "curl is required. Install it first: $SUDO_CMD apt install curl"
=======
# ── Pre-flight ────────────────────────────────────────────────────────────────
printf "\n${BOLD}  ╔══════════════════════════════════════╗\n"
printf "  ║   devsetup Installer  v%-12s  ║\n" "$INSTALLER_VERSION"
printf "  ╚══════════════════════════════════════╝${RESET}\n\n"
>>>>>>> refs/remotes/origin/main

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

<<<<<<< HEAD
# Check internet connectivity
info "Checking internet connectivity..."
if curl -fsSL --max-time 5 https://1.1.1.1 &>/dev/null \
   || curl -fsSL --max-time 5 https://google.com &>/dev/null; then
    ok "Internet: reachable"
else
    die "No internet connection. Check your network and try again."
fi

# Detect OS for context
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    info "Detected OS: ${PRETTY_NAME:-$ID}"
fi

# ── Download method: prefer git clone, fall back to curl ─────────────────────
=======
>>>>>>> refs/remotes/origin/main
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/devsetup"

if command -v git &>/dev/null; then
<<<<<<< HEAD
    info "Cloning devsetup repository..."
    if git clone --depth=1 "$REPO_URL" "$TMP_DIR/devsetup" 2>/dev/null; then
        ok "Repository cloned"
    else
        die "Failed to clone $REPO_URL — check the URL or your internet connection."
    fi
    SRC="$TMP_DIR/devsetup"
=======
    info "Cloning repository (git)..."
    git clone --depth=1 --quiet "$REPO_URL" "$SRC" \
        || die "Failed to clone $REPO_URL — check your internet connection."
    ok "Repository cloned"
>>>>>>> refs/remotes/origin/main
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
<<<<<<< HEAD
    local_fail=0
    for f in "${FILES[@]}"; do
        info "  Downloading $f..."
        mkdir -p "$SRC/$(dirname "$f")"
        if ! curl -fsSL "$RAW_URL/$f" -o "$SRC/$f"; then
            warn "Failed to download $f"
            (( local_fail++ ))
        fi
    done
    if (( local_fail > 0 )); then
        die "Failed to download $local_fail file(s). Check the repository URL."
    fi
    ok "All files downloaded"
fi

# ── Sanity check downloaded files ─────────────────────────────────────────────
info "Verifying download..."
[[ -f "$SRC/devsetup" ]]       || die "Missing: devsetup (main script)"
[[ -d "$SRC/lib" ]]            || die "Missing: lib/ directory"
[[ -d "$SRC/config" ]]         || die "Missing: config/ directory"
[[ -f "$SRC/lib/logger.sh" ]]  || die "Missing: lib/logger.sh"
[[ -f "$SRC/lib/detect.sh" ]]  || die "Missing: lib/detect.sh"
[[ -f "$SRC/lib/install.sh" ]] || die "Missing: lib/install.sh"
[[ -f "$SRC/lib/tui.sh" ]]     || die "Missing: lib/tui.sh"
[[ -f "$SRC/config/tools.conf" ]] || die "Missing: config/tools.conf"
ok "Download verified — all files present"

# ── Install files ─────────────────────────────────────────────────────────────
info "Installing devsetup to $INSTALL_BIN ..."
=======
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

>>>>>>> refs/remotes/origin/main
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

<<<<<<< HEAD
# ── Fix PATH if /usr/local/bin is not in it ───────────────────────────────────
if ! echo "$PATH" | tr ':' '\n' | grep -q '^/usr/local/bin$'; then
    warn "/usr/local/bin is not in your PATH."
    # Add to current session
    export PATH="/usr/local/bin:$PATH"
    # Add to shell RC for persistence
    local_rc="$HOME/.bashrc"
    [[ -n "${ZSH_VERSION:-}" ]] && local_rc="$HOME/.zshrc"
    if [[ -f "$local_rc" ]] && ! grep -q 'export PATH="/usr/local/bin' "$local_rc" 2>/dev/null; then
        echo 'export PATH="/usr/local/bin:$PATH"' >> "$local_rc"
        info "Added /usr/local/bin to PATH in $local_rc"
    fi
fi

# ── Remove legacy locations if they conflict ──────────────────────────────────
if [[ -f /usr/bin/devsetup && -f "$INSTALL_BIN" && /usr/bin/devsetup != "$INSTALL_BIN" ]]; then
    warn "Found legacy /usr/bin/devsetup — the curl install uses $INSTALL_BIN"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
if "$INSTALL_BIN" --version 2>/dev/null; then
    ok "devsetup is ready!"
else
    warn "Installation may have issues — try running: devsetup --help"
fi

echo ""
echo -e "${BOLD}  ✨ Run:  devsetup${RESET}"
echo -e "  ${DIM}or:    devsetup --doctor    (check system readiness)${RESET}"
echo -e "  ${DIM}or:    devsetup --help      (see all commands)${RESET}"
echo ""
=======
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
>>>>>>> refs/remotes/origin/main
