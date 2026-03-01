#!/usr/bin/env bash
# =============================================================================
# lib/tui.sh — Interactive TUI menu (whiptail → dialog → fzf → plain fallback)
# =============================================================================
# Provides a grouped checklist menu for tool selection, with auto-detection of
# the best available TUI backend.
# =============================================================================

# ── Backend detection ─────────────────────────────────────────────────────────
_tui_backend() {
    if command -v whiptail &>/dev/null; then echo "whiptail"
    elif command -v dialog  &>/dev/null; then echo "dialog"
    elif command -v fzf     &>/dev/null; then echo "fzf"
    else                                       echo "plain"
    fi
}

# ── Terminal dimensions ───────────────────────────────────────────────────────
_term_height() { tput lines  2>/dev/null || echo 24; }
_term_width()  { tput cols   2>/dev/null || echo 80; }

# =============================================================================
# ── whiptail / dialog backend ─────────────────────────────────────────────────
# =============================================================================

# Build whiptail/dialog checklist items from a groups array.
# groups[category]="tool1 tool2 tool3"
_build_checklist_items() {
    declare -n _groups="$1"   # nameref to associative array

    local items=()
    for category in "${!_groups[@]}"; do
        local tools_in_cat="${_groups[$category]}"
        for tool in $tools_in_cat; do
            items+=("$tool" "[$category]" "OFF")
        done
    done
    echo "${items[@]}"
}

_show_whiptail_menu() {
    declare -n _groups_wt="$1"
    local title="${2:-DevSetup — Select Tools to Install}"

    local h; h="$(_term_height)"
    local w; w="$(_term_width)"
    local list_h=$(( h - 10 ))

    local items=()
    for category in "${!_groups_wt[@]}"; do
        for tool in ${_groups_wt[$category]}; do
            items+=("$tool" "[$category]" "OFF")
        done
    done

    local RESULT
    RESULT=$(whiptail --title "$title" \
        --checklist "Space=toggle  Enter=confirm  Tab=buttons" \
        "$h" "$w" "$list_h" \
        "${items[@]}" \
        3>&1 1>&2 2>&3)
    local exit_code=$?
    [[ $exit_code -ne 0 ]] && return 1

    # Strip quotes from whiptail output
    echo "$RESULT" | tr -d '"'
}

_show_dialog_menu() {
    declare -n _groups_dlg="$1"
    local title="${2:-DevSetup — Select Tools to Install}"

    local h; h="$(_term_height)"
    local w; w="$(_term_width)"
    local list_h=$(( h - 10 ))

    local items=()
    for category in "${!_groups_dlg[@]}"; do
        for tool in ${_groups_dlg[$category]}; do
            items+=("$tool" "[$category]" "off")
        done
    done

    local RESULT
    RESULT=$(dialog --title "$title" \
        --checklist "Space=toggle  Enter=confirm" \
        "$h" "$w" "$list_h" \
        "${items[@]}" \
        2>&1 >/dev/tty)
    local exit_code=$?
    [[ $exit_code -ne 0 ]] && return 1
    echo "$RESULT"
}

# =============================================================================
# ── fzf backend ──────────────────────────────────────────────────────────────
# =============================================================================

_show_fzf_menu() {
    declare -n _groups_fzf="$1"

    # Build flat list with category prefix
    local flat_list=()
    for category in "${!_groups_fzf[@]}"; do
        for tool in ${_groups_fzf[$category]}; do
            flat_list+=("[$category] $tool")
        done
    done

    local RESULT
    RESULT=$(printf '%s\n' "${flat_list[@]}" \
        | fzf --multi \
              --prompt=" Select tools (TAB=toggle, ENTER=confirm): " \
              --header="DevSetup — Use TAB to select multiple tools" \
              --border --height=80% \
              --color='hl:bold:yellow,hl+:bold:yellow,marker:green' \
        | awk '{print $NF}')   # extract just the tool name

    [[ -z "$RESULT" ]] && return 1
    echo "$RESULT"
}

# =============================================================================
# ── Plain text fallback ───────────────────────────────────────────────────────
# =============================================================================

_show_plain_menu() {
    declare -n _groups_plain="$1"

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║         DevSetup — Select Tools to Install       ║"
    echo "╠══════════════════════════════════════════════════╣"

    local all_tools=()
    local idx=1
    for category in "${!_groups_plain[@]}"; do
        echo "║  ── $category"
        for tool in ${_groups_plain[$category]}; do
            printf "║    %2d) %-40s║\n" "$idx" "$tool"
            all_tools+=("$tool")
            ((idx++))
        done
    done
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "  Enter numbers separated by spaces (e.g. 1 3 5), or 'all' or 'none':"
    read -rp "  > " choices

    if [[ "${choices,,}" == "all" ]]; then
        echo "${all_tools[*]}"
        return 0
    elif [[ "${choices,,}" == "none" || -z "$choices" ]]; then
        return 1
    fi

    local selected=()
    for num in $choices; do
        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#all_tools[@]} )); then
            selected+=("${all_tools[$((num-1))]}")
        fi
    done
    echo "${selected[*]}"
}

# =============================================================================
# ── Public: show the tool selection menu ─────────────────────────────────────
# =============================================================================
# Usage:
#   declare -A TOOL_GROUPS
#   TOOL_GROUPS[DevOps]="docker kubectl helm terraform"
#   TOOL_GROUPS[Cloud]="awscli"
#   TOOL_GROUPS[Languages]="nvm python"
#   selected="$(tui_select_tools TOOL_GROUPS)"

tui_select_tools() {
    local groups_var="$1"
    local title="${2:-DevSetup — Select Tools to Install}"
    local backend; backend="$(_tui_backend)"

    case "$backend" in
        whiptail) _show_whiptail_menu "$groups_var" "$title" ;;
        dialog)   _show_dialog_menu   "$groups_var" "$title" ;;
        fzf)      _show_fzf_menu      "$groups_var" ;;
        plain)    _show_plain_menu    "$groups_var" ;;
    esac
}

# =============================================================================
# ── Progress bar ─────────────────────────────────────────────────────────────
# =============================================================================

# Show a whiptail/dialog gauge for a list of steps executed by a function.
# Usage: tui_progress_gauge "Installing tools" _my_install_function
tui_progress_gauge() {
    local title="$1"; shift
    local func="$1"; shift
    local backend; backend="$(_tui_backend)"
    local h; h="$(_term_height)"
    local w; w="$(_term_width)"

    case "$backend" in
        whiptail|dialog)
            (
                local step=0
                local total="${1:-10}"
                while read -r line; do
                    ((step++))
                    local pct=$(( step * 100 / total ))
                    echo "$pct"
                    echo "XXX"
                    echo "$line"
                    echo "XXX"
                done < <("$func" "$@" 2>&1)
            ) | "$backend" --gauge "$title" "$h" "$w" 0
            ;;
        *)
            "$func" "$@"
            ;;
    esac
}

# =============================================================================
# ── Confirmation dialog ───────────────────────────────────────────────────────
# =============================================================================

# Returns 0 if user says yes, 1 if no.
tui_confirm() {
    local msg="${1:-Are you sure?}"
    local backend; backend="$(_tui_backend)"
    local h; h="$(_term_height)"
    local w; w="$(_term_width)"

    case "$backend" in
        whiptail) whiptail --yesno "$msg" 10 60 ;;
        dialog)   dialog  --yesno "$msg" 10 60 ;;
        *)
            read -rp "$msg [y/N]: " ans
            [[ "${ans,,}" == "y" ]]
            ;;
    esac
}
