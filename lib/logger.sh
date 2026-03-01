#!/usr/bin/env bash
# =============================================================================
# lib/logger.sh — Colored logging, timestamps, and spinner utilities
# =============================================================================

# ── Colors & Styles ──────────────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

BLACK="\033[0;30m";  RED="\033[0;31m";    GREEN="\033[0;32m";  YELLOW="\033[0;33m"
BLUE="\033[0;34m";   MAGENTA="\033[0;35m"; CYAN="\033[0;36m";  WHITE="\033[0;37m"

BBLACK="\033[1;30m"; BRED="\033[1;31m";   BGREEN="\033[1;32m"; BYELLOW="\033[1;33m"
BBLUE="\033[1;34m";  BMAGENTA="\033[1;35m";BCYAN="\033[1;36m"; BWHITE="\033[1;37m"

# Icons
ICON_OK="✔"
ICON_FAIL="✘"
ICON_WARN="⚠"
ICON_INFO="●"
ICON_ARROW="➜"
ICON_SKIP="⊘"

# Log file (optional; set LOG_FILE externally to enable file logging)
LOG_FILE="${LOG_FILE:-}"

# ── Internal helper ───────────────────────────────────────────────────────────
_log_timestamp() {
    date "+%Y-%m-%d %H:%M:%S"
}

_log_write() {
    local level="$1"; local color="$2"; local icon="$3"; local msg="$4"
    local ts; ts="$(_log_timestamp)"
    local plain="[$ts] [$level] $msg"
    local pretty="${DIM}[$ts]${RESET} ${color}${BOLD}${icon} ${level}${RESET} ${color}${msg}${RESET}"

    echo -e "$pretty" >&2
    [[ -n "$LOG_FILE" ]] && echo "$plain" >> "$LOG_FILE"
}

# ── Public API ────────────────────────────────────────────────────────────────
log_info()    { _log_write "INFO " "$CYAN"    "$ICON_INFO"  "$*"; }
log_ok()      { _log_write "OK   " "$BGREEN"  "$ICON_OK"    "$*"; }
log_warn()    { _log_write "WARN " "$BYELLOW" "$ICON_WARN"  "$*"; }
log_error()   { _log_write "ERROR" "$BRED"    "$ICON_FAIL"  "$*"; }
log_skip()    { _log_write "SKIP " "$DIM"     "$ICON_SKIP"  "$*"; }
log_step()    { _log_write "STEP " "$BBLUE"   "$ICON_ARROW" "$*"; }
log_section() {
    local msg="$*"
    local width=60
    local line; line=$(printf '─%.0s' $(seq 1 $width))
    echo -e "\n${BMAGENTA}${line}${RESET}"
    echo -e "${BMAGENTA}  ${BOLD}${msg}${RESET}"
    echo -e "${BMAGENTA}${line}${RESET}\n"
    [[ -n "$LOG_FILE" ]] && echo -e "\n=== $msg ===" >> "$LOG_FILE"
}

# Dry-run aware command executor
# Usage: run_cmd CMD [ARGS...]
run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo -e "${DIM}[dry-run]${RESET} ${CYAN}$*${RESET}"
    else
        log_step "Running: $*"
        "$@"
    fi
}

# ── Spinner ──────────────────────────────────────────────────────────────────
_SPINNER_PID=""
_spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

spinner_start() {
    local msg="${1:-Working...}"
    (
        local i=0
        while true; do
            local char="${_spinner_chars:$((i % ${#_spinner_chars})):1}"
            echo -ne "\r${BCYAN}${char}${RESET} ${msg}   " >&2
            sleep 0.08
            ((i++))
        done
    ) &
    _SPINNER_PID=$!
    disown "$_SPINNER_PID"
}

spinner_stop() {
    local status="${1:-ok}"   # ok | fail | skip
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
    fi
    echo -ne "\r\033[2K" >&2   # clear spinner line

    case "$status" in
        ok)   echo -e "${BGREEN}${ICON_OK}  Done${RESET}" >&2 ;;
        fail) echo -e "${BRED}${ICON_FAIL}  Failed${RESET}" >&2 ;;
        skip) echo -e "${DIM}${ICON_SKIP}  Skipped${RESET}" >&2 ;;
    esac
}
