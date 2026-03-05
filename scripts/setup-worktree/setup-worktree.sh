#!/usr/bin/env bash
# Create a git worktree from a branch name or Jira URL.
#
# Usage:
#   setup-worktree.sh <branch-name-or-jira-url>
#
# If a Jira URL or ID is provided, the Jira issue number is extracted and used as
# the branch suffix. A conventional commit type is selected interactively.
# If a branch name with a valid CC prefix is provided, it is used as-is.
# Otherwise, a CC type is selected interactively and prepended.
#
# Examples:
#   setup-worktree.sh feat/my-feature
#       → branch feat/my-feature, worktree at ../feat-my-feature
#   setup-worktree.sh my-feature
#       → prompts for type, e.g. feat/my-feature, worktree at ../feat-my-feature
#   setup-worktree.sh https://company.atlassian.net/browse/PROJ-123
#       → prompts for type, e.g. fix/proj-123, worktree at ../fix-proj-123

set -euo pipefail

# -- Colors & terminal helpers -------------------------------------------------

BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
WHITE='\033[97m'
BG_BLUE='\033[44m'

hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }

SAVED_TTY=""

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
    else
        echo "OTHER"
    fi
}

# -- Interactive type selector -------------------------------------------------
# Sets CC_TYPE to the selected conventional commit type.
# Returns 1 if the user quit without selecting.

CC_TYPES=("feat" "fix" "chore" "refactor" "docs" "test" "style" "perf" "build" "ci" "revert" "hotfix")
CC_TYPE=""

draw_type_menu() {
    local selected="$1"
    local hint="$2"
    local num=${#CC_TYPES[@]}

    # Move cursor to beginning of menu block
    printf "\033[${num}A"

    for i in "${!CC_TYPES[@]}"; do
        if [[ $i -eq $selected ]]; then
            printf "  ${BG_BLUE}${BOLD}${WHITE}▸ %-10s${RESET}  ${DIM}%s${RESET}\n" "${CC_TYPES[$i]}" "$(type_hint "${CC_TYPES[$i]}")"
        else
            printf "  ${DIM}  %-10s${RESET}\n" "${CC_TYPES[$i]}"
        fi
    done
}

type_hint() {
    case "$1" in
        feat)     echo "new feature or enhancement" ;;
        fix)      echo "bug fix" ;;
        chore)    echo "maintenance, tooling, config" ;;
        refactor) echo "code restructuring, no behavior change" ;;
        docs)     echo "documentation only" ;;
        test)     echo "add or update tests" ;;
        style)    echo "formatting, no logic change" ;;
        perf)     echo "performance improvement" ;;
        build)    echo "build system or dependencies" ;;
        ci)       echo "CI/CD configuration" ;;
        revert)   echo "revert a previous commit" ;;
        hotfix)   echo "urgent production fix" ;;
        *)        echo "" ;;
    esac
}

select_type() {
    local prompt="$1"
    local selected=0
    local num=${#CC_TYPES[@]}

    echo
    printf "  ${BOLD}${CYAN}${prompt}${RESET}\n"
    printf "  ${DIM}Use ↑↓ to navigate, Enter to confirm, q to quit${RESET}\n"
    echo

    # Print initial menu
    for i in "${!CC_TYPES[@]}"; do
        if [[ $i -eq $selected ]]; then
            printf "  ${BG_BLUE}${BOLD}${WHITE}▸ %-10s${RESET}  ${DIM}%s${RESET}\n" "${CC_TYPES[$i]}" "$(type_hint "${CC_TYPES[$i]}")"
        else
            printf "  ${DIM}  %-10s${RESET}\n" "${CC_TYPES[$i]}"
        fi
    done

    enter_raw_mode
    hide_cursor

    while true; do
        local key
        key=$(read_key)
        case "$key" in
            UP)
                if [[ $selected -gt 0 ]]; then
                    selected=$((selected - 1))
                fi
                draw_type_menu "$selected" ""
                ;;
            DOWN)
                if [[ $selected -lt $((num - 1)) ]]; then
                    selected=$((selected + 1))
                fi
                draw_type_menu "$selected" ""
                ;;
            ENTER)
                CC_TYPE="${CC_TYPES[$selected]}"
                break
                ;;
            QUIT|ESC)
                exit_raw_mode
                show_cursor
                echo
                echo "Aborted."
                exit 0
                ;;
        esac
    done

    exit_raw_mode
    show_cursor
    echo
}

# -- Validation ----------------------------------------------------------------

if [[ $# -ne 1 ]]; then
    echo "Usage: $(basename "$0") <branch-name-or-jira-url>"
    echo
    echo "Examples:"
    echo "  $(basename "$0") feat/my-feature"
    echo "  $(basename "$0") my-feature"
    echo "  $(basename "$0") https://company.atlassian.net/browse/PROJ-123"
    echo "  $(basename "$0") PROJ-123"
    exit 1
fi

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: not inside a git repository." >&2
    exit 1
fi

PARAM="$1"

# -- Parse input ---------------------------------------------------------------

# Conventional commit prefix pattern
CC_PATTERN="^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert|hotfix)/"

# Jira URL pattern: contains /browse/ followed by PROJECT-NUMBER
JIRA_URL_PATTERN="atlassian\.net/browse/([A-Za-z]+-[0-9]+)"

# Jira ID pattern: PROJECT-NUMBER standalone
JIRA_ID_PATTERN="^([A-Za-z]+-[0-9]+)$"

BRANCH_SUFFIX=""
NEEDS_TYPE=false

if [[ "$PARAM" =~ $JIRA_URL_PATTERN ]]; then
    # Jira URL → extract ID, lowercase it
    JIRA_ID="${BASH_REMATCH[1]}"
    BRANCH_SUFFIX="${JIRA_ID,,}"
    NEEDS_TYPE=true
    printf "  ${CYAN}Jira:${RESET} ${BOLD}${JIRA_ID}${RESET}\n"

elif [[ "$PARAM" =~ $JIRA_ID_PATTERN ]]; then
    # Standalone Jira ID → lowercase it
    JIRA_ID="${BASH_REMATCH[1]}"
    BRANCH_SUFFIX="${JIRA_ID,,}"
    NEEDS_TYPE=true
    printf "  ${CYAN}Jira:${RESET} ${BOLD}${JIRA_ID}${RESET}\n"

elif [[ "$PARAM" =~ $CC_PATTERN ]]; then
    # Branch name already has a valid CC prefix — use as-is
    BRANCH="$PARAM"

else
    # Plain branch name — need to pick a type
    BRANCH_SUFFIX="$PARAM"
    NEEDS_TYPE=true
fi

# -- Select conventional commit type if needed ---------------------------------

if $NEEDS_TYPE; then
    select_type "Select branch type:"
    BRANCH="${CC_TYPE}/${BRANCH_SUFFIX}"
fi

# -- Determine worktree path ---------------------------------------------------

DIR_NAME="${BRANCH//\//-}"
WORKTREE_PATH="../${DIR_NAME}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
ABS_PATH="$(cd "${REPO_ROOT}/.." && pwd)/${DIR_NAME}"

printf "  ${CYAN}Branch:${RESET}   ${BOLD}${BRANCH}${RESET}\n"
printf "  ${CYAN}Worktree:${RESET} ${BOLD}${ABS_PATH}${RESET}\n"
echo

# -- Guard: worktree already exists -------------------------------------------

if git worktree list --porcelain | grep -qF "worktree ${ABS_PATH}"; then
    echo "Error: worktree already exists at ${WORKTREE_PATH}" >&2
    exit 1
fi

# -- Guard: branch already exists ---------------------------------------------

if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    echo "Error: branch '${BRANCH}' already exists locally." >&2
    exit 1
fi

# -- Record current branch (base) ---------------------------------------------

BASE_BRANCH="$(git branch --show-current)"

# -- Create the worktree + branch ---------------------------------------------

echo "Creating worktree and branch..."
git worktree add -b "${BRANCH}" "${WORKTREE_PATH}"

# -- Copy .env files ----------------------------------------------------------

if [[ -f ".env" ]]; then
    cp ".env" "${WORKTREE_PATH}/.env"
    printf "  ${GREEN}✓${RESET} Copied .env\n"
fi

# -- Post-setup inside the worktree -------------------------------------------

# mise trust
if command -v mise &>/dev/null; then
    if mise trust "${ABS_PATH}" &>/dev/null 2>&1; then
        printf "  ${GREEN}✓${RESET} mise trust\n"
    else
        printf "  ${YELLOW}!${RESET} mise trust failed (non-fatal)\n"
    fi
fi

# .agent file
printf "baseBranch=%s\n" "${BASE_BRANCH}" > "${ABS_PATH}/.agent"
printf "  ${GREEN}✓${RESET} .agent → baseBranch=%s\n" "${BASE_BRANCH}"

# -- Success -------------------------------------------------------------------

echo
printf "  ${BOLD}${GREEN}Worktree ready!${RESET}\n"
printf "  ${DIM}Branch:${RESET}   %s\n" "${BRANCH}"
printf "  ${DIM}Base:${RESET}     %s\n" "${BASE_BRANCH}"
printf "  ${DIM}Path:${RESET}     %s\n" "${ABS_PATH}"
echo
printf "  To enter:  ${BOLD}cd %s${RESET}\n" "${WORKTREE_PATH}"
