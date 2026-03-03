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

<<<<<<< HEAD
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
=======
    # ── Build flat item list ──────────────────────────────────────────────────
    local -a items=() labels=() sep_colors=()
    local total cursor=1 scroll=0
>>>>>>> refs/remotes/origin/main

    # Category colours/icons
    declare -A _CC=(
        [DevOps]="$TEAL"    [IaC]="$ORANGE"    [Cloud]="$INDIGO"
        [WebServer]="$LIME" [PHP]="$LAVENDER"  [Database]="$CORAL"
        [Languages]="$YELLOW" [VCS]="$BCYAN"   [Utils]="$PINK"
    )
<<<<<<< HEAD
    declare -A _CI=(
        [DevOps]="⎈" [IaC]="⛌" [Cloud]="☁" [WebServer]="▶" [PHP]="λ"
        [Database]="▣" [Languages]="◇" [VCS]="⑂" [Utils]="⚒"
    )

    local _cat_tool_count=0
=======

    local -a sorted_cats=()
    mapfile -t sorted_cats < <(printf '%s\n' "${!_grps[@]}" | sort)

    # Pre-compute installed status — avoids repeated command -v on every redraw
    declare -A _installed=()
>>>>>>> refs/remotes/origin/main
    for cat in "${sorted_cats[@]}"; do
        for tool in ${_grps[$cat]}; do
<<<<<<< HEAD
            items+=("$tool"); labels+=("$tool")
            (( _cat_tool_count++ ))
=======
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
>>>>>>> refs/remotes/origin/main
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

<<<<<<< HEAD
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
=======
    # ── Draw entire TUI ───────────────────────────────────────────────────────
    _draw() {
        # Move cursor to top-left and clear (faster than `clear`)
        printf '\033[H\033[2J\033[3J' >&2

        printf "${INDIGO}${BOLD}  ╔══════════════════════════════════════════════════╗\n" >&2
        printf "  ║   ${BWHITE}devsetup — Select Tools to Install${INDIGO}           ║\n" >&2
        printf "  ╚══════════════════════════════════════════════════╝${RESET}\n" >&2
        printf "  ${DIM}↑/↓ move   Space select   Enter confirm   a all   n none   q quit${RESET}\n\n" >&2
>>>>>>> refs/remotes/origin/main

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
<<<<<<< HEAD
                # Use the pre-computed cache instead of command -v on every draw
                if [[ "${_install_cache[$t]:-0}" == "1" ]]; then
                    printf "  %s%s ${BOLD}%-16s${RESET}  ${DIM}✔ installed${RESET}\n" \
=======
                if [[ "${_installed[$t]:-0}" == "1" ]]; then
                    printf "  %s%s ${BOLD}%-18s${RESET}  ${DIM}installed${RESET}\n" \
>>>>>>> refs/remotes/origin/main
                        "$cur" "$mark" "$t" >&2
                else
                    printf "  %s%s %-18s\n" "$cur" "$mark" "$t" >&2
                fi
            fi
        done

<<<<<<< HEAD
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
=======
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
>>>>>>> refs/remotes/origin/main
    }

    # ── Event loop ────────────────────────────────────────────────────────────
    while true; do
        # Keep cursor in scroll window
        while (( cursor < scroll       )); do (( scroll-- )); done
        while (( cursor >= scroll+ROWS )); do (( scroll++ )); done

        _draw

        local key="" esc="" extra=""
        IFS= read -r -s -n1 key </dev/tty
        if [[ "$key" == $'\x1b' ]]; then
            IFS= read -r -s -n1 -t0.1 esc </dev/tty
            if [[ "$esc" == "[" ]]; then
                IFS= read -r -s -n1 -t0.1 key </dev/tty
                case "$key" in
<<<<<<< HEAD
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
=======
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
>>>>>>> refs/remotes/origin/main
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
