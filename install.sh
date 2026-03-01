#!/usr/bin/env bash
# =============================================================================
#  install.sh — One-liner remote installer for devsetup
#
#  Usage (once hosted on a server or GitHub):
#    curl -fsSL https://raw.githubusercontent.com/YOU/devsetup/main/install.sh | bash
#
#  What it does:
#    1. Downloads the devsetup repo (or just the required files)
#    2. Installs to /usr/local/bin/devsetup
#    3. Puts lib/ and config/ into /usr/share/devsetup/
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/Silver595/DevSetUp"
RAW_URL="https://raw.githubusercontent.com/Silver595/DevSetUp/main"
INSTALL_BIN="/usr/local/bin/devsetup"
INSTALL_SHARE="/usr/share/devsetup"
INSTALLER_VERSION="1.0.0"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()  { echo -e "${CYAN}  ➜${RESET}  $*"; }
ok()    { echo -e "${GREEN}  ✔${RESET}  $*"; }
warn()  { echo -e "${YELLOW}  ⚠${RESET}  $*"; }
die()   { echo -e "${RED}  ✘  ERROR:${RESET} $*" >&2; exit 1; }

SUDO_CMD=""
[[ "$EUID" -ne 0 ]] && SUDO_CMD="sudo"

# ── Preflight ─────────────────────────────────────────────────────────────────
command -v curl &>/dev/null || die "curl is required. Install it first: sudo apt install curl"

echo ""
echo -e "${BOLD}  DevSetup Installer v${INSTALLER_VERSION}${RESET}"
echo "  ─────────────────────────────────"
echo ""

# ── Download method: prefer git clone, fall back to curl ─────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if command -v git &>/dev/null; then
    info "Cloning devsetup repository..."
    git clone --depth=1 "$REPO_URL" "$TMP_DIR/devsetup" 2>/dev/null \
        || die "Failed to clone $REPO_URL — check the URL or your internet connection."
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
    for f in "${FILES[@]}"; do
        info "  Downloading $f..."
        mkdir -p "$SRC/$(dirname "$f")"
        curl -fsSL "$RAW_URL/$f" -o "$SRC/$f" \
            || die "Failed to download $f"
    done
fi

# ── Install files ─────────────────────────────────────────────────────────────
info "Installing devsetup to $INSTALL_BIN ..."
$SUDO_CMD mkdir -p "$INSTALL_SHARE/lib" "$INSTALL_SHARE/config"

# Rewrite DEVSETUP_DIR inside the script to point to installed location
sed "s|^DEVSETUP_DIR=.*|DEVSETUP_DIR=\"${INSTALL_SHARE}\"|" \
    "$SRC/devsetup" > "$TMP_DIR/devsetup_patched"

$SUDO_CMD install -m 755 "$TMP_DIR/devsetup_patched" "$INSTALL_BIN"
$SUDO_CMD cp -r "$SRC/lib/."    "$INSTALL_SHARE/lib/"
$SUDO_CMD cp -r "$SRC/config/." "$INSTALL_SHARE/config/"
$SUDO_CMD chmod +x "$INSTALL_SHARE/lib/"*.sh

ok "Installed: $INSTALL_BIN"
ok "Data dir:  $INSTALL_SHARE"

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
devsetup --version && ok "devsetup is ready!" || warn "Installation may have issues — run 'devsetup --help' to check."

echo ""
echo -e "${BOLD}  ✨ Run:  devsetup${RESET}"
echo ""
