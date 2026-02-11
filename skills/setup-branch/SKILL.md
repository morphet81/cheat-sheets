---
name: setup-branch
description: Create a new branch and worktree from a JIRA ID or URL. Determines branch prefix (fix/ or feat/) from the JIRA item type, sets up the worktree one level up, installs dependencies, pushes the branch, and creates a draft PR.
argument-hint: "<JIRA-ID or URL>"
---

Create a new git branch and worktree from a JIRA ticket. Automatically names the branch based on the JIRA item type and sets up the worktree ready to work in.

**Usage:**
- `/setup-branch PROJ-123` - Create branch from JIRA ID
- `/setup-branch https://mycompany.atlassian.net/browse/PROJ-123` - Create branch from JIRA URL

**Instructions:**

1. **Check prerequisites:**
   - **JIRA MCP server:** Verify that a JIRA MCP tool is available (e.g., by checking if any MCP tools related to JIRA/Atlassian are accessible). If no JIRA MCP server is configured, display the following message and **STOP**:
     ```
     ## Missing Prerequisite: JIRA MCP Server

     No JIRA MCP server is configured. This skill requires a JIRA MCP integration to fetch issue details.

     Please configure a JIRA MCP server in your Claude Code settings before using this skill.
     ```
   - **GitHub CLI (`gh`):** Run `gh --version` to check if the `gh` CLI is installed. If the command fails (not found), display the following message and **STOP**:
     ```
     ## Missing Prerequisite: GitHub CLI

     The `gh` command is not installed. This skill requires the GitHub CLI for repository operations.

     Install it from: https://cli.github.com/
     ```
   - **GitHub CLI authentication:** Run `gh auth status` to check if `gh` is authenticated. If the command indicates the user is not logged in, display the following message and **STOP**:
     ```
     ## Missing Prerequisite: GitHub CLI Authentication

     The GitHub CLI is not authenticated. Please run `gh auth login` to authenticate before using this skill.
     ```

2. **Parse the JIRA reference from $ARGUMENTS:**
   - If no argument is provided, inform the user of the expected usage and STOP
   - If the argument is a URL (contains `atlassian.net/browse/` or similar), extract the JIRA ID from the URL path (e.g., `https://mycompany.atlassian.net/browse/PROJ-123` → `PROJ-123`). If the JIRA ID cannot be extracted, show what was received and STOP
   - If the argument is already a JIRA ID (matches pattern like `PROJ-123`, `ABC-1`, etc.), use it directly
   - If the argument cannot be parsed as either a URL or JIRA ID, inform the user and STOP

3. **Fetch the JIRA item type:**
   - Use the JIRA MCP tool or API to fetch the issue details for the extracted JIRA ID
   - Identify the issue type (Bug, Story, Task, Epic, Sub-task, etc.)
   - If the JIRA API is not available or the fetch fails, ask the developer to provide the issue type manually using `AskUserQuestion` with options: "Bug", "Story/Task/Other"

4. **Determine the branch name:**
   - Lowercase the JIRA ID for use in the branch name (e.g., `PROJ-123` → `proj-123`)
   - If the issue type is **Bug**: branch name is `fix/<jira-id>` (e.g., `fix/proj-123`)
   - For **all other types** (Story, Task, Epic, Sub-task, etc.): branch name is `feat/<jira-id>` (e.g., `feat/proj-123`)

5. **Ask which base branch to branch from:**
   - Use `AskUserQuestion` to ask the developer which branch to use as the base
   - Default option should be `main`
   - Let the developer type a different branch name via the "Other" option

6. **Fetch the base branch from remote:**
   - Run `git fetch origin <base-branch>`
   - **If the fetch fails** (e.g., the base branch does not exist on the remote), show the error and STOP immediately. Do not continue with branch or worktree creation.
   - Do **NOT** checkout or pull the base branch — this avoids disrupting uncommitted work in the current worktree.

7. **Create the new branch and worktree together:**
   - If the branch name already exists locally (`git rev-parse --verify <branch-name>` succeeds), inform the user and STOP (do not force-create)
   - Determine the worktree path: take the **parent directory** of the current working directory and append the branch name with `/` replaced by `-`
     - Example: if CWD is `/Users/dev/my-project` and branch is `fix/proj-123`, the worktree path is `/Users/dev/fix-proj-123`
   - If the worktree directory already exists, inform the user and STOP
   - Run `git worktree add <worktree-path> -b <branch-name> origin/<base-branch>`
     - This creates the new branch based on the remote base branch AND the worktree in a single command, without touching the current worktree
   - If the command fails, show the error and STOP

8. **Install dependencies in the new worktree:**
   - **All commands in this step must run from the new worktree directory** (use `cd <worktree-path>` before running them, or pass the `cwd` option)
   - Detect the package manager by checking for lock files in the new worktree directory:
     - `bun.lockb` or `bun.lock` → run `bun install --frozen-lockfile`
     - `pnpm-lock.yaml` → run `pnpm install --frozen-lockfile`
     - `yarn.lock` → run `yarn install --frozen-lockfile`
     - `package-lock.json` → run `npm ci`
     - If none of these lock files exist but a `package.json` is present → run `npm install` and warn that no lock file was found
     - If no `package.json` exists → skip dependency installation entirely
   - If the install command fails, show the error but do NOT delete the worktree — the developer may want to fix the issue manually

9. **Push the branch and create a draft PR:**
   - **All commands in this step must run from the new worktree directory**
   - Run `git push -u origin <branch-name>`
   - If the push fails, show the error but do NOT delete the worktree — continue to the success message without a PR
   - If the push succeeds, create a draft PR using `gh pr create --draft`:
     - **Title:** Use the commit prefix convention based on issue type, followed by a concise summary derived from the JIRA ticket summary:
       - Bug → `fix: <summary>` (e.g., `fix: resolve null pointer in user lookup`)
       - All other types → `feat: <summary>` (e.g., `feat: add bulk export for reports`)
       - The summary part should be lowercase, imperative mood, and concise
     - **Description:** Build the body from the JIRA ticket details:
       - Start with a `## Summary` section with a brief description based on the JIRA ticket description
       - Add a `## JIRA` section with a link to the ticket: `[PROJ-123](https://<site>.atlassian.net/browse/PROJ-123)`
       - Use a HEREDOC to pass the body to `gh pr create`
     - **Base branch:** Use the base branch selected in step 5
   - If PR creation fails, show the error but do NOT treat it as a fatal failure — the branch and worktree are still usable

10. **Show success message:**

   Display a summary with all relevant information:

   ```
   ## Branch Setup Complete

   - JIRA: PROJ-123
   - Type: Bug → fix/proj-123
   - Base: origin/main
   - Worktree: /Users/dev/fix-proj-123
   - Dependencies: installed (npm ci)
   - PR: https://github.com/org/repo/pull/42 (draft)

   To start working:
     cd /Users/dev/fix-proj-123
   ```

   If the PR was not created (push or PR creation failed), omit the PR line and add:

   ```
   To push and create a PR manually:
     cd /Users/dev/fix-proj-123
     git push -u origin fix/proj-123
     gh pr create --draft
   ```
