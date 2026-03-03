#!/usr/bin/env bash
# =============================================================================
# lib/logger.sh — Logging: colors, spinner, progress counter, summary box
# All color vars use $'\033' so they work in echo, printf, cat, and heredocs.
# =============================================================================

# ── ANSI palette (real ESC bytes — works in every context) ───────────────────
RESET=$'\033[0m';   BOLD=$'\033[1m';    DIM=$'\033[2m';   ITALIC=$'\033[3m'
RED=$'\033[31m';    GREEN=$'\033[32m';  YELLOW=$'\033[33m'; BLUE=$'\033[34m'
MAGENTA=$'\033[35m'; CYAN=$'\033[36m'; WHITE=$'\033[37m'
BRED=$'\033[1;31m'; BGREEN=$'\033[1;32m'; BYELLOW=$'\033[1;33m'
BCYAN=$'\033[1;36m'; BWHITE=$'\033[1;37m'; BMAGENTA=$'\033[1;35m'

# 256-colour extras
ORANGE=$'\033[38;5;214m';  PINK=$'\033[38;5;213m';    LAVENDER=$'\033[38;5;183m'
TEAL=$'\033[38;5;87m';     LIME=$'\033[38;5;154m';    GOLD=$'\033[38;5;220m'
CORAL=$'\033[38;5;209m';   INDIGO=$'\033[38;5;105m';  SKY=$'\033[38;5;117m'
BG_DARK=$'\033[48;5;235m'

# ── Icons ─────────────────────────────────────────────────────────────────────
ICON_OK="✔";  ICON_FAIL="✘"; ICON_WARN="⚠"; ICON_INFO="●"
ICON_ARROW="➜"; ICON_SKIP="⊘"; ICON_GEAR="⚙"

# ── Log file ──────────────────────────────────────────────────────────────────
LOG_FILE="${LOG_FILE:-/tmp/devsetup_$(date +%Y%m%d_%H%M%S).log}"
export LOG_FILE

# Write header to log file (only once)
if [[ ! -f "$LOG_FILE" ]]; then
    printf 'devsetup log — %s\n%s\n\n' "$(date)" "$(printf '─%.0s' {1..60})" > "$LOG_FILE"
fi

_ts()       { date "+%H:%M:%S"; }
_term_cols(){ tput cols 2>/dev/null || echo 80; }

# ── Core log writer ───────────────────────────────────────────────────────────
_log_write() {
    local icon="$1" color="$2" level="$3"; shift 3
    local msg="$*" ts; ts="$(_ts)"
    printf "${DIM}%s${RESET}  ${color}${BOLD}%s${RESET}  ${color}%-5s${RESET}  %s\n" \
        "$ts" "$icon" "$level" "$msg" >&2
    printf '[%s] [%-5s] %s\n' "$ts" "$level" "$msg" >> "$LOG_FILE"
}

log_info()  { _log_write "$ICON_INFO"  "$TEAL"     "INFO"  "$@"; }
log_ok()    { _log_write "$ICON_OK"    "$BGREEN"   "OK"    "$@"; }
log_warn()  { _log_write "$ICON_WARN"  "$GOLD"     "WARN"  "$@"; }
log_error() { _log_write "$ICON_FAIL"  "$BRED"     "ERROR" "$@"; }
log_skip()  { _log_write "$ICON_SKIP"  "$DIM"      "SKIP"  "$@"; }
log_step()  { _log_write "$ICON_ARROW" "$LAVENDER" "STEP"  "$@"; }

# Step counter:  log_progress 2 5 "nginx"
log_progress() {
    local n="$1" total="$2"; shift 2
    printf "\n  ${BG_DARK}${BWHITE}${BOLD} %s/%s ${RESET}  ${ORANGE}${BOLD}%s${RESET}\n\n" \
        "$n" "$total" "$*" >&2
}

# Box-drawing section header
log_section() {
    local msg="$*"
    local cols; cols="$(_term_cols)"
    local w=$(( cols < 64 ? cols - 4 : 60 ))
    local line; line="$(printf '─%.0s' $(seq 1 $w))"
    local pad=$(( (w - ${#msg} - 2) / 2 ))
    printf "\n${INDIGO}  ╭%s╮${RESET}\n" "$line" >&2
    printf "${INDIGO}  │${RESET}%*s ${BWHITE}${BOLD}%s${RESET} %*s${INDIGO}│${RESET}\n" \
        "$pad" "" "$msg" "$pad" "" >&2
    printf "${INDIGO}  ╰%s╯${RESET}\n\n" "$line" >&2
    printf '\n=== %s ===\n' "$msg" >> "$LOG_FILE"
}

# ── run_cmd: dry-run aware; silences output to LOG_FILE in real mode ──────────
run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        printf "  ${DIM}${ORANGE}[dry-run]${RESET}  ${DIM}%s${RESET}\n" "$*" >&2
        return 0
    fi
    printf '  $ %s\n' "$*" >> "$LOG_FILE"
    local rc=0
    "$@" >> "$LOG_FILE" 2>&1 || rc=$?
    if [[ $rc -ne 0 ]]; then
        printf '  [FAILED rc=%d] %s\n' "$rc" "$*" >> "$LOG_FILE"
    fi
    return $rc
}

# run_cmd_visible: like run_cmd but shows stdout/stderr to user too
run_cmd_visible() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        printf "  ${DIM}${ORANGE}[dry-run]${RESET}  ${DIM}%s${RESET}\n" "$*" >&2
        return 0
    fi
    printf '  $ %s\n' "$*" >> "$LOG_FILE"
    "$@" 2>&1 | tee -a "$LOG_FILE" >&2
    return "${PIPESTATUS[0]}"
}

# ── Spinner ───────────────────────────────────────────────────────────────────
_SPINNER_PID=""
_SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

spinner_start() {
    [[ "${DRY_RUN:-false}" == "true" ]] && return 0
    local msg="${1:-Working...}"
    (
        local i=0
        while true; do
            local c="${_SPINNER_CHARS:$(( i % ${#_SPINNER_CHARS} )):1}"
            printf "\r  ${TEAL}%s${RESET}  ${DIM}%s${RESET}    " "$c" "$msg" >&2
            sleep 0.08; (( i++ ))
        done
    ) &
    _SPINNER_PID=$!
    disown "$_SPINNER_PID"
}

spinner_stop() {
    [[ "${DRY_RUN:-false}" == "true" ]] && return 0
    if [[ -n "${_SPINNER_PID:-}" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
    fi
    printf "\r\033[2K" >&2
    case "${1:-ok}" in
        ok)   printf "  ${BGREEN}${ICON_OK}${RESET}  ${GREEN}Done${RESET}\n" >&2 ;;
        fail) printf "  ${BRED}${ICON_FAIL}${RESET}  ${RED}Failed${RESET}\n" >&2 ;;
        skip) printf "  ${DIM}${ICON_SKIP}${RESET}  ${DIM}Skipped${RESET}\n" >&2 ;;
    esac
}

# ── Summary tracking ──────────────────────────────────────────────────────────
declare -a _SUMMARY_OK=()
declare -a _SUMMARY_FAIL=()
declare -a _SUMMARY_SKIP=()

# Strip newlines so multiline version strings don't break box layout
summary_ok()   { _SUMMARY_OK+=(  "$(printf '%s' "$*" | tr '\n' ' ')"); }
summary_fail() { _SUMMARY_FAIL+=("$(printf '%s' "$*" | tr '\n' ' ')"); }
summary_skip() { _SUMMARY_SKIP+=("$(printf '%s' "$*" | tr '\n' ' ')"); }

log_summary() {
    local cols; cols="$(_term_cols)"
    local w=$(( cols < 64 ? cols - 4 : 60 ))
    local line; line="$(printf '─%.0s' $(seq 1 $w))"
    local title=" Installation Summary "
    local pad=$(( (w - ${#title}) / 2 ))

    printf "\n${INDIGO}  ╭%s╮${RESET}\n" "$line" >&2
    printf "${INDIGO}  │${RESET}%*s${BWHITE}${BOLD}%s${RESET}%*s${INDIGO}│${RESET}\n" \
        "$pad" "" "$title" "$pad" "" >&2
    printf "${INDIGO}  ├%s┤${RESET}\n" "$line" >&2

    local t
    for t in "${_SUMMARY_OK[@]}";   do
        printf "${INDIGO}  │${RESET}  ${BGREEN}${ICON_OK}${RESET}   %-*s${INDIGO}│${RESET}\n" \
            "$(( w - 6 ))" "$t" >&2; done
    for t in "${_SUMMARY_FAIL[@]}"; do
        printf "${INDIGO}  │${RESET}  ${BRED}${ICON_FAIL}${RESET}   %-*s${INDIGO}│${RESET}\n" \
            "$(( w - 6 ))" "$t" >&2; done
    for t in "${_SUMMARY_SKIP[@]}"; do
        printf "${INDIGO}  │${RESET}  ${DIM}${ICON_SKIP}${RESET}   %-*s${INDIGO}│${RESET}\n" \
            "$(( w - 6 ))" "$t" >&2; done

    printf "${INDIGO}  ├%s┤${RESET}\n" "$line" >&2
    printf "${INDIGO}  │${RESET}  ${BGREEN}%d ok${RESET}  ${BRED}%d failed${RESET}  ${DIM}%d skipped  log: %s${RESET}  ${INDIGO}│${RESET}\n" \
        "${#_SUMMARY_OK[@]}" "${#_SUMMARY_FAIL[@]}" "${#_SUMMARY_SKIP[@]}" \
        "$(basename "${LOG_FILE}")" >&2
    printf "${INDIGO}  ╰%s╯${RESET}\n\n" "$line" >&2
}
