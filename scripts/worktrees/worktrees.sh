#!/usr/bin/env bash
# Interactive git worktree manager with arrow-key navigation.
#
# Lists all worktrees with color. Navigate with arrow keys, Enter to inspect,
# 'd' to remove, 'q' to quit.
#
# Usage:
#   worktrees.sh

set -euo pipefail

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository." >&2
    exit 1
fi

# -- Colors --------------------------------------------------------------------

BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
WHITE='\033[97m'
BG_BLUE='\033[44m'
BG_RESET='\033[49m'

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

# Restore terminal on exit
cleanup() {
    show_cursor
    exit_raw_mode
}
trap cleanup EXIT

# -- Gather worktrees ----------------------------------------------------------

gather_worktrees() {
    WT_PATHS=()
    WT_BRANCHES=()
    WT_COMMITS=()
    WT_BARE=()

    local current_path="" current_branch="" current_commit="" is_bare=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
            if [[ -n "$current_path" ]]; then
                WT_PATHS+=("$current_path")
                WT_BRANCHES+=("${current_branch:-(detached)}")
                WT_COMMITS+=("$current_commit")
                WT_BARE+=("$is_bare")
            fi
            current_path="${BASH_REMATCH[1]}"
            current_branch=""
            current_commit=""
            is_bare=false
        elif [[ "$line" =~ ^HEAD\ (.+)$ ]]; then
            current_commit="${BASH_REMATCH[1]:0:8}"
        elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]]; then
            current_branch="${BASH_REMATCH[1]}"
        elif [[ "$line" == "bare" ]]; then
            is_bare=true
        elif [[ "$line" == "detached" ]]; then
            current_branch="(detached)"
        fi
    done < <(git worktree list --porcelain)

    if [[ -n "$current_path" ]]; then
        WT_PATHS+=("$current_path")
        WT_BRANCHES+=("${current_branch:-(detached)}")
        WT_COMMITS+=("$current_commit")
        WT_BARE+=("$is_bare")
    fi

    COUNT=${#WT_PATHS[@]}
}

# -- Read a single keypress ----------------------------------------------------

read_key() {
    local char
    # Read one byte at a time using dd (works reliably on macOS bash 3.2+)
    char=$(dd bs=1 count=1 2>/dev/null)

    if [[ "$char" == $'\x1b' ]]; then
        # Escape sequence — read next two bytes one at a time
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
    else
        echo "OTHER"
    fi
}

# -- Draw the worktree list ----------------------------------------------------

draw_list() {
    clear_screen

    printf "  ${BOLD}${CYAN}Git Worktrees${RESET}\n"
    printf "  ${DIM}Use ${WHITE}↑↓${RESET}${DIM} to navigate, ${WHITE}Enter${RESET}${DIM} to inspect, ${WHITE}d${RESET}${DIM} to remove, ${WHITE}q${RESET}${DIM} to quit${RESET}\n"
    echo

    printf "  ${DIM}%-30s  %-10s  %s${RESET}\n" "Branch" "Commit" "Path"
    printf "  ${DIM}%-30s  %-10s  %s${RESET}\n" "──────────────────────────────" "────────" "────"

    for i in $(seq 0 $((COUNT - 1))); do
        local branch="${WT_BRANCHES[$i]}"
        local commit="${WT_COMMITS[$i]}"
        local path="${WT_PATHS[$i]}"
        local tag=""

        if [[ $i -eq 0 ]]; then
            tag="${DIM} (main)${RESET}"
        elif [[ "${WT_BARE[$i]}" == "true" ]]; then
            tag="${DIM} (bare)${RESET}"
        fi

        if [[ $i -eq "$SELECTED" ]]; then
            printf "  ${BG_BLUE}${BOLD}${WHITE}▸ %-28s  ${YELLOW}%-10s${WHITE}  %s${RESET}${tag}\n" \
                "$branch" "$commit" "$path"
        else
            printf "  ${DIM} ${RESET} ${GREEN}%-28s  ${YELLOW}%-10s${RESET}  ${DIM}%s${RESET}${tag}\n" \
                "$branch" "$commit" "$path"
        fi
    done

    echo
}

# -- Show detail panel for selected worktree -----------------------------------

show_detail() {
    local idx="$1"
    local wt_path="${WT_PATHS[$idx]}"
    local wt_branch="${WT_BRANCHES[$idx]}"

    clear_screen

    printf "  ${BOLD}${MAGENTA}── ${wt_branch} ──${RESET}\n"
    printf "  ${DIM}Path:${RESET} %s\n" "$wt_path"
    echo

    if [[ -d "$wt_path" ]]; then
        local status_output
        status_output=$(git -C "$wt_path" status --short 2>/dev/null)

        printf "  ${BOLD}${CYAN}Status:${RESET}\n"
        if [[ -n "$status_output" ]]; then
            while IFS= read -r line; do
                local code="${line:0:2}"
                local file="${line:3}"
                case "$code" in
                    "M "*|" M") printf "    ${YELLOW}%s${RESET}  %s\n" "$code" "$file" ;;
                    "A "*|"??"*) printf "    ${GREEN}%s${RESET}  %s\n" "$code" "$file" ;;
                    "D "*|" D") printf "    ${RED}%s${RESET}  %s\n" "$code" "$file" ;;
                    *) printf "    ${DIM}%s${RESET}  %s\n" "$code" "$file" ;;
                esac
            done <<< "$status_output"
        else
            printf "    ${GREEN}Clean — nothing to commit${RESET}\n"
        fi

        echo
        printf "  ${BOLD}${CYAN}Recent commits:${RESET}\n"
        git -C "$wt_path" log --oneline -5 --format="    ${YELLOW}%h${RESET} %s" 2>/dev/null || true
    else
        printf "  ${RED}(directory not found — worktree may be prunable)${RESET}\n"
    fi

    echo
    if [[ $idx -eq 0 ]]; then
        printf "  ${DIM}(This is the main worktree and cannot be removed.)${RESET}\n"
    fi
    printf "  ${DIM}Press any key to go back...${RESET}"
    dd bs=1 count=1 &>/dev/null
}

# -- Remove a worktree with confirmation ---------------------------------------

remove_worktree() {
    local idx="$1"
    local wt_path="${WT_PATHS[$idx]}"
    local wt_branch="${WT_BRANCHES[$idx]}"

    if [[ $idx -eq 0 ]]; then
        clear_screen
        printf "\n  ${RED}Cannot remove the main worktree.${RESET}\n"
        printf "  ${DIM}Press any key to go back...${RESET}"
        dd bs=1 count=1 &>/dev/null
        return
    fi

    # Switch back to cooked mode for interactive prompts
    show_cursor
    exit_raw_mode
    clear_screen

    printf "\n  ${BOLD}${RED}Remove worktree${RESET}\n"
    printf "  ${DIM}Path:${RESET}   %s\n" "$wt_path"
    printf "  ${DIM}Branch:${RESET} %s\n" "$wt_branch"
    echo

    read -rp "  Remove this worktree? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        printf "  ${DIM}Aborted.${RESET}\n"
        sleep 0.5
        enter_raw_mode
        hide_cursor
        return
    fi

    if git worktree remove "$wt_path" 2>/dev/null; then
        printf "  ${GREEN}Worktree removed.${RESET}\n"
    else
        read -rp "  Worktree has changes. Force remove? [y/N] " force
        if [[ "$force" =~ ^[Yy]$ ]]; then
            git worktree remove --force "$wt_path"
            printf "  ${GREEN}Worktree force-removed.${RESET}\n"
        else
            printf "  ${DIM}Kept.${RESET}\n"
            sleep 0.5
            enter_raw_mode
            hide_cursor
            return
        fi
    fi

    # Offer branch deletion
    if [[ "$wt_branch" != "(detached)" ]]; then
        read -rp "  Also delete branch '${wt_branch}'? [y/N] " del_branch
        if [[ "$del_branch" =~ ^[Yy]$ ]]; then
            if git branch -d "$wt_branch" 2>/dev/null; then
                printf "  ${GREEN}Branch '${wt_branch}' deleted.${RESET}\n"
            else
                read -rp "  Branch not fully merged. Force delete? [y/N] " force_br
                if [[ "$force_br" =~ ^[Yy]$ ]]; then
                    git branch -D "$wt_branch"
                    printf "  ${GREEN}Branch '${wt_branch}' force-deleted.${RESET}\n"
                else
                    printf "  ${DIM}Branch kept.${RESET}\n"
                fi
            fi
        fi
    fi

    sleep 0.5

    # Refresh and re-enter raw mode
    gather_worktrees
    if [[ "$SELECTED" -ge "$COUNT" ]]; then
        SELECTED=$((COUNT - 1))
    fi

    enter_raw_mode
    hide_cursor
}

# -- Main loop -----------------------------------------------------------------

gather_worktrees

if [[ $COUNT -eq 0 ]]; then
    echo "No worktrees found."
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
            if [[ $SELECTED -gt 0 ]]; then
                SELECTED=$((SELECTED - 1))
            fi
            ;;
        DOWN)
            if [[ $SELECTED -lt $((COUNT - 1)) ]]; then
                SELECTED=$((SELECTED + 1))
            fi
            ;;
        ENTER)
            show_detail "$SELECTED"
            ;;
        DELETE)
            remove_worktree "$SELECTED"
            if [[ $COUNT -eq 0 ]]; then
                clear_screen
                printf "\n  ${DIM}No worktrees remaining.${RESET}\n"
                break
            fi
            ;;
        QUIT|ESC)
            clear_screen
            break
            ;;
    esac
done
