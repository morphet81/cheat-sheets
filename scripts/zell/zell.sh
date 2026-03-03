#!/usr/bin/env bash
# Interactive zellij session manager with arrow-key navigation.
#
# Lists all zellij sessions. Navigate with arrow keys, Enter to attach,
# 'd' to delete (with confirmation), 'r' to rename, 'q' to quit.
#
# Usage:
#   zell.sh

set -euo pipefail

if ! command -v zellij &>/dev/null; then
    echo "Error: zellij is not installed or not in PATH." >&2
    exit 1
fi

# -- Colors --------------------------------------------------------------------

BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
CYAN='\033[36m'
GREEN='\033[32m'
RED='\033[31m'
MAGENTA='\033[35m'
WHITE='\033[97m'
BG_BLUE='\033[44m'

# -- Terminal helpers ----------------------------------------------------------

SAVED_TTY=""

hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }
clear_screen() { printf '\033[2J\033[H'; }

enter_raw_mode() {
    SAVED_TTY=$(stty -g)
    stty -echo -icanon min 1 time 0
}

exit_raw_mode() {
    if [[ -n "$SAVED_TTY" ]]; then
        stty "$SAVED_TTY"
        SAVED_TTY=""
    fi
}

cleanup() {
    show_cursor
    exit_raw_mode
}
trap cleanup EXIT

# -- Gather sessions -----------------------------------------------------------

gather_sessions() {
    SESSION_NAMES=()
    SESSION_STATUS=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Strip ANSI escape codes
        local clean
        clean=$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')
        local name
        name=$(printf '%s' "$clean" | awk '{print $1}')
        [[ -z "$name" ]] && continue

        local status="running"
        if printf '%s' "$clean" | grep -qi "exited"; then
            status="exited"
        elif printf '%s' "$clean" | grep -q "(current)"; then
            status="current"
        fi

        SESSION_NAMES+=("$name")
        SESSION_STATUS+=("$status")
    done < <(zellij list-sessions 2>/dev/null || true)

    COUNT=${#SESSION_NAMES[@]}
}

# -- Read a single keypress ----------------------------------------------------

read_key() {
    local char
    char=$(dd bs=1 count=1 2>/dev/null)

    if [[ "$char" == $'\x1b' ]]; then
        local c1 c2
        c1=$(dd bs=1 count=1 2>/dev/null)
        c2=$(dd bs=1 count=1 2>/dev/null)
        case "${c1}${c2}" in
            '[A') echo "UP" ;;
            '[B') echo "DOWN" ;;
            *)    echo "ESC" ;;
        esac
    elif [[ "$char" == "" ]]; then
        echo "ENTER"
    elif [[ "$char" == "q" || "$char" == "Q" ]]; then
        echo "QUIT"
    elif [[ "$char" == "d" || "$char" == "D" ]]; then
        echo "DELETE"
    elif [[ "$char" == "r" || "$char" == "R" ]]; then
        echo "RENAME"
    else
        echo "OTHER"
    fi
}

# -- Draw the session list -----------------------------------------------------

draw_list() {
    clear_screen

    printf "  ${BOLD}${CYAN}Zellij Sessions${RESET}\n"
    printf "  ${DIM}Use ${WHITE}↑↓${RESET}${DIM} to navigate · ${WHITE}Enter${RESET}${DIM} attach · ${WHITE}d${RESET}${DIM} delete · ${WHITE}r${RESET}${DIM} rename · ${WHITE}q${RESET}${DIM} quit${RESET}\n"
    echo

    printf "  ${DIM}%-40s  %s${RESET}\n" "Session" "Status"
    printf "  ${DIM}%-40s  %s${RESET}\n" "────────────────────────────────────────" "───────"

    for i in $(seq 0 $((COUNT - 1))); do
        local name="${SESSION_NAMES[$i]}"
        local status="${SESSION_STATUS[$i]}"
        local status_str status_color

        case "$status" in
            current)
                status_str="● current"
                status_color="$GREEN"
                ;;
            exited)
                status_str="○ exited"
                status_color="$DIM"
                ;;
            *)
                status_str="● running"
                status_color="$CYAN"
                ;;
        esac

        if [[ $i -eq "$SELECTED" ]]; then
            printf "  ${BG_BLUE}${BOLD}${WHITE}▸ %-38s  " "$name"
            printf "${status_color}%s${RESET}\n" "$status_str"
        else
            printf "   ${GREEN}%-38s  " "$name"
            printf "${status_color}%s${RESET}\n" "$status_str"
        fi
    done

    echo
}

# -- Attach to session ---------------------------------------------------------

attach_session() {
    local idx="$1"
    local name="${SESSION_NAMES[$idx]}"

    show_cursor
    exit_raw_mode
    clear_screen

    zellij attach "$name" || true

    gather_sessions
    [[ $COUNT -gt 0 && "$SELECTED" -ge "$COUNT" ]] && SELECTED=$((COUNT - 1))
    [[ $COUNT -eq 0 ]] && SELECTED=0

    enter_raw_mode
    hide_cursor
}

# -- Delete session with confirmation ------------------------------------------

delete_session() {
    local idx="$1"
    local name="${SESSION_NAMES[$idx]}"

    show_cursor
    exit_raw_mode
    clear_screen

    printf "\n  ${BOLD}${RED}Delete session${RESET}\n"
    printf "  ${DIM}Session:${RESET} %s\n\n" "$name"

    read -rp "  Delete this session? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        printf "  ${DIM}Aborted.${RESET}\n"
        sleep 0.5
        enter_raw_mode
        hide_cursor
        return
    fi

    if zellij delete-session "$name" 2>/dev/null; then
        printf "  ${GREEN}Session '${name}' deleted.${RESET}\n"
    else
        printf "  ${RED}Failed to delete session '${name}'.${RESET}\n"
        sleep 1
        enter_raw_mode
        hide_cursor
        return
    fi

    sleep 0.5

    gather_sessions
    [[ $COUNT -gt 0 && "$SELECTED" -ge "$COUNT" ]] && SELECTED=$((COUNT - 1))
    [[ $COUNT -eq 0 ]] && SELECTED=0

    enter_raw_mode
    hide_cursor
}

# -- Rename session ------------------------------------------------------------

rename_session() {
    local idx="$1"
    local old_name="${SESSION_NAMES[$idx]}"

    show_cursor
    exit_raw_mode
    clear_screen

    printf "\n  ${BOLD}${MAGENTA}Rename session${RESET}\n"
    printf "  ${DIM}Current name:${RESET} %s\n\n" "$old_name"

    read -rp "  New name: " new_name
    # Replace spaces with hyphens (zellij session names cannot contain spaces)
    new_name="${new_name// /-}"

    if [[ -z "$new_name" || "$new_name" == "$old_name" ]]; then
        printf "  ${DIM}Aborted.${RESET}\n"
        sleep 0.5
        enter_raw_mode
        hide_cursor
        return
    fi

    if zellij --session "$old_name" action rename-session "$new_name" 2>/dev/null; then
        printf "  ${GREEN}Session renamed to '${new_name}'.${RESET}\n"
    else
        printf "  ${RED}Failed to rename session.${RESET}\n"
        sleep 1
        enter_raw_mode
        hide_cursor
        return
    fi

    sleep 0.5

    gather_sessions
    # Keep selection on the renamed session
    SELECTED=0
    for i in $(seq 0 $((COUNT - 1))); do
        if [[ "${SESSION_NAMES[$i]}" == "$new_name" ]]; then
            SELECTED=$i
            break
        fi
    done

    enter_raw_mode
    hide_cursor
}

# -- Main loop -----------------------------------------------------------------

gather_sessions

if [[ $COUNT -eq 0 ]]; then
    echo "No active zellij sessions found."
    exit 0
fi

SELECTED=0
enter_raw_mode
hide_cursor

while true; do
    draw_list

    key=$(read_key)
    case "$key" in
        UP)
            [[ $SELECTED -gt 0 ]] && SELECTED=$((SELECTED - 1))
            ;;
        DOWN)
            [[ $SELECTED -lt $((COUNT - 1)) ]] && SELECTED=$((SELECTED + 1))
            ;;
        ENTER)
            attach_session "$SELECTED"
            [[ $COUNT -eq 0 ]] && { clear_screen; printf "\n  ${DIM}No sessions remaining.${RESET}\n"; break; }
            ;;
        DELETE)
            delete_session "$SELECTED"
            [[ $COUNT -eq 0 ]] && { clear_screen; printf "\n  ${DIM}No sessions remaining.${RESET}\n"; break; }
            ;;
        RENAME)
            rename_session "$SELECTED"
            ;;
        QUIT|ESC)
            clear_screen
            break
            ;;
    esac
done
