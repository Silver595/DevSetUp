#!/usr/bin/env bash
# =============================================================================
# lib/tui.sh — Interactive tool selector
#   Chain: whiptail → dialog → fzf → pure-bash (always works, arrow keys)
#   All backends write the selected tool list to a file (_tui_out_file).
#   This avoids any subshell / fd-swap complications.
# =============================================================================

# ── Detect backend ────────────────────────────────────────────────────────────
# Pure-bash TUI is the default — works in sudo, SSH, any terminal.
# Override with: DEVSETUP_TUI=whiptail devsetup
_tui_detect_backend() {
    local pref="${DEVSETUP_TUI:-}"
    if [[ -n "$pref" ]] && command -v "$pref" &>/dev/null; then
        echo "$pref"; return
    fi
    echo "bash"   # pure-bash always works
}
TUI_BACKEND="$(_tui_detect_backend)"

# ── Confirm prompt (y/n) ──────────────────────────────────────────────────────
tui_confirm() {
    local prompt="${1:-Are you sure?}" default="${2:-y}"
    local hint="[Y/n]"; [[ "$default" == "n" ]] && hint="[y/N]"
    printf "\n  ${TEAL}?${RESET}  ${BOLD}%s${RESET} ${DIM}%s${RESET} " "$prompt" "$hint" >&2
    local reply
    if [[ -t 0 ]]; then
        IFS= read -r reply
    else
        IFS= read -r reply </dev/tty
    fi
    reply="${reply:-$default}"
    [[ "${reply,,}" =~ ^y ]]
}

# ── Simple labelled prompt ────────────────────────────────────────────────────
tui_read() {
    local prompt="$1" default="${2:-}"
    printf "  ${TEAL}?${RESET}  ${BOLD}%s${RESET}${DIM}%s${RESET}: " \
        "$prompt" "${default:+ [$default]}" >&2
    local reply
    IFS= read -r reply </dev/tty
    printf '%s' "${reply:-$default}"
}

# =============================================================================
# ── Pure-bash arrow-key multi-select ─────────────────────────────────────────
# Writes space-separated tool list to global _tui_out_file
# =============================================================================
_tui_bash() {
    local -n _grps="$1"

    # ── Pre-compute install status cache (run command -v ONCE per tool) ───────
    declare -A _install_cache=()
    local _cat _tool
    for _cat in "${!_grps[@]}"; do
        for _tool in ${_grps[$_cat]}; do
            local _cmd="$_tool"
            case "$_tool" in
                awscli) _cmd="aws" ;; azure) _cmd="az" ;; ripgrep) _cmd="rg" ;;
                neovim) _cmd="nvim" ;; postgresql) _cmd="psql" ;; golang) _cmd="go" ;;
                mysql) _cmd="mysql" ;; phpfpm) _cmd="php-fpm" ;;
            esac
            if [[ "$_tool" == "nvm" ]]; then
                [[ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]] && _install_cache[$_tool]=1 || _install_cache[$_tool]=0
            elif command -v "$_cmd" &>/dev/null; then
                _install_cache[$_tool]=1
            else
                _install_cache[$_tool]=0
            fi
        done
    done

    # Build flat list
    local -a items=() labels=()
    local -a sorted_cats=()
    mapfile -t sorted_cats < <(printf '%s\n' "${!_grps[@]}" | sort)

    declare -A _CC=(
        [DevOps]="$TEAL"    [IaC]="$ORANGE"    [Cloud]="$INDIGO"
        [WebServer]="$LIME" [PHP]="$LAVENDER"  [Database]="$CORAL"
        [Languages]="$YELLOW" [VCS]="$BCYAN"   [Utils]="$PINK"
    )
    declare -A _CI=(
        [DevOps]="⎈" [IaC]="⛌" [Cloud]="☁" [WebServer]="▶" [PHP]="λ"
        [Database]="▣" [Languages]="◇" [VCS]="⑂" [Utils]="⚒"
    )

    local _cat_tool_count=0
    for cat in "${sorted_cats[@]}"; do
        items+=(""); labels+=("__SEP__:${_CC[$cat]:-$TEAL}:${_CI[$cat]:->} $cat")
        for tool in ${_grps[$cat]}; do
            items+=("$tool"); labels+=("$tool")
            (( _cat_tool_count++ ))
        done
    done

    local total="${#items[@]}"
    local -a selected=()
    local cursor=1 scroll=0
    local ROWS; ROWS=$(( $(tput lines 2>/dev/null || echo 24) - 8 ))
    (( ROWS < 6 )) && ROWS=6

    # Save terminal state and switch to raw mode
    local OLD_STTY; OLD_STTY="$(stty -g 2>/dev/null)"
    stty -echo -icanon min 1 time 0 2>/dev/null
    tput civis 2>/dev/null

    _is_sep()  { [[ "${labels[$1]:-}" == __SEP__* ]]; }
    _is_sel()  { local i; for i in "${selected[@]}"; do [[ "$i" == "$1" ]] && return 0; done; return 1; }
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

    # Page up/down helpers
    _page_down() {
        local jump=$(( ROWS / 2 ))
        local i; for (( i=0; i<jump; i++ )); do _next; done
    }
    _page_up() {
        local jump=$(( ROWS / 2 ))
        local i; for (( i=0; i<jump; i++ )); do _prev; done
    }

    # Select/deselect all in current category
    _toggle_category() {
        # Find the category of cursor position
        local ci="$cursor" sep_idx=-1
        while (( ci >= 0 )); do
            if _is_sep "$ci"; then sep_idx=$ci; break; fi
            (( ci-- ))
        done
        (( sep_idx < 0 )) && return

        # Find all tools in this category (between this sep and next sep/end)
        local -a cat_indices=()
        local j=$(( sep_idx + 1 ))
        while (( j < total )) && ! _is_sep "$j"; do
            cat_indices+=("$j")
            (( j++ ))
        done

        # If all are selected, deselect all. Otherwise, select all.
        local all_sel=true
        for idx in "${cat_indices[@]}"; do
            _is_sel "$idx" || { all_sel=false; break; }
        done

        if [[ "$all_sel" == "true" ]]; then
            # Deselect all in category
            for idx in "${cat_indices[@]}"; do
                local new=()
                local i; for i in "${selected[@]}"; do [[ "$i" != "$idx" ]] && new+=("$i"); done
                selected=("${new[@]}")
            done
        else
            # Select all in category
            for idx in "${cat_indices[@]}"; do
                _is_sel "$idx" || selected+=("$idx")
            done
        fi
    }

    _draw() {
        printf '\033[H\033[2J' >&2   # clear screen
        printf "${INDIGO}${BOLD}  ╔══════════════════════════════════════════════════╗\n" >&2
        printf "  ║   ${BWHITE}devsetup — Select Tools to Install${INDIGO}           ║\n" >&2
        printf "  ╚══════════════════════════════════════════════════╝${RESET}\n" >&2
        printf "  ${DIM}↑/↓ move  Space select  Enter confirm  a=all  n=none  q=quit${RESET}\n" >&2
        printf "  ${DIM}c=toggle category  PgUp/PgDn scroll  /=search${RESET}\n\n" >&2

        local end=$(( scroll + ROWS ))
        (( end > total )) && end=$total

        local idx
        for (( idx = scroll; idx < end; idx++ )); do
            if _is_sep "$idx"; then
                local si="${labels[$idx]#__SEP__:}"
                local sc="${si%%:*}" sl="${si#*:}"
                printf "  ${sc}${BOLD} ▸ %-28s${RESET}\n" "$sl" >&2
            else
                local t="${items[$idx]}"
                local mark="${DIM}[ ]${RESET}"
                _is_sel "$idx" && mark="${BGREEN}[${ICON_OK}]${RESET}"
                local cur="   "
                [[ "$idx" == "$cursor" ]] && cur="${ORANGE}❯  ${RESET}"
                # Use the pre-computed cache instead of command -v on every draw
                if [[ "${_install_cache[$t]:-0}" == "1" ]]; then
                    printf "  %s%s ${BOLD}%-16s${RESET}  ${DIM}✔ installed${RESET}\n" \
                        "$cur" "$mark" "$t" >&2
                else
                    printf "  %s%s %-16s\n" "$cur" "$mark" "$t" >&2
                fi
            fi
        done

        local sel_installed=0 sel_new=0
        for sidx in "${selected[@]}"; do
            local st="${items[$sidx]:-}"
            [[ -z "$st" ]] && continue
            [[ "${_install_cache[$st]:-0}" == "1" ]] && (( sel_installed++ )) || (( sel_new++ ))
        done

        (( total > ROWS )) && \
            printf "\n  ${DIM}[ %d–%d of %d tools ]${RESET}" "$((scroll+1))" "$end" "$_cat_tool_count" >&2
        printf "\n  ${TEAL}${BOLD}%d selected${RESET}" "${#selected[@]}" >&2
        (( sel_new > 0 )) && printf "  ${GREEN}(%d new)${RESET}" "$sel_new" >&2
        (( sel_installed > 0 )) && printf "  ${DIM}(%d reinstall)${RESET}" "$sel_installed" >&2
        printf "\n" >&2
    }

    # Main event loop
    while true; do
        while (( cursor < scroll        )); do (( scroll-- )); done
        while (( cursor >= scroll+ROWS  )); do (( scroll++ )); done
        _draw

        local key="" esc="" extra=""
        IFS= read -r -s -n1 key </dev/tty
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -r -s -n1 -t0.1 esc </dev/tty
            if [[ "$esc" == "[" ]]; then
                IFS= read -r -s -n1 -t0.1 key </dev/tty
                case "$key" in
                    A) _prev ;;              # Up arrow
                    B) _next ;;              # Down arrow
                    5) # Page Up
                       IFS= read -r -s -n1 -t0.1 extra </dev/tty  # consume ~
                       _page_up ;;
                    6) # Page Down
                       IFS= read -r -s -n1 -t0.1 extra </dev/tty  # consume ~
                       _page_down ;;
                    H) cursor=1; while _is_sep "$cursor" && (( cursor < total )); do (( cursor++ )); done ;;  # Home
                    F) cursor=$(( total - 1 )); while _is_sep "$cursor" && (( cursor > 0 )); do (( cursor-- )); done ;;  # End
                esac
            elif [[ -z "$esc" ]]; then
                # Plain Escape key (no follow-up) → quit
                stty "$OLD_STTY" 2>/dev/null; tput cnorm 2>/dev/null
                printf '\033[H\033[2J' >&2
                return 1
            fi
        else
            case "$key" in
                " ")   _toggle "$cursor" ;;
                "")    break ;;      # Enter
                j|J)   _next ;;
                k|K)   _prev ;;
                c|C)   _toggle_category ;;
                a|A)
                    selected=()
                    local i; for (( i=0; i<total; i++ )); do
                        _is_sep "$i" || selected+=("$i")
                    done ;;
                n|N)   selected=() ;;
                q|Q)
                    stty "$OLD_STTY" 2>/dev/null; tput cnorm 2>/dev/null
                    printf '\033[H\033[2J' >&2
                    return 1 ;;
            esac
        fi
    done

    # Restore terminal
    stty "$OLD_STTY" 2>/dev/null; tput cnorm 2>/dev/null
    printf '\033[H\033[2J' >&2

    # Write result to output file
    local -a result=()
    local idx
    for idx in "${selected[@]}"; do
        [[ -n "${items[$idx]:-}" ]] && result+=("${items[$idx]}")
    done
    printf '%s\n' "${result[*]}" > "$_tui_out_file"
}

# =============================================================================
# ── whiptail backend ──────────────────────────────────────────────────────────
# =============================================================================
_tui_whiptail() {
    local -n _g="$1"
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
        --checklist "Space=toggle  Enter=confirm  Esc=cancel:" \
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
    local -n _g="$1"
    local -a args=() sorted_cats=()
    mapfile -t sorted_cats < <(printf '%s\n' "${!_g[@]}" | sort)
    for cat in "${sorted_cats[@]}"; do
        args+=("--- [$cat] ---" "" "off")
        for tool in ${_g[$cat]}; do
            local state="off"
            command -v "$tool" &>/dev/null && state="on"
            args+=("$tool" "$cat" "$state")
        done
    done
    local _tmp; _tmp="$(mktemp)"
    dialog --title "devsetup — Tool Selector" \
        --checklist "Space to toggle, Enter to confirm:" \
        30 65 20 "${args[@]}" 2>"$_tmp"
    local rc=$?
    if [[ $rc -eq 0 ]]; then
        tr -d '"' < "$_tmp" | tr ' ' '\n' | grep -v '^---' | grep -v '^\[' \
            | tr '\n' ' ' > "$_tui_out_file"
    fi
    rm -f "$_tmp"
    return $rc
}

# =============================================================================
# ── fzf backend ───────────────────────────────────────────────────────────────
# =============================================================================
_tui_fzf() {
    local -n _g="$1"
    local -a all=() sorted_cats=()
    mapfile -t sorted_cats < <(printf '%s\n' "${!_g[@]}" | sort)
    for cat in "${sorted_cats[@]}"; do
        for tool in ${_g[$cat]}; do
            local mark=""
            command -v "$tool" &>/dev/null && mark=" ✔"
            all+=("$(printf '%-12s  %-20s%s' "[$cat]" "$tool" "$mark")")
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
# ── Public: tui_select_tools  ASSOC_VAR_NAME ─────────────────────────────────
# Sets $_tui_out_file (caller must declare it beforehand)
# Returns 0 if something selected, 1 if cancelled/empty
# =============================================================================
tui_select_tools() {
    local var_name="$1"
    : > "$_tui_out_file"   # truncate

    case "$TUI_BACKEND" in
        whiptail) _tui_whiptail "$var_name" ;;
        dialog)   _tui_dialog   "$var_name" ;;
        fzf)      _tui_fzf      "$var_name" ;;
        bash)     _tui_bash     "$var_name" ;;
    esac

    local result; result="$(cat "$_tui_out_file" 2>/dev/null || echo '')"
    result="${result// /}"   # check if empty after stripping spaces
    [[ -n "$result" ]]
}
