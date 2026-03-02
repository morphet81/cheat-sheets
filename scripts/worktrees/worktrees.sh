#!/usr/bin/env bash
# Interactive git worktree manager.
#
# Lists all worktrees in a formatted table. The user can select a worktree
# to see its git status and optionally remove it.
#
# Usage:
#   worktrees.sh

set -euo pipefail

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository." >&2
    exit 1
fi

# -- Gather worktrees ----------------------------------------------------------

declare -a WT_PATHS=()
declare -a WT_BRANCHES=()
declare -a WT_COMMITS=()
declare -a WT_BARE=()

current_path=""
current_branch=""
current_commit=""
is_bare=false

while IFS= read -r line; do
    if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
        # Save previous entry
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

# Save last entry
if [[ -n "$current_path" ]]; then
    WT_PATHS+=("$current_path")
    WT_BRANCHES+=("${current_branch:-(detached)}")
    WT_COMMITS+=("$current_commit")
    WT_BARE+=("$is_bare")
fi

COUNT=${#WT_PATHS[@]}

if [[ $COUNT -eq 0 ]]; then
    echo "No worktrees found."
    exit 0
fi

# -- Display worktrees ---------------------------------------------------------

display_worktrees() {
    echo
    echo "  Git Worktrees"
    echo "  ============="
    echo
    printf "  %-4s  %-30s  %-25s  %s\n" "#" "Branch" "Commit" "Path"
    printf "  %-4s  %-30s  %-25s  %s\n" "---" "------------------------------" "-------------------------" "----"

    for i in $(seq 0 $((COUNT - 1))); do
        local marker=""
        if [[ "${WT_BARE[$i]}" == "true" ]]; then
            marker=" (bare)"
        fi
        # Mark the main worktree
        local idx=$((i + 1))
        if [[ $i -eq 0 ]]; then
            marker=" (main)"
        fi
        printf "  %-4s  %-30s  %-25s  %s\n" \
            "${idx}" \
            "${WT_BRANCHES[$i]}${marker}" \
            "${WT_COMMITS[$i]}" \
            "${WT_PATHS[$i]}"
    done
    echo
}

# -- Interactive loop ----------------------------------------------------------

while true; do
    display_worktrees

    echo "  Enter a worktree number to inspect, or 'q' to quit."
    read -rp "  > " choice

    if [[ "$choice" == "q" || "$choice" == "Q" || -z "$choice" ]]; then
        break
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt $COUNT ]]; then
        echo "  Invalid selection."
        continue
    fi

    idx=$((choice - 1))
    wt_path="${WT_PATHS[$idx]}"
    wt_branch="${WT_BRANCHES[$idx]}"

    echo
    echo "  ── ${wt_branch} ──"
    echo "  Path: ${wt_path}"
    echo

    if [[ -d "$wt_path" ]]; then
        echo "  Status:"
        git -C "$wt_path" status --short | sed 's/^/    /' || echo "    (clean)"
        echo
        echo "  Recent commits:"
        git -C "$wt_path" log --oneline -5 | sed 's/^/    /'
    else
        echo "  (directory not found — worktree may be prunable)"
    fi

    echo

    # Don't offer removal for the main worktree
    if [[ $idx -eq 0 ]]; then
        echo "  (This is the main worktree and cannot be removed.)"
        read -rp "  Press Enter to continue..." _
        continue
    fi

    read -rp "  Remove this worktree? [y/N] " remove
    if [[ "$remove" =~ ^[Yy]$ ]]; then
        git worktree remove "$wt_path" && echo "  Worktree removed." || {
            read -rp "  Worktree has changes. Force remove? [y/N] " force
            if [[ "$force" =~ ^[Yy]$ ]]; then
                git worktree remove --force "$wt_path"
                echo "  Worktree force-removed."
            else
                echo "  Kept."
                read -rp "  Press Enter to continue..." _
                continue
            fi
        }

        # Offer branch deletion
        if [[ "$wt_branch" != "(detached)" ]]; then
            read -rp "  Also delete branch '${wt_branch}'? [y/N] " del_branch
            if [[ "$del_branch" =~ ^[Yy]$ ]]; then
                if git branch -d "$wt_branch" 2>/dev/null; then
                    echo "  Branch '${wt_branch}' deleted."
                else
                    read -rp "  Branch not fully merged. Force delete? [y/N] " force_br
                    if [[ "$force_br" =~ ^[Yy]$ ]]; then
                        git branch -D "$wt_branch"
                        echo "  Branch '${wt_branch}' force-deleted."
                    else
                        echo "  Branch kept."
                    fi
                fi
            fi
        fi

        # Refresh worktree list
        WT_PATHS=()
        WT_BRANCHES=()
        WT_COMMITS=()
        WT_BARE=()

        current_path=""
        current_branch=""
        current_commit=""
        is_bare=false

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

        if [[ $COUNT -eq 0 ]]; then
            echo "  No worktrees remaining."
            break
        fi
    fi

    read -rp "  Press Enter to continue..." _
done
