#!/usr/bin/env bash
# =============================================================================
# lib/tui.sh — Pure-bash interactive TUI (arrow keys, toggle, confirm)
#   Fallback chain: whiptail → dialog → fzf → pure-bash (always works)
# =============================================================================

# ── Detect available TUI backends ────────────────────────────────────────────
_tui_backend() {
    if   command -v whiptail &>/dev/null; then echo "whiptail"
    elif command -v dialog   &>/dev/null; then echo "dialog"
    elif command -v fzf      &>/dev/null; then echo "fzf"
    else                                       echo "bash"
    fi
}

TUI_BACKEND="$(_tui_backend)"

# ── Confirm prompt ────────────────────────────────────────────────────────────
tui_confirm() {
    local prompt="${1:-Are you sure?}"
    local default="${2:-y}"   # y or n

    case "$TUI_BACKEND" in
        whiptail)
            if whiptail --yesno "$prompt" 8 60 2>/dev/null; then return 0
            else return 1; fi
            ;;
        dialog)
            if dialog --yesno "$prompt" 8 60 2>/dev/null; then return 0
            else return 1; fi
            ;;
        *)
            local hint="[Y/n]"; [[ "$default" == "n" ]] && hint="[y/N]"
            printf "\n  ${TEAL}?${RESET}  ${BOLD}%s${RESET} ${DIM}%s${RESET} " "$prompt" "$hint" >&2
            local reply; IFS= read -r reply </dev/tty
            reply="${reply:-$default}"
            [[ "${reply,,}" =~ ^y ]]
            ;;
    esac
}

# ── Pure-bash arrow-key multi-select ─────────────────────────────────────────
# tui_bash_select ASSOC_VAR_NAME  →  prints "tool1 tool2 ..." to stdout
tui_bash_select() {
    local -n _grps="$1"

    # Build flat ordered list: (display_line  tool_name  category  is_separator)
    local -a items=()        # "tool_name" or "" for separators
    local -a labels=()       # display strings

    # Sort categories
    local sorted_cats=()
    IFS=$'\n' read -ra sorted_cats <<< "$(printf '%s\n' "${!_grps[@]}" | sort)"

    local -A CAT_COLORS=(
        [DevOps]="$TEAL"  [IaC]="$ORANGE"   [Cloud]="$INDIGO"    [WebServer]="$LIME"
        [PHP]="$LAVENDER" [Database]="$CORAL" [Languages]="$YELLOW" [VCS]="$BCYAN"
        [Utils]="$PINK"
    )
    local -A CAT_ICONS=(
        [DevOps]="⎈" [IaC]="⛌" [Cloud]="☁" [WebServer]="🌐" [PHP]="λ"
        [Database]="▣" [Languages]="⟨/⟩" [VCS]="⑂" [Utils]="⚒"
    )

    for cat in "${sorted_cats[@]}"; do
        # separator
        items+=("")
        labels+=("__SEP__:${CAT_COLORS[$cat]:-$TEAL}:${CAT_ICONS[$cat]:-·} ${cat}")
        for tool in ${_grps[$cat]}; do
            items+=("$tool")
            labels+=("$tool")
        done
    done

    local total="${#items[@]}"
    local -a selected=()   # indices that are toggled on
    local cursor=1         # skip first separator
    local scroll=0
    local ROWS; ROWS=$(( $(tput lines 2>/dev/null || echo 24) - 8 ))
    (( ROWS < 5 )) && ROWS=5

    # Restore terminal on exit
    local OLD_STTY; OLD_STTY=$(stty -g 2>/dev/null)
    stty -echo -icanon min 1 time 0 2>/dev/null
    tput civis 2>/dev/null   # hide cursor
    trap 'stty '"$OLD_STTY"' 2>/dev/null; tput cnorm 2>/dev/null' RETURN INT TERM

    _is_sep()      { [[ "${labels[$1]:-}" == __SEP__* ]]; }
    _is_selected() { local i; for i in "${selected[@]}"; do [[ "$i" == "$1" ]] && return 0; done; return 1; }
    _toggle() {
        _is_sep "$1" && return
        local i new=()
        if _is_selected "$1"; then
            for i in "${selected[@]}"; do [[ "$i" != "$1" ]] && new+=("$i"); done
            selected=("${new[@]}")
        else
            selected+=("$1")
        fi
    }

    _render() {
        # Clear and redraw
        clear >&2

        printf "${INDIGO}${BOLD}" >&2
        printf "  ╔══════════════════════════════════════════════════════════╗\n" >&2
        printf "  ║        ${BWHITE}devsetup — Tool Selector${INDIGO}                        ║\n" >&2
        printf "  ╚══════════════════════════════════════════════════════════╝${RESET}\n" >&2
        printf "  ${DIM}↑↓ navigate   Space toggle   Enter confirm   a all   q quit${RESET}\n\n" >&2

        local end=$(( scroll + ROWS ))
        (( end > total )) && end=$total
        local idx
        for (( idx = scroll; idx < end; idx++ )); do
            if _is_sep "$idx"; then
                local sep_info="${labels[$idx]#__SEP__:}"
                local sep_color="${sep_info%%:*}"
                local sep_label="${sep_info#*:}"
                printf "  ${sep_color}${BOLD}▸ %-28s${RESET}\n" "$sep_label" >&2
            else
                local tool="${items[$idx]}"
                local sel_mark="${DIM}[ ]${RESET}"
                _is_selected "$idx" && sel_mark="${BGREEN}[${ICON_OK}]${RESET}"
                local cursor_mark="  "
                [[ "$idx" == "$cursor" ]] && cursor_mark="${ORANGE}❯ ${RESET}"
                if command -v "$tool" &>/dev/null; then
                    printf "  %s%s ${tool}  ${DIM}✔ installed${RESET}\n" \
                        "$cursor_mark" "$sel_mark" >&2
                else
                    printf "  %s%s ${tool}\n" "$cursor_mark" "$sel_mark" >&2
                fi
            fi
        done

        # Scroll indicator
        (( total > ROWS )) && printf "\n  ${DIM}showing %d-%d of %d${RESET}\n" \
            "$scroll" "$end" "$total" >&2

        # Selected summary
        local sel_count="${#selected[@]}"
        printf "\n  ${TEAL}${BOLD}%d tool(s) selected${RESET}\n" "$sel_count" >&2
    }

    _next_non_sep() {
        local i=$(( cursor + 1 ))
        while (( i < total )); do
            _is_sep "$i" || { cursor=$i; return; }
            (( i++ ))
        done
    }
    _prev_non_sep() {
        local i=$(( cursor - 1 ))
        while (( i >= 0 )); do
            _is_sep "$i" || { cursor=$i; return; }
            (( i-- ))
        done
    }

    while true; do
        # Adjust scroll window
        while (( cursor < scroll )); do (( scroll-- )); done
        while (( cursor >= scroll + ROWS )); do (( scroll++ )); done

        _render

        # Read a key (handle escape sequences for arrows)
        local key esc
        IFS= read -r -s -n1 key </dev/tty
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -r -s -n1 -t 0.1 esc </dev/tty
            if [[ "$esc" == "[" ]]; then
                IFS= read -r -s -n1 -t 0.1 key </dev/tty
                case "$key" in
                    A) _prev_non_sep ;;   # Up
                    B) _next_non_sep ;;   # Down
                    5) (( scroll -= ROWS/2 < 0 ? 0 : ROWS/2 )) ;;  # PgUp
                    6) (( scroll += ROWS/2 )) ;;                     # PgDown
                esac
            fi
        else
            case "$key" in
                " ") _toggle "$cursor" ;;  # Space = toggle
                "") # Enter = confirm
                    break ;;
                k|K) _prev_non_sep ;;
                j|J) _next_non_sep ;;
                a|A)  # Select all
                    selected=()
                    local i; for (( i=0; i<total; i++ )); do
                        _is_sep "$i" || selected+=("$i")
                    done
                    ;;
                n|N)  # Select none
                    selected=() ;;
                q|Q)   # Quit
                    stty "$OLD_STTY" 2>/dev/null; tput cnorm 2>/dev/null
                    clear >&2; return 1
                    ;;
            esac
        fi
    done

    stty "$OLD_STTY" 2>/dev/null; tput cnorm 2>/dev/null; clear >&2

    # Return selected tool names
    local -a result=()
    for idx in "${selected[@]}"; do
        [[ -n "${items[$idx]}" ]] && result+=("${items[$idx]}")
    done
    echo "${result[*]}"
}

# ── Main TUI selector: writes result to stdout (for pipeline use) ─────────────
tui_select_tools() {
    local -n _g="$1"

    case "$TUI_BACKEND" in
        whiptail|dialog)
            local args=() sorted_cats=()
            IFS=$'\n' read -ra sorted_cats <<< "$(printf '%s\n' "${!_g[@]}" | sort)"
            for cat in "${sorted_cats[@]}"; do
                args+=("--- [${cat}] ---" "" "OFF")
                for tool in ${_g[$cat]}; do args+=("$tool" "$cat" "OFF"); done
            done
            local selected
            if [[ "$TUI_BACKEND" == "whiptail" ]]; then
                selected=$(whiptail --title "devsetup — Tool Selector" \
                    --checklist "Space to toggle, Enter to confirm:" \
                    30 65 20 "${args[@]}" 3>&1 1>&2 2>&3)
            else
                selected=$(dialog --title "devsetup — Tool Selector" \
                    --checklist "Space to toggle, Enter to confirm:" \
                    30 65 20 "${args[@]}" 2>&1 >/dev/tty)
            fi
            [[ -z "$selected" ]] && return 1
            # strip category separators and quotes
            echo "$selected" | tr -d '"' | tr ' ' '\n' \
                | grep -v '^---' | grep -v '^\[' | tr '\n' ' '
            ;;
        fzf)
            local -a all_tools=()
            local sorted_cats=()
            IFS=$'\n' read -ra sorted_cats <<< "$(printf '%s\n' "${!_g[@]}" | sort)"
            for cat in "${sorted_cats[@]}"; do
                for tool in ${_g[$cat]}; do
                    all_tools+=("$(printf '%-12s  %s' "[$cat]" "$tool")")
                done
            done
            printf '%s\n' "${all_tools[@]}" \
                | fzf --multi \
                      --prompt="  Search tools > " \
                      --header="devsetup  |  Tab/Space select  ·  Enter confirm  ·  Esc cancel" \
                      --height=90% --border=rounded --layout=reverse \
                      --color='header:italic,border:blue' \
                | awk '{print $NF}' | tr '\n' ' ' || return 1
            ;;
        bash)
            tui_bash_select "$1"
            ;;
    esac
}

# ── TUI selector that writes result to a file (avoids subshell redirect issues) ──
# This is what run_interactive uses so the TUI renders properly on screen.
tui_select_tools_to_file() {
    local var_name="$1"
    local out_file="$2"

    case "$TUI_BACKEND" in
        whiptail|dialog|fzf)
            # These write to /dev/tty themselves — safe to capture stdout
            local result; result="$(tui_select_tools "$var_name")" || return 1
            echo "$result" > "$out_file"
            ;;
        bash)
            # Pure-bash TUI renders on >&2; result on stdout — safe to capture
            local result; result="$(tui_bash_select "$var_name")" || return 1
            echo "$result" > "$out_file"
            ;;
    esac
}

# ── Simple read-from-tty ──────────────────────────────────────────────────────
tui_read() {
    local prompt="$1" default="${2:-}"
    printf "  ${TEAL}?${RESET}  ${BOLD}%s${RESET}${DIM}%s${RESET}: " \
        "$prompt" "${default:+ [$default]}" >&2
    local reply; IFS= read -r reply </dev/tty
    echo "${reply:-$default}"
}
