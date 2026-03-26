# Cheat Sheets & Dev Toolkit

A personal collection of interactive cheat sheets, Claude Code skills, and utility scripts for everyday development.

## Cheat Sheets

Interactive HTML reference pages for keyboard shortcuts and commands:

| Page | Description |
|------|-------------|
| [**index.html**](index.html) | Landing page with links to all cheat sheets |
| [**nvim.html**](nvim.html) | Neovim/Vim keyboard shortcuts and commands |
| [**git.html**](git.html) | Git commands for branching, merging, and collaboration |
| [**zellij.html**](zellij.html) | Zellij terminal multiplexer shortcuts |
| [**iterm.html**](iterm.html) | iTerm2 navigation and pane management |

## Claude Code Skills

Automation skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code), stored in `skills/<name>/SKILL.md`. Full documentation available in [claude-skills.html](claude-skills.html).

| Skill | Description |
|-------|-------------|
| **address-ticket** | End-to-end ticket implementation with TDD using a multi-agent team |
| **address-pr-comments** | Retrieve PR comments, propose fixes, and implement them |
| **review-changes** | Spawn 8 specialized reviewer agents for code/PR review |
| **create-pr** | Push branch and create a GitHub PR from JIRA ticket context |
| **create-jira-ticket** | Create a JIRA ticket with epic inference, ADF, Figma, and confirmation via `acli` |
| **update-jira-ticket** | Sync JIRA ticket descriptions with branch changes |
| **setup-branch** | Create branch + worktree from a JIRA ID or URL |
| **merge-base-branch** | Pick base branch, merge, resolve conflicts, lint, 100% coverage tests, build |
| **cleanup** | Review changes, fix lint/audit, ensure coverage, then commit |
| **pre-push** | Parallel pre-push checks (tests, linting) |
| **verify-test-cases** | Check test quality, duplications, and coverage |
| **release-review** | Compare tags/commits and produce QA + developer reports |
| **team** | Spawn a multi-agent team (PO, designers, devs, testers) |
| **screenshots** | Capture app/Storybook screenshots of affected components |
| **localise** | Generate an HTML translation helper for Lokalise (23 languages) |
| **translate-pdf** | Translate PDF documents via Markdown extraction and rebuild |
| **adb** | Automate Android device interactions through ADB |

## Scripts

Standalone utilities in `scripts/<name>/`. Full listing with source code available in [scripts.html](scripts.html).

| Script | Description |
|--------|-------------|
| **markdown-to-pdf** | Convert Markdown to styled A4 PDF |
| **pdf-to-markdown** | Extract PDF content to structured Markdown |
| **reorder-duplex-pdf** | Reorder pages from a two-pass single-sided ADF scan |
| **setup-worktree** | Create a git worktree from a branch name or JIRA URL |
| **worktree-add** | Create a worktree in the parent directory |
| **worktree-remove** | Remove a git worktree by branch name or path |
| **worktrees** | Interactive worktree manager with arrow-key navigation |
| **zell** | Interactive zellij session manager |

## Project Structure

```
.
├── *.html              # Interactive cheat sheet pages
├── claude-skills.html  # Skills documentation page
├── scripts.html        # Scripts documentation page
├── skills/             # Claude Code skill definitions (SKILL.md each)
└── scripts/            # Standalone utility scripts
```
