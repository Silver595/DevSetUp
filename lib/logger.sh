#!/usr/bin/env bash
# =============================================================================
# lib/logger.sh — Premium logging: colors, spinner, progress, summary
# =============================================================================

# ── ANSI palette ─────────────────────────────────────────────────────────────
RESET="\033[0m";  BOLD="\033[1m"; DIM="\033[2m"; ITALIC="\033[3m"
BLACK="\033[30m"; RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
BLUE="\033[34m";  MAGENTA="\033[35m"; CYAN="\033[36m"; WHITE="\033[37m"
BBLACK="\033[1;30m"; BRED="\033[1;31m"; BGREEN="\033[1;32m"
BYELLOW="\033[1;33m"; BBLUE="\033[1;34m"; BMAGENTA="\033[1;35m"
BCYAN="\033[1;36m"; BWHITE="\033[1;37m"

# 256-color extras
ORANGE="\033[38;5;214m"; PINK="\033[38;5;213m";   LAVENDER="\033[38;5;183m"
TEAL="\033[38;5;87m";    LIME="\033[38;5;154m";   GOLD="\033[38;5;220m"
CORAL="\033[38;5;209m";  INDIGO="\033[38;5;105m"; SKY="\033[38;5;117m"
BG_DARK="\033[48;5;235m"

# ── Icons ─────────────────────────────────────────────────────────────────────
ICON_OK="✔";  ICON_FAIL="✘"; ICON_WARN="⚠"; ICON_INFO="●"
ICON_ARROW="➜"; ICON_SKIP="⊘"; ICON_GEAR="⚙"

# ── Log file ──────────────────────────────────────────────────────────────────
LOG_FILE="${LOG_FILE:-/tmp/devsetup_$(date +%Y%m%d_%H%M%S).log}"
export LOG_FILE

# Write header to log file
[[ ! -f "$LOG_FILE" ]] && printf "devsetup log — %s\n%s\n\n" "$(date)" "$(printf '─%.0s' {1..60})" > "$LOG_FILE"

_ts()       { date "+%H:%M:%S"; }
_term_cols(){ tput cols 2>/dev/null || echo 80; }

# ── Core write ────────────────────────────────────────────────────────────────
_log_write() {
    local icon="$1" color="$2" level="$3" msg="$4"
    local ts; ts="$(_ts)"
    printf "${DIM}%s${RESET}  ${color}${BOLD}%s${RESET}  ${color}%-5s${RESET}  %s\n" \
        "$ts" "$icon" "$level" "$msg" >&2
    printf "[%s] [%-5s] %s\n" "$ts" "$level" "$msg" >> "$LOG_FILE"
}

# ── Public API ────────────────────────────────────────────────────────────────
log_info()  { _log_write "$ICON_INFO"  "$TEAL"     "INFO"  "$*"; }
log_ok()    { _log_write "$ICON_OK"    "$BGREEN"   "OK"    "$*"; }
log_warn()  { _log_write "$ICON_WARN"  "$GOLD"     "WARN"  "$*"; }
log_error() { _log_write "$ICON_FAIL"  "$BRED"     "ERROR" "$*"; }
log_skip()  { _log_write "$ICON_SKIP"  "$DIM"      "SKIP"  "$*"; }
log_step()  { _log_write "$ICON_ARROW" "$LAVENDER" "STEP"  "$*"; }

# Progress: [N/TOTAL] label
log_progress() {
    local n="$1" total="$2"; shift 2
    local label="$*"
    printf "\n  ${BG_DARK}${BWHITE}${BOLD} %s/%s ${RESET}  ${ORANGE}${BOLD}%s${RESET}\n\n" \
        "$n" "$total" "$label" >&2
}

# Box-drawing section header
log_section() {
    local msg="$*"
    local cols; cols="$(_term_cols)"
    local w=$(( cols < 64 ? cols - 4 : 60 ))
    local line; line="$(printf '─%.0s' $(seq 1 $w))"
    local pad=$(( (w - ${#msg} - 2) / 2 ))
    echo -e "" >&2
    echo -e "${INDIGO}  ╭${line}╮${RESET}" >&2
    printf "${INDIGO}  │${RESET}%*s ${BWHITE}${BOLD}%s${RESET} %*s${INDIGO}│${RESET}\n" \
        "$pad" "" "$msg" "$pad" "" >&2
    echo -e "${INDIGO}  ╰${line}╯${RESET}" >&2
    echo -e "" >&2
    printf "\n=== %s ===\n" "$msg" >> "$LOG_FILE"
}

log_category() {
    printf "\n  ${BG_DARK}${BWHITE}${BOLD}  ${ICON_GEAR} %s  ${RESET}\n" "$*" >&2
}

# ── run_cmd: dry-run aware, pipes real output to log file ─────────────────────
run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        printf "  ${DIM}${ORANGE}[dry-run]${RESET}  ${DIM}%s${RESET}\n" "$*" >&2
        return 0
    fi
    # Pipe stdout+stderr to log file only; suppress terminal noise
    printf "  $ %s\n" "$*" >> "$LOG_FILE"
    "$@" >> "$LOG_FILE" 2>&1
}

# ── Spinner ──────────────────────────────────────────────────────────────────
_SPINNER_PID=""
_SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

spinner_start() {
    [[ "${DRY_RUN:-false}" == "true" ]] && return 0
    local msg="${1:-Working...}"
    (
        local i=0
        while true; do
            local c="${_SPINNER_CHARS:$((i % ${#_SPINNER_CHARS})):1}"
            printf "\r  ${TEAL}%s${RESET}  ${DIM}%s${RESET}    " "$c" "$msg" >&2
            sleep 0.07; (( i++ ))
        done
    ) &
    _SPINNER_PID=$!
    disown "$_SPINNER_PID"
}

spinner_stop() {
    [[ "${DRY_RUN:-false}" == "true" ]] && return 0
    [[ -n "$_SPINNER_PID" ]] && {
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
    }
    printf "\r\033[2K" >&2
    case "${1:-ok}" in
        ok)   printf "  ${BGREEN}${ICON_OK}${RESET}  ${GREEN}Done${RESET}\n" >&2 ;;
        fail) printf "  ${BRED}${ICON_FAIL}${RESET}  ${RED}Failed${RESET}\n" >&2 ;;
        skip) printf "  ${DIM}${ICON_SKIP}${RESET}  ${DIM}Skipped${RESET}\n" >&2 ;;
    esac
}

# ── Final summary ─────────────────────────────────────────────────────────────
# Usage: populate arrays then call log_summary
declare -a _SUMMARY_OK=()
declare -a _SUMMARY_FAIL=()
declare -a _SUMMARY_SKIP=()

summary_ok()   { _SUMMARY_OK+=("$(echo -n "$*" | tr '\n' ' ')"); }
summary_fail() { _SUMMARY_FAIL+=("$(echo -n "$*" | tr '\n' ' ')"); }
summary_skip() { _SUMMARY_SKIP+=("$(echo -n "$*" | tr '\n' ' ')"); }

log_summary() {
    local cols; cols="$(_term_cols)"
    local w=$(( cols < 64 ? cols - 4 : 60 ))
    local line; line="$(printf '─%.0s' $(seq 1 $w))"

    echo -e "" >&2
    echo -e "${INDIGO}  ╭${line}╮${RESET}" >&2
    printf "${INDIGO}  │${RESET}%*s${BWHITE}${BOLD} Installation Summary ${RESET}%*s${INDIGO}│${RESET}\n" \
        "$(( (w - 22) / 2 ))" "" "$(( (w - 22) / 2 ))" "" >&2
    echo -e "${INDIGO}  ├${line}┤${RESET}" >&2

    for t in "${_SUMMARY_OK[@]}";   do
        printf "${INDIGO}  │${RESET}  ${BGREEN}${ICON_OK}${RESET}  ${GREEN}%-*s${RESET}${INDIGO}│${RESET}\n" \
            "$(( w - 5 ))" "$t" >&2; done
    for t in "${_SUMMARY_FAIL[@]}"; do
        printf "${INDIGO}  │${RESET}  ${BRED}${ICON_FAIL}${RESET}  ${RED}%-*s${RESET}${INDIGO}│${RESET}\n" \
            "$(( w - 5 ))" "$t" >&2; done
    for t in "${_SUMMARY_SKIP[@]}"; do
        printf "${INDIGO}  │${RESET}  ${DIM}${ICON_SKIP}${RESET}  ${DIM}%-*s${RESET}${INDIGO}│${RESET}\n" \
            "$(( w - 5 ))" "$t" >&2; done

    echo -e "${INDIGO}  ├${line}┤${RESET}" >&2
    printf "${INDIGO}  │${RESET}  ${BGREEN}%d ok${RESET}  ${BRED}%d failed${RESET}  ${DIM}%d skipped${RESET}  ${DIM}│ log: %s${RESET}${INDIGO}│${RESET}\n" \
        "${#_SUMMARY_OK[@]}" "${#_SUMMARY_FAIL[@]}" "${#_SUMMARY_SKIP[@]}" \
        "$(basename "${LOG_FILE}")" >&2
    echo -e "${INDIGO}  ╰${line}╯${RESET}" >&2
    echo -e "" >&2
}

log_rule() {
    local cols; cols="$(_term_cols)"
    printf "${DIM}%s${RESET}\n" "$(printf '─%.0s' $(seq 1 $cols))" >&2
}
