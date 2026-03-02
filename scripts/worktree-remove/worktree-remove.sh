#!/usr/bin/env bash
# Remove a git worktree by branch name or path.
#
# Usage:
#   worktree-remove.sh <branch-name-or-path>
#
# The parameter can be:
#   - A branch name (e.g., feat/nero-345) — finds and removes the matching worktree
#   - A worktree path (e.g., ../feat-nero-345) — removes that worktree directly
#
# The worktree is removed and the associated branch is deleted (with confirmation).
#
# Examples:
#   worktree-remove.sh feat/nero-345
#   worktree-remove.sh ../feat-nero-345

set -euo pipefail

# -- Validation ----------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    echo "Usage: $(basename "$0") <branch-name-or-path>"
    echo
    echo "Examples:"
    echo "  $(basename "$0") feat/nero-345     # by branch name"
    echo "  $(basename "$0") ../feat-nero-345  # by path"
    exit 1
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository." >&2
    exit 1
fi

PARAM="$1"
WORKTREE_PATH=""
BRANCH=""

# -- Resolve worktree from parameter -------------------------------------------

# Try to match as a branch name first
while IFS= read -r line; do
    if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
        current_path="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]]; then
        current_branch="${BASH_REMATCH[1]}"
        if [[ "$current_branch" == "$PARAM" ]]; then
            WORKTREE_PATH="$current_path"
            BRANCH="$current_branch"
            break
        fi
    fi
done < <(git worktree list --porcelain)

# If not found by branch, try as a path
if [[ -z "$WORKTREE_PATH" ]]; then
    # Resolve the parameter to an absolute path
    if [[ -d "$PARAM" ]]; then
        RESOLVED="$(cd "$PARAM" && pwd)"
    else
        # Try resolving relative to cwd even if dir doesn't exist
        RESOLVED="$(cd "$(dirname "$PARAM")" 2>/dev/null && pwd)/$(basename "$PARAM")" || RESOLVED="$PARAM"
    fi

    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
            current_path="${BASH_REMATCH[1]}"
            if [[ "$current_path" == "$RESOLVED" ]]; then
                WORKTREE_PATH="$current_path"
            fi
        elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]] && [[ -n "$WORKTREE_PATH" ]] && [[ -z "$BRANCH" ]]; then
            BRANCH="${BASH_REMATCH[1]}"
            break
        fi
    done < <(git worktree list --porcelain)
fi

if [[ -z "$WORKTREE_PATH" ]]; then
    echo "Error: no worktree found for '${PARAM}'." >&2
    echo "Run 'git worktree list' to see existing worktrees." >&2
    exit 1
fi

# -- Confirm and remove --------------------------------------------------------

echo "Worktree found:"
echo "  Path:   ${WORKTREE_PATH}"
[[ -n "$BRANCH" ]] && echo "  Branch: ${BRANCH}"
echo

read -rp "Remove this worktree? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

git worktree remove "$WORKTREE_PATH"
echo "Worktree removed."

# Offer to delete the branch
if [[ -n "$BRANCH" ]]; then
    read -rp "Also delete branch '${BRANCH}'? [y/N] " del_branch
    if [[ "$del_branch" =~ ^[Yy]$ ]]; then
        if git branch -d "$BRANCH" 2>/dev/null; then
            echo "Branch '${BRANCH}' deleted."
        else
            read -rp "Branch not fully merged. Force delete? [y/N] " force
            if [[ "$force" =~ ^[Yy]$ ]]; then
                git branch -D "$BRANCH"
                echo "Branch '${BRANCH}' force-deleted."
            else
                echo "Branch '${BRANCH}' kept."
            fi
        fi
    fi
fi
