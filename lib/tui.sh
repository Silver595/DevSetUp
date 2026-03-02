#!/usr/bin/env bash
# =============================================================================
# lib/tui.sh — Interactive tool selector
#   Default: pure-bash arrow-key TUI (works everywhere — sudo, SSH, tmux)
#   Override: DEVSETUP_TUI=whiptail|dialog|fzf devsetup
# =============================================================================

# ── Backend detection ─────────────────────────────────────────────────────────
_tui_detect_backend() {
    local pref="${DEVSETUP_TUI:-}"
    if [[ -n "$pref" ]] && command -v "$pref" &>/dev/null; then
        echo "$pref"; return
    fi
    echo "bash"
}
TUI_BACKEND="$(_tui_detect_backend)"

# ── Confirm prompt ────────────────────────────────────────────────────────────
tui_confirm() {
    local prompt="${1:-Are you sure?}" default="${2:-y}"
    local hint="[Y/n]"; [[ "$default" == "n" ]] && hint="[y/N]"
    printf "\n  ${TEAL}?${RESET}  ${BOLD}%s${RESET} ${DIM}%s${RESET} " "$prompt" "$hint" >&2
    local reply
    IFS= read -r reply </dev/tty 2>/dev/null || IFS= read -r reply
    reply="${reply:-$default}"
    [[ "${reply,,}" =~ ^y ]]
}

# ── Labelled read prompt ──────────────────────────────────────────────────────
tui_read() {
    local prompt="$1" default="${2:-}"
    printf "  ${TEAL}?${RESET}  ${BOLD}%s${RESET}${DIM}%s${RESET}: " \
        "$prompt" "${default:+ [$default]}" >&2
    local reply
    IFS= read -r reply </dev/tty 2>/dev/null || IFS= read -r reply
    printf '%s' "${reply:-$default}"
}

# =============================================================================
# ── Pure-bash TUI ─────────────────────────────────────────────────────────────
# Writes space-separated selection to global $_tui_out_file
# =============================================================================
_tui_bash() {
    local var_name="$1"
    local -n _grps="$var_name"

    # ── Build flat item list ──────────────────────────────────────────────────
    local -a items=() labels=() sep_colors=()
    local total cursor=1 scroll=0

    # Category colours/icons
    declare -A _CC=(
        [DevOps]="$TEAL"    [IaC]="$ORANGE"    [Cloud]="$INDIGO"
        [WebServer]="$LIME" [PHP]="$LAVENDER"  [Database]="$CORAL"
        [Languages]="$YELLOW" [VCS]="$BCYAN"   [Utils]="$PINK"
    )

    local -a sorted_cats=()
    mapfile -t sorted_cats < <(printf '%s\n' "${!_grps[@]}" | sort)

    # Pre-compute installed status — avoids repeated command -v on every redraw
    declare -A _installed=()
    for cat in "${sorted_cats[@]}"; do
        for tool in ${_grps[$cat]}; do
            command -v "$tool" &>/dev/null && _installed["$tool"]=1 || _installed["$tool"]=0
        done
    done

    # Build flat items / labels / sep_color arrays
    local -a sep_colors=()   # colour code per item (empty for non-separators)
    for cat in "${sorted_cats[@]}"; do
        # category header row
        items+=("")
        labels+=("${cat}")
        sep_colors+=("${_CC[$cat]:-$TEAL}")
        for tool in ${_grps[$cat]}; do
            items+=("$tool")
            labels+=("$tool")
            sep_colors+=("")
        done
    done

    local total="${#items[@]}"
    (( total == 0 )) && { log_warn "No tools found in tools.conf"; return 1; }

    local -a selected=()
    local cursor=1 scroll=0
    local ROWS; ROWS=$(( $(tput lines 2>/dev/null || echo 24) - 9 ))
    (( ROWS < 5 )) && ROWS=5

    # Save/restore terminal
    local OLD_STTY; OLD_STTY="$(stty -g 2>/dev/null || true)"
    stty -echo -icanon min 1 time 0 2>/dev/null || true
    tput civis 2>/dev/null || true

    # ── Helpers ────────────────────────────────────────────────────────────────
    _is_sep()  { [[ -n "${sep_colors[$1]:-}" ]]; }
    _is_sel()  {
        local i; for i in "${selected[@]}"; do [[ "$i" == "$1" ]] && return 0; done
        return 1
    }
    _toggle()  {
        _is_sep "$1" && return
        if _is_sel "$1"; then
            local new=()
            local i; for i in "${selected[@]}"; do [[ "$i" != "$1" ]] && new+=("$i"); done
            selected=("${new[@]}")
        else
            selected+=("$1")
        fi
    }
    _next() {
        local i=$(( cursor + 1 ))
        while (( i < total )); do _is_sep "$i" || { cursor=$i; return; }; (( i++ )); done
    }
    _prev() {
        local i=$(( cursor - 1 ))
        while (( i >= 0 )); do _is_sep "$i" || { cursor=$i; return; }; (( i-- )); done
    }

    # ── Draw entire TUI ───────────────────────────────────────────────────────
    _draw() {
        # Move cursor to top-left and clear (faster than `clear`)
        printf '\033[H\033[2J\033[3J' >&2

        printf "${INDIGO}${BOLD}  ╔══════════════════════════════════════════════════╗\n" >&2
        printf "  ║   ${BWHITE}devsetup — Select Tools to Install${INDIGO}           ║\n" >&2
        printf "  ╚══════════════════════════════════════════════════╝${RESET}\n" >&2
        printf "  ${DIM}↑/↓ move   Space select   Enter confirm   a all   n none   q quit${RESET}\n\n" >&2

        local end=$(( scroll + ROWS ))
        (( end > total )) && end=$total

        for (( idx = scroll; idx < end; idx++ )); do
            if _is_sep "$idx"; then
                printf "  %s${BOLD}  ▸ %-24s${RESET}\n" \
                    "${sep_colors[$idx]}" "${labels[$idx]}" >&2
            else
                local t="${items[$idx]}"
                local mark="${DIM}[ ]${RESET}"
                _is_sel "$idx" && mark="${BGREEN}[✔]${RESET}"
                local cur="   "
                [[ "$idx" == "$cursor" ]] && cur="${ORANGE}❯  ${RESET}"
                if [[ "${_installed[$t]:-0}" == "1" ]]; then
                    printf "  %s%s ${BOLD}%-18s${RESET}  ${DIM}installed${RESET}\n" \
                        "$cur" "$mark" "$t" >&2
                else
                    printf "  %s%s %-18s\n" "$cur" "$mark" "$t" >&2
                fi
            fi
        done

        # Scroll indicator + selection count
        if (( total > ROWS + scroll )); then
            printf "\n  ${DIM}↓ more below (showing %d–%d of %d items)${RESET}\n" \
                "$scroll" "$end" "$total" >&2
        elif (( scroll > 0 )); then
            printf "\n  ${DIM}↑ more above (showing %d–%d of %d items)${RESET}\n" \
                "$scroll" "$end" "$total" >&2
        else
            printf "\n" >&2
        fi
        printf "  ${TEAL}${BOLD}%d tool(s) selected${RESET}  ${DIM}(scroll: %d/%d)${RESET}\n" \
            "${#selected[@]}" "$scroll" "$(( total - ROWS ))" >&2
    }

    # ── Event loop ────────────────────────────────────────────────────────────
    while true; do
        # Keep cursor in scroll window
        while (( cursor < scroll       )); do (( scroll-- )); done
        while (( cursor >= scroll+ROWS )); do (( scroll++ )); done

        _draw

        local key="" esc=""
        IFS= read -r -s -n1 key </dev/tty
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -r -s -n1 -t0.1 esc </dev/tty
            if [[ "$esc" == "[" ]]; then
                IFS= read -r -s -n1 -t0.1 key </dev/tty
                case "$key" in
                    A) _prev ;;                           # Up arrow
                    B) _next ;;                           # Down arrow
                    5) (( scroll -= ROWS/2 ))             # Page up
                       (( scroll < 0 )) && scroll=0 ;;
                    6) (( scroll += ROWS/2 )) ;;          # Page down
                esac
            fi
        else
            case "$key" in
                " ")  _toggle "$cursor" ;;               # Space = toggle
                "")   break ;;                           # Enter = confirm
                k|K)  _prev ;;
                j|J)  _next ;;
                a|A)  selected=()
                      local i; for (( i=0; i<total; i++ )); do
                          _is_sep "$i" || selected+=("$i")
                      done ;;
                n|N)  selected=() ;;
                q|Q)
                    stty "$OLD_STTY" 2>/dev/null || true
                    tput cnorm 2>/dev/null || true
                    printf '\033[H\033[2J\033[3J' >&2
                    return 1 ;;
            esac
        fi
    done

    # Restore terminal
    stty "$OLD_STTY" 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    printf '\033[H\033[2J\033[3J' >&2

    # Collect tool names and write to output file
    local -a result=()
    local idx
    for idx in "${selected[@]}"; do
        [[ -n "${items[$idx]:-}" ]] && result+=("${items[$idx]}")
    done

    if [[ ${#result[@]} -gt 0 ]]; then
        printf '%s ' "${result[@]}" > "$_tui_out_file"
    fi
}

# =============================================================================
# ── whiptail backend ──────────────────────────────────────────────────────────
# =============================================================================
_tui_whiptail() {
    local var_name="$1"
    local -n _g="$var_name"
    local -a args=() sorted_cats=()
    mapfile -t sorted_cats < <(printf '%s\n' "${!_g[@]}" | sort)
    for cat in "${sorted_cats[@]}"; do
        for tool in ${_g[$cat]}; do
            local state="OFF"
            command -v "$tool" &>/dev/null && state="ON"
            args+=("$tool" "[$cat]" "$state")
        done
    done
    local _tmp; _tmp="$(mktemp)"
    whiptail --title "devsetup — Tool Selector" \
        --checklist "Space=toggle  Enter=confirm  Esc=cancel" \
        30 65 20 "${args[@]}" 2>"$_tmp"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        tr -d '"' < "$_tmp" | tr ' ' '\n' | grep -v '^\s*$' \
            | tr '\n' ' ' > "$_tui_out_file"
    fi
    rm -f "$_tmp"
    return $rc
}

# =============================================================================
# ── dialog backend ────────────────────────────────────────────────────────────
# =============================================================================
_tui_dialog() {
    local var_name="$1"
    local -n _g="$var_name"
    local -a args=() sorted_cats=()
    mapfile -t sorted_cats < <(printf '%s\n' "${!_g[@]}" | sort)
    for cat in "${sorted_cats[@]}"; do
        for tool in ${_g[$cat]}; do
            local state="off"
            command -v "$tool" &>/dev/null && state="on"
            args+=("$tool" "[$cat]" "$state")
        done
    done
    local _tmp; _tmp="$(mktemp)"
    dialog --title "devsetup — Tool Selector" \
        --checklist "Space=toggle  Enter=confirm  Esc=cancel" \
        30 65 20 "${args[@]}" 2>"$_tmp"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        tr -d '"' < "$_tmp" | tr ' ' '\n' | grep -v '^\s*$' \
            | tr '\n' ' ' > "$_tui_out_file"
    fi
    rm -f "$_tmp"
    return $rc
}

# =============================================================================
# ── fzf backend ───────────────────────────────────────────────────────────────
# =============================================================================
_tui_fzf() {
    local var_name="$1"
    local -n _g="$var_name"
    local -a all=() sorted_cats=()
    mapfile -t sorted_cats < <(printf '%s\n' "${!_g[@]}" | sort)
    for cat in "${sorted_cats[@]}"; do
        for tool in ${_g[$cat]}; do
            local mark=" "
            command -v "$tool" &>/dev/null && mark="✔"
            all+=("$(printf '%-12s  %-20s  %s' "[$cat]" "$tool" "$mark")")
        done
    done
    printf '%s\n' "${all[@]}" \
        | fzf --multi \
              --prompt="  Search > " \
              --header=$'devsetup | Tab/Space=select  Enter=confirm  Esc=cancel' \
              --height=90% --border=rounded --layout=reverse \
              --color='header:italic,border:blue' \
        | awk '{print $2}' | tr '\n' ' ' > "$_tui_out_file"
}

# =============================================================================
# ── Main dispatcher ───────────────────────────────────────────────────────────
# Caller must set/export _tui_out_file before calling.
# Returns 0 if at least one tool selected, 1 if cancelled/empty.
# =============================================================================
tui_select_tools() {
    local var_name="$1"
    : > "$_tui_out_file"  # start empty

    case "$TUI_BACKEND" in
        whiptail) _tui_whiptail "$var_name" || return 1 ;;
        dialog)   _tui_dialog   "$var_name" || return 1 ;;
        fzf)      _tui_fzf      "$var_name" ;;
        bash)     _tui_bash     "$var_name" || return 1 ;;
    esac

    # Verify something was actually written
    local result; result="$(cat "$_tui_out_file" 2>/dev/null)"
    result="${result//[[:space:]]/}"   # strip all whitespace
    [[ -n "$result" ]]
}
