#!/bin/bash

# Claude Code Skills Installer
# Downloads skills from the cheat-sheets repository to ~/.claude/skills
# Skills are auto-discovered by Claude Code - no CLAUDE.md references needed

set -e

# Configuration
REPO_OWNER="morphet81"
REPO_NAME="cheat-sheets"
BRANCH="main"
SKILLS_DIR="$HOME/.claude/skills"
GLOBAL_CLAUDE_MD="$HOME/.claude/CLAUDE.md"
GLOBAL_INSTRUCTIONS_URL_PATH="global-instructions.md"
INSTRUCTIONS_BEGIN_MARKER="<!-- BEGIN cheat-sheets-global-instructions -->"
INSTRUCTIONS_END_MARKER="<!-- END cheat-sheets-global-instructions -->"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH"
GITHUB_API_BASE="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Extract version from a SKILL.md file (reads the version: field from YAML frontmatter)
extract_version() {
    local file="$1"
    if [ -f "$file" ]; then
        awk '/^version:/{gsub(/[" ]/, "", $2); print $2; exit}' "$file" 2>/dev/null || echo "unknown"
    else
        echo "not installed"
    fi
}

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Claude Code Skills Installer         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check for required commands
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is required but not installed.${NC}"
    exit 1
fi

# Create skills directory if it doesn't exist
echo -e "${YELLOW}Setting up skills directory...${NC}"
mkdir -p "$SKILLS_DIR"

# Fetch list of skill folders from GitHub API
echo -e "${YELLOW}Fetching available skills...${NC}"
SKILLS_JSON=$(curl -s "$GITHUB_API_BASE/skills?ref=$BRANCH")

# Check if the API request was successful
if echo "$SKILLS_JSON" | grep -q '"message"'; then
    echo -e "${RED}Error: Could not fetch skills list from GitHub.${NC}"
    echo -e "${RED}Make sure the repository is public and the URL is correct.${NC}"
    exit 1
fi

# Parse skill folder names (directories only)
SKILL_FOLDERS=$(echo "$SKILLS_JSON" | grep -o '"name": "[^"]*"' | grep -o '[^"]*"$' | tr -d '"' | sort)

if [ -z "$SKILL_FOLDERS" ]; then
    echo -e "${RED}Error: No skills found in the repository.${NC}"
    exit 1
fi

echo -e "${CYAN}Current versions:${NC}"
while read -r skill; do
    [ -z "$skill" ] && continue
    CURRENT_VER=$(extract_version "$SKILLS_DIR/$skill/SKILL.md")
    if [ "$CURRENT_VER" = "not installed" ]; then
        echo -e "  ${DIM}$skill — not installed${NC}"
    else
        echo -e "  $skill — ${BLUE}v$CURRENT_VER${NC}"
    fi
done <<< "$SKILL_FOLDERS"
echo ""

# Track results per category
NEW_SKILLS=""
UPDATED_SKILLS=""
UNCHANGED_SKILLS=""

# Download each skill
while read -r SKILL_NAME; do
    if [ -z "$SKILL_NAME" ]; then
        continue
    fi

    SKILL_TARGET_DIR="$SKILLS_DIR/$SKILL_NAME"
    OLD_VER=$(extract_version "$SKILL_TARGET_DIR/SKILL.md")

    echo -e "${YELLOW}Installing skill: ${NC}${BLUE}$SKILL_NAME${NC}"

    # Remove existing skill folder if it exists
    if [ -d "$SKILL_TARGET_DIR" ]; then
        echo -e "  ${YELLOW}Replacing existing skill...${NC}"
        rm -rf "$SKILL_TARGET_DIR"
    fi

    # Create skill directory
    mkdir -p "$SKILL_TARGET_DIR"

    # Fetch files in the skill folder
    SKILL_FILES_JSON=$(curl -s "$GITHUB_API_BASE/skills/$SKILL_NAME?ref=$BRANCH")
    SKILL_FILES=$(echo "$SKILL_FILES_JSON" | grep -o '"name": "[^"]*"' | grep -o '[^"]*"$' | tr -d '"')

    # Download each file in the skill folder
    while read -r FILE_NAME; do
        if [ -z "$FILE_NAME" ]; then
            continue
        fi

        FILE_URL="$GITHUB_RAW_BASE/skills/$SKILL_NAME/$FILE_NAME"
        TARGET_FILE="$SKILL_TARGET_DIR/$FILE_NAME"

        echo -e "  ${YELLOW}Downloading:${NC} $FILE_NAME"

        if curl -sL "$FILE_URL" -o "$TARGET_FILE"; then
            echo -e "  ${GREEN}✓${NC} $FILE_NAME"
        else
            echo -e "  ${RED}✗ Failed to download $FILE_NAME${NC}"
        fi
    done <<< "$SKILL_FILES"

    # Read new version after download
    NEW_VER=$(extract_version "$SKILL_TARGET_DIR/SKILL.md")

    # Track version transition
    if [ "$OLD_VER" = "not installed" ]; then
        echo -e "  ${GREEN}NEW${NC} v$NEW_VER"
        NEW_SKILLS="${NEW_SKILLS}${SKILL_NAME}|${NEW_VER}\n"
    elif [ "$OLD_VER" != "$NEW_VER" ]; then
        echo -e "  ${YELLOW}UPDATED${NC} v$OLD_VER → v$NEW_VER"
        UPDATED_SKILLS="${UPDATED_SKILLS}${SKILL_NAME}|${OLD_VER}|${NEW_VER}\n"
    else
        echo -e "  ${DIM}unchanged${NC} v$NEW_VER"
        UNCHANGED_SKILLS="${UNCHANGED_SKILLS}${SKILL_NAME}|${NEW_VER}\n"
    fi

    echo ""
done <<< "$SKILL_FOLDERS"

# Install global instructions into ~/.claude/CLAUDE.md
install_global_instructions() {
    echo -e "${YELLOW}Installing global instructions...${NC}"

    # Download the global instructions to a temp file
    TEMP_INSTRUCTIONS=$(mktemp)
    if ! curl -sL "$GITHUB_RAW_BASE/$GLOBAL_INSTRUCTIONS_URL_PATH" -o "$TEMP_INSTRUCTIONS" || [ ! -s "$TEMP_INSTRUCTIONS" ]; then
        echo -e "${RED}  Error: Could not fetch global instructions.${NC}"
        rm -f "$TEMP_INSTRUCTIONS"
        return 1
    fi

    # Build the full block (markers + content) into a temp file
    TEMP_BLOCK=$(mktemp)
    {
        echo "$INSTRUCTIONS_BEGIN_MARKER"
        cat "$TEMP_INSTRUCTIONS"
        echo "$INSTRUCTIONS_END_MARKER"
    } > "$TEMP_BLOCK"

    # Ensure ~/.claude directory exists
    mkdir -p "$(dirname "$GLOBAL_CLAUDE_MD")"

    if [ -f "$GLOBAL_CLAUDE_MD" ]; then
        if grep -qF "$INSTRUCTIONS_BEGIN_MARKER" "$GLOBAL_CLAUDE_MD"; then
            # Replace the existing block using awk
            awk -v begin="$INSTRUCTIONS_BEGIN_MARKER" \
                -v end="$INSTRUCTIONS_END_MARKER" \
                -v block_file="$TEMP_BLOCK" '
                $0 == begin {
                    while ((getline line < block_file) > 0) print line
                    skip = 1
                    next
                }
                $0 == end { skip = 0; next }
                !skip { print }
            ' "$GLOBAL_CLAUDE_MD" > "${GLOBAL_CLAUDE_MD}.tmp"
            mv "${GLOBAL_CLAUDE_MD}.tmp" "$GLOBAL_CLAUDE_MD"
            echo -e "  ${YELLOW}UPDATED${NC} global instructions in $GLOBAL_CLAUDE_MD"
        else
            # Append the block (with a blank line separator)
            echo "" >> "$GLOBAL_CLAUDE_MD"
            cat "$TEMP_BLOCK" >> "$GLOBAL_CLAUDE_MD"
            echo -e "  ${GREEN}NEW${NC} global instructions added to $GLOBAL_CLAUDE_MD"
        fi
    else
        # Create the file with just the block
        cat "$TEMP_BLOCK" > "$GLOBAL_CLAUDE_MD"
        echo -e "  ${GREEN}NEW${NC} global instructions created at $GLOBAL_CLAUDE_MD"
    fi

    rm -f "$TEMP_INSTRUCTIONS" "$TEMP_BLOCK"
    echo ""
}

install_global_instructions || true

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation complete!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "Skills installed to: ${BLUE}$SKILLS_DIR${NC}"
echo ""

if [ -n "$NEW_SKILLS" ]; then
    echo -e "${GREEN}New:${NC}"
    echo -e "$NEW_SKILLS" | while IFS='|' read -r name ver; do
        [ -z "$name" ] && continue
        echo -e "  ${GREEN}+${NC} /$name ${BLUE}v$ver${NC}"
    done
fi

if [ -n "$UPDATED_SKILLS" ]; then
    echo -e "${YELLOW}Updated:${NC}"
    echo -e "$UPDATED_SKILLS" | while IFS='|' read -r name old new; do
        [ -z "$name" ] && continue
        echo -e "  ${YELLOW}↑${NC} /$name ${DIM}v$old${NC} → ${BLUE}v$new${NC}"
    done
fi

if [ -n "$UNCHANGED_SKILLS" ]; then
    echo -e "${DIM}Unchanged:${NC}"
    echo -e "$UNCHANGED_SKILLS" | while IFS='|' read -r name ver; do
        [ -z "$name" ] && continue
        echo -e "  ${DIM}  /$name v$ver${NC}"
    done
fi

echo ""
echo -e "${YELLOW}Skills are auto-discovered. Open a new Claude Code session to use them.${NC}"
