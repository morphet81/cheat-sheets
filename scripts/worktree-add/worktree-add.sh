#!/usr/bin/env bash
# Create a git worktree in the parent directory with automatic branch handling.
#
# Usage:
#   worktree-add.sh <branch-or-name>
#
# If the parameter looks like a conventional commit branch (feat/..., fix/..., etc.),
# it is used as the branch name and the worktree is created at ../<type-rest>.
# Otherwise, a new branch with the given name is created at ../<name>.
#
# Examples:
#   worktree-add.sh feat/nero-345    → worktree at ../feat-nero-345, branch feat/nero-345
#   worktree-add.sh test-this        → worktree at ../test-this, branch test-this

set -euo pipefail

# -- Validation ----------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    echo "Usage: $(basename "$0") <branch-or-name>"
    echo
    echo "Examples:"
    echo "  $(basename "$0") feat/nero-345    # worktree at ../feat-nero-345"
    echo "  $(basename "$0") test-this        # worktree at ../test-this"
    exit 1
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository." >&2
    exit 1
fi

PARAM="$1"

# -- Determine branch name and worktree path -----------------------------------

# Conventional commit prefixes
CC_PATTERN="^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert|hotfix)/"

if [[ "$PARAM" =~ $CC_PATTERN ]]; then
    BRANCH="$PARAM"
    # Replace slashes with dashes for the directory name
    DIR_NAME="${PARAM//\//-}"
else
    BRANCH="$PARAM"
    DIR_NAME="$PARAM"
fi

WORKTREE_PATH="../${DIR_NAME}"

# Resolve to absolute path for display
ABS_PATH="$(cd "$(git rev-parse --show-toplevel)/.." && pwd)/${DIR_NAME}"

# -- Check if worktree already exists ------------------------------------------

if git worktree list --porcelain | grep -q "worktree ${ABS_PATH}$"; then
    echo "Error: worktree already exists at ${WORKTREE_PATH}" >&2
    exit 1
fi

# -- Create the worktree -------------------------------------------------------

if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    # Branch exists — use it
    echo "Branch '${BRANCH}' exists, checking out into worktree..."
    git worktree add "${WORKTREE_PATH}" "${BRANCH}"
else
    # Branch does not exist — create it
    echo "Creating new branch '${BRANCH}' and worktree..."
    git worktree add -b "${BRANCH}" "${WORKTREE_PATH}"
fi

echo
echo "Worktree ready:"
echo "  Path:   ${ABS_PATH}"
echo "  Branch: ${BRANCH}"
echo
echo "To enter:  cd ${WORKTREE_PATH}"
