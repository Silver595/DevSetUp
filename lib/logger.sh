#!/usr/bin/env bash
# =============================================================================
# lib/logger.sh — Colored logging, timestamps, and spinner utilities
# Enhanced UI with rich colors, icons, and premium visual design
# =============================================================================

# ── ANSI escape helpers ───────────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
ITALIC="\033[3m"
UNDERLINE="\033[4m"

# Standard colors
BLACK="\033[30m";   RED="\033[31m";     GREEN="\033[32m";   YELLOW="\033[33m"
BLUE="\033[34m";    MAGENTA="\033[35m"; CYAN="\033[36m";    WHITE="\033[37m"

# Bright/bold colors
BBLACK="\033[1;30m"; BRED="\033[1;31m";   BGREEN="\033[1;32m"; BYELLOW="\033[1;33m"
BBLUE="\033[1;34m";  BMAGENTA="\033[1;35m";BCYAN="\033[1;36m"; BWHITE="\033[1;37m"

# 256-color palette (truecolor-friendly terminals)
ORANGE="\033[38;5;214m"
PINK="\033[38;5;213m"
LAVENDER="\033[38;5;183m"
TEAL="\033[38;5;87m"
LIME="\033[38;5;154m"
GOLD="\033[38;5;220m"
CORAL="\033[38;5;209m"
INDIGO="\033[38;5;105m"

# Background accents
BG_DARK="\033[48;5;235m"
BG_BLUE="\033[48;5;18m"
BG_GREEN="\033[48;5;22m"
BG_RED="\033[48;5;52m"

# ── Icons ─────────────────────────────────────────────────────────────────────
ICON_OK="✔"
ICON_FAIL="✘"
ICON_WARN="⚠"
ICON_INFO="●"
ICON_ARROW="➜"
ICON_SKIP="⊘"
ICON_STAR="★"
ICON_DOT="·"
ICON_ROCKET="🚀"
ICON_GEAR="⚙"
ICON_LOCK="🔒"
ICON_FIRE="🔥"
ICON_SPARKLE="✨"
ICON_PACKAGE="📦"

# Log file (optional; set LOG_FILE externally to enable file logging)
LOG_FILE="${LOG_FILE:-}"

# ── Terminal width helper ──────────────────────────────────────────────────────
_term_cols() { tput cols 2>/dev/null || echo 80; }

# ── Internal timestamp ─────────────────────────────────────────────────────────
_log_timestamp() { date "+%H:%M:%S"; }

# ── Core write ────────────────────────────────────────────────────────────────
_log_write() {
    local level="$1" color="$2" icon="$3" label_color="${4:-$2}" msg="$5"
    local ts; ts="$(_log_timestamp)"

    # Colored terminal output
    printf "${DIM}%s${RESET}  ${color}${BOLD}%s${RESET}  ${label_color}%-5s${RESET}  %s\n" \
        "$ts" "$icon" "$level" "$msg" >&2

    # Plain file output
    [[ -n "$LOG_FILE" ]] && printf "[%s] [%-5s] %s\n" "$ts" "$level" "$msg" >> "$LOG_FILE"
}

# ── Public log API ────────────────────────────────────────────────────────────
log_info()  { _log_write "INFO"  "$TEAL"     "$ICON_INFO"  "$CYAN"    "$*"; }
log_ok()    { _log_write "OK"    "$BGREEN"   "$ICON_OK"    "$GREEN"   "$*"; }
log_warn()  { _log_write "WARN"  "$GOLD"     "$ICON_WARN"  "$YELLOW"  "$*"; }
log_error() { _log_write "ERROR" "$BRED"     "$ICON_FAIL"  "$RED"     "$*"; }
log_skip()  { _log_write "SKIP"  "$DIM"      "$ICON_SKIP"  "$DIM"     "$*"; }
log_step()  { _log_write "STEP"  "$LAVENDER" "$ICON_ARROW" "$INDIGO"  "$*"; }

# ── Section header ────────────────────────────────────────────────────────────
log_section() {
    local msg="$*"
    local cols; cols="$(_term_cols)"
    local inner=$(( cols - 4 ))
    local pad=$(( (inner - ${#msg}) / 2 ))
    local line; line="$(printf '─%.0s' $(seq 1 $inner))"

    echo -e "" >&2
    echo -e "${INDIGO}  ╭${line}╮${RESET}" >&2
    printf "${INDIGO}  │${RESET}%*s${BWHITE}${BOLD}%s${RESET}%*s${INDIGO}│${RESET}\n" \
        "$pad" "" "$msg" "$pad" "" >&2
    echo -e "${INDIGO}  ╰${line}╯${RESET}" >&2
    echo -e "" >&2
    [[ -n "$LOG_FILE" ]] && echo -e "\n=== $msg ===" >> "$LOG_FILE"
}

# ── Category header (for grouped tool display) ────────────────────────────────
log_category() {
    local label="$*"
    echo -e "\n${BG_DARK}${BWHITE}${BOLD}  ${ICON_GEAR} ${label}  ${RESET}" >&2
}

# ── Dry-run aware command runner ───────────────────────────────────────────────
run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "  ${DIM}${ORANGE}[dry-run]${RESET}  ${DIM}$*${RESET}" >&2
    else
        log_step "Running: $*"
        "$@"
    fi
}

# ── Spinner ──────────────────────────────────────────────────────────────────
_SPINNER_PID=""
# Braille spinner frames
_spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

spinner_start() {
    [[ "${DRY_RUN:-false}" == "true" ]] && return 0
    local msg="${1:-Working...}"
    (
        local i=0
        while true; do
            local char="${_spinner_chars:$((i % ${#_spinner_chars})):1}"
            printf "\r  ${TEAL}%s${RESET}  ${DIM}%s${RESET}   " "$char" "$msg" >&2
            sleep 0.07
            (( i++ ))
        done
    ) &
    _SPINNER_PID=$!
    disown "$_SPINNER_PID"
}

spinner_stop() {
    [[ "${DRY_RUN:-false}" == "true" ]] && return 0
    local status="${1:-ok}"
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
    fi
    printf "\r\033[2K" >&2
    case "$status" in
        ok)   printf "  ${BGREEN}${ICON_OK}${RESET}  ${GREEN}Done${RESET}\n" >&2 ;;
        fail) printf "  ${BRED}${ICON_FAIL}${RESET}  ${RED}Failed${RESET}\n" >&2 ;;
        skip) printf "  ${DIM}${ICON_SKIP}${RESET}  ${DIM}Skipped${RESET}\n" >&2 ;;
    esac
}

# ── Status badge (inline) ──────────────────────────────────────────────────────
badge() {
    local label="$1" color="${2:-$TEAL}"
    printf "${color}${BG_DARK}${BOLD} %s ${RESET}" "$label"
}

# ── Horizontal rule ───────────────────────────────────────────────────────────
log_rule() {
    local cols; cols="$(_term_cols)"
    local char="${1:-─}"
    local color="${2:-$DIM}"
    printf "${color}%*s${RESET}\n" "$cols" "" | tr ' ' "$char" >&2
}
