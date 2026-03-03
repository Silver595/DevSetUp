#!/usr/bin/env bash
# =============================================================================
#  install.sh — One-liner remote installer for devsetup
#
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
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/Silver595/DevSetUp"
RAW_URL="https://raw.githubusercontent.com/Silver595/DevSetUp/main"
INSTALL_BIN="/usr/local/bin/devsetup"
INSTALL_SHARE="/usr/share/devsetup"
INSTALLER_VERSION="1.1.0"

# ── Colors ────────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'

info()  { echo -e "${CYAN}  ➜${RESET}  $*"; }
ok()    { echo -e "${GREEN}  ✔${RESET}  $*"; }
warn()  { echo -e "${YELLOW}  ⚠${RESET}  $*"; }
die()   { echo -e "${RED}  ✘  ERROR:${RESET} $*" >&2; exit 1; }

SUDO_CMD=""
[[ "$EUID" -ne 0 ]] && SUDO_CMD="sudo"

# ── Preflight ─────────────────────────────────────────────────────────────────
# Check bash version
if (( BASH_VERSINFO[0] < 4 )); then
    die "bash 4.0+ required (you have $BASH_VERSION). Upgrade with: $SUDO_CMD apt install bash"
fi

command -v curl &>/dev/null || die "curl is required. Install it first: $SUDO_CMD apt install curl"

echo ""
echo -e "${BOLD}  DevSetup Installer v${INSTALLER_VERSION}${RESET}"
echo "  ─────────────────────────────────"
echo ""

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
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if command -v git &>/dev/null; then
    info "Cloning devsetup repository..."
    if git clone --depth=1 "$REPO_URL" "$TMP_DIR/devsetup" 2>/dev/null; then
        ok "Repository cloned"
    else
        die "Failed to clone $REPO_URL — check the URL or your internet connection."
    fi
    SRC="$TMP_DIR/devsetup"
else
    info "git not found — downloading files directly..."
    SRC="$TMP_DIR/devsetup"
    mkdir -p "$SRC/lib" "$SRC/config"

    FILES=(
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
$SUDO_CMD mkdir -p "$INSTALL_SHARE/lib" "$INSTALL_SHARE/config"

# Rewrite path vars so the installed binary finds its libraries
sed \
    -e "s|^DEVSETUP_DIR=.*|DEVSETUP_DIR=\"${INSTALL_SHARE}\"|" \
    -e "s|^LIB_DIR=.*|LIB_DIR=\"\${DEVSETUP_DIR}/lib\"|" \
    -e "s|^CONF_DIR=.*|CONF_DIR=\"\${DEVSETUP_DIR}/config\"|" \
    "$SRC/devsetup" > "$TMP_DIR/devsetup_patched"

$SUDO_CMD install -m 755 "$TMP_DIR/devsetup_patched" "$INSTALL_BIN"
$SUDO_CMD cp -r "$SRC/lib/."    "$INSTALL_SHARE/lib/"
$SUDO_CMD cp -r "$SRC/config/." "$INSTALL_SHARE/config/"
$SUDO_CMD chmod +x "$INSTALL_SHARE/lib/"*.sh

ok "Installed: $INSTALL_BIN"
ok "Data dir:  $INSTALL_SHARE"

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
