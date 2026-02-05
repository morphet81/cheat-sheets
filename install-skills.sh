#!/bin/bash

# Claude Code Skills Installer
# Downloads skills from the cheat-sheets repository to ~/.claude/skills
# and adds references to ~/.claude/CLAUDE.md

set -e

# Configuration
REPO_OWNER="morphet81"
REPO_NAME="cheat-sheets"
BRANCH="main"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH"
GITHUB_API_BASE="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/contents"

# Markers for skill references section in CLAUDE.md
SKILLS_START_MARKER="<!-- CHEAT-SHEETS-SKILLS-START -->"
SKILLS_END_MARKER="<!-- CHEAT-SHEETS-SKILLS-END -->"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Claude Code Skills Installer         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check for required commands
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is required but not installed.${NC}"
    exit 1
fi

# Create directories if they don't exist
echo -e "${YELLOW}Setting up directories...${NC}"
mkdir -p "$CLAUDE_DIR"
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

echo -e "${GREEN}Found skills:${NC}"
echo "$SKILL_FOLDERS" | while read -r skill; do
    echo "  - $skill"
done
echo ""

# Track installed skills for reference generation
INSTALLED_SKILLS=""

# Download each skill
while read -r SKILL_NAME; do
    if [ -z "$SKILL_NAME" ]; then
        continue
    fi

    echo -e "${YELLOW}Installing skill: ${NC}${BLUE}$SKILL_NAME${NC}"

    SKILL_TARGET_DIR="$SKILLS_DIR/$SKILL_NAME"

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

            # Track .md files for references
            if [[ "$FILE_NAME" == *.md ]]; then
                INSTALLED_SKILLS="$INSTALLED_SKILLS$SKILL_NAME/$FILE_NAME"$'\n'
            fi
        else
            echo -e "  ${RED}✗ Failed to download $FILE_NAME${NC}"
        fi
    done <<< "$SKILL_FILES"

    echo ""
done <<< "$SKILL_FOLDERS"

# Build skills references section
echo -e "${YELLOW}Updating ~/.claude/CLAUDE.md...${NC}"

SKILLS_REFS="$SKILLS_START_MARKER
# Skills (auto-installed from morphet81/cheat-sheets)
"

while read -r SKILL_PATH; do
    if [ -n "$SKILL_PATH" ]; then
        SKILLS_REFS="$SKILLS_REFS
@skills/$SKILL_PATH"
    fi
done <<< "$INSTALLED_SKILLS"

SKILLS_REFS="$SKILLS_REFS

$SKILLS_END_MARKER"

# Update CLAUDE.md
if [ -f "$CLAUDE_MD" ]; then
    # Check if skills section already exists
    if grep -q "$SKILLS_START_MARKER" "$CLAUDE_MD"; then
        # Replace existing skills section
        echo -e "  ${YELLOW}Replacing existing skills references...${NC}"

        # Create temp file with content before marker, new refs, and content after marker
        BEFORE=$(sed -n "1,/$SKILLS_START_MARKER/p" "$CLAUDE_MD" | sed '$d')
        AFTER=$(sed -n "/$SKILLS_END_MARKER/,\$p" "$CLAUDE_MD" | sed '1d')

        echo "$BEFORE" > "$CLAUDE_MD.tmp"
        echo "$SKILLS_REFS" >> "$CLAUDE_MD.tmp"
        echo "$AFTER" >> "$CLAUDE_MD.tmp"

        mv "$CLAUDE_MD.tmp" "$CLAUDE_MD"
    else
        # Append skills section to existing file
        echo -e "  ${YELLOW}Appending skills references to existing file...${NC}"
        echo "" >> "$CLAUDE_MD"
        echo "$SKILLS_REFS" >> "$CLAUDE_MD"
    fi
else
    # Create new CLAUDE.md with skills references
    echo -e "  ${YELLOW}Creating new CLAUDE.md...${NC}"
    echo "$SKILLS_REFS" > "$CLAUDE_MD"
fi

echo -e "  ${GREEN}✓${NC} CLAUDE.md updated"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Installation complete!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "Skills downloaded to: ${BLUE}$SKILLS_DIR${NC}"
echo -e "References added to:  ${BLUE}$CLAUDE_MD${NC}"
echo ""
echo -e "${YELLOW}Installed skills:${NC}"
echo "$SKILL_FOLDERS" | while read -r skill; do
    echo -e "  ${GREEN}•${NC} /$skill"
done
echo ""
echo -e "${YELLOW}Open a new Claude Code session to use the skills.${NC}"
