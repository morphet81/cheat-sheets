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
# The new branch is nested under the current branch's parent path, so all
# branches created from the same parent stay at the same level in the hierarchy.
#
# Examples (on branch "main"):
#   worktree-add.sh feat/nero-345    → worktree at ../feat-nero-345, branch feat/nero-345
#   worktree-add.sh test-this        → worktree at ../test-this, branch test-this
#
# Examples (on branch "project-x/main"):
#   worktree-add.sh feat/nero-345    → worktree at ../feat-nero-345, branch project-x/feat/nero-345
#   worktree-add.sh test-this        → worktree at ../test-this, branch project-x/test-this

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

# -- Fetch latest remote state -------------------------------------------------

echo "Fetching..."
git fetch

# -- Determine branch name and worktree path -----------------------------------

# Nest the new branch under the current branch's parent path.
# e.g. current branch "this-function/main" + param "feat/btn" → "this-function/feat/btn"
CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
BRANCH_PREFIX=""
if [[ "$CURRENT_BRANCH" == */* ]]; then
    BRANCH_PREFIX="${CURRENT_BRANCH%/*}/"
fi

# Conventional commit prefixes
CC_PATTERN="^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert|hotfix)/"

if [[ "$PARAM" =~ $CC_PATTERN ]]; then
    BRANCH="${BRANCH_PREFIX}${PARAM}"
    # Replace slashes with dashes for the directory name
    DIR_NAME="${PARAM//\//-}"
else
    BRANCH="${BRANCH_PREFIX}${PARAM}"
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

# -- Check if branch already exists (local or remote) -------------------------

BRANCH_EXISTS_LOCAL=false
BRANCH_EXISTS_REMOTE=false

if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    BRANCH_EXISTS_LOCAL=true
fi

REMOTE_REF="$(git remote | head -1)"
if [[ -n "$REMOTE_REF" ]] && git show-ref --verify --quiet "refs/remotes/${REMOTE_REF}/${BRANCH}"; then
    BRANCH_EXISTS_REMOTE=true
fi

if $BRANCH_EXISTS_LOCAL || $BRANCH_EXISTS_REMOTE; then
    if $BRANCH_EXISTS_LOCAL && $BRANCH_EXISTS_REMOTE; then
        echo "Branch '${BRANCH}' already exists (local and remote)."
    elif $BRANCH_EXISTS_LOCAL; then
        echo "Branch '${BRANCH}' already exists (local)."
    else
        echo "Branch '${BRANCH}' already exists (remote: ${REMOTE_REF}/${BRANCH})."
    fi
    printf "Use existing branch? [y/N] "
    read -r CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# -- Create the worktree -------------------------------------------------------

if $BRANCH_EXISTS_LOCAL; then
    # Local branch exists — check it out
    echo "Checking out existing branch '${BRANCH}' into worktree..."
    git worktree add "${WORKTREE_PATH}" "${BRANCH}"
elif $BRANCH_EXISTS_REMOTE; then
    # Remote branch exists — create local tracking branch
    echo "Creating local branch '${BRANCH}' tracking '${REMOTE_REF}/${BRANCH}'..."
    git worktree add --track -b "${BRANCH}" "${WORKTREE_PATH}" "${REMOTE_REF}/${BRANCH}"
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
