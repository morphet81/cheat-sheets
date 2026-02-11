---
name: create-pr
version: 1.3.0
description: Push the current branch and create a pull request on GitHub. Derives PR title and description from the JIRA ticket found in the branch name. Draft by default, use --no-draft for a ready PR.
argument-hint: "[--no-draft]"
---

Push the current branch and create a GitHub pull request with title and description derived from the JIRA ticket in the branch name.

**Usage:**
- `/create-pr` - Push and create a draft PR
- `/create-pr --no-draft` - Push and create a ready-for-review PR

**Instructions:**

1. **Check prerequisites:**
   - **JIRA MCP server:** Verify that a JIRA MCP tool is available. If not configured, display the following message and **STOP**:
     ```
     ## Missing Prerequisite: JIRA MCP Server

     No JIRA MCP server is configured. This skill requires a JIRA MCP integration to fetch issue details.

     Please configure a JIRA MCP server in your Claude Code settings before using this skill.
     ```
   - **GitHub CLI (`gh`):** Run `gh --version`. If not found, display the following message and **STOP**:
     ```
     ## Missing Prerequisite: GitHub CLI

     The `gh` command is not installed. This skill requires the GitHub CLI for repository operations.

     Install it from: https://cli.github.com/
     ```
   - **GitHub CLI authentication:** Run `gh auth status`. If not authenticated, display the following message and **STOP**:
     ```
     ## Missing Prerequisite: GitHub CLI Authentication

     The GitHub CLI is not authenticated. Please run `gh auth login` to authenticate before using this skill.
     ```

2. **Parse options from $ARGUMENTS:**
   - If `--no-draft` is present, the PR will be created as ready for review
   - Otherwise (default), the PR will be created as a draft

3. **Get the current branch and extract the JIRA ID:**
   - Run `git branch --show-current` to get the current branch name
   - Extract the JIRA ID by matching the pattern `[A-Z][A-Z0-9]+-[0-9]+` (e.g., `PROJ-123`, `AB-1`, `MYAPP-4567`)
   - The JIRA ID can appear anywhere in the branch name (e.g., `fix/proj-123`, `feat/PROJ-123`, `PROJ-123-some-description`)
   - The match should be case-insensitive — normalize the extracted ID to uppercase for the JIRA API lookup
   - If no JIRA ID is found, display the following message and **STOP**:
     ```
     No JIRA ID found in branch name: "<current-branch>"
     Expected a branch name containing a JIRA ID (e.g., fix/proj-123, feat/MYAPP-456).
     ```

4. **Fetch the JIRA ticket details:**
   - Use the JIRA MCP tool to retrieve the issue by its JIRA ID
   - Fetch: **summary**, **description**, **issue type** (Bug, Story, Task, etc.)
   - If the fetch fails, ask the developer to provide the issue type and summary manually using `AskUserQuestion`

5. **Determine the base branch:**
   - Check if a `.agent` file exists in the current directory
   - If it exists, read it and look for a `baseBranch=<value>` line to extract the base branch
   - Use `AskUserQuestion` to let the developer choose the base branch:
     - If a base branch was found in `.agent`: first option is that branch with "(from .agent)" suffix, second option is `main` (if different)
     - If no `.agent` file or no `baseBranch` key: first option is `main`
     - The developer can type a different branch name via the "Other" option if the PR targets a different base branch

6. **Push the branch:**
   - Run `git push -u origin <branch-name>`
   - If the branch is already up to date on the remote, that's fine — continue to the next step
   - If the push fails for any other reason, show the error and **STOP**

7. **Create the pull request:**
   - Build the PR title using the commit prefix convention based on issue type, followed by a concise summary derived from the JIRA ticket summary:
     - Bug → `fix: <summary>` (e.g., `fix: resolve null pointer in user lookup`)
     - All other types → `feat: <summary>` (e.g., `feat: add bulk export for reports`)
     - The summary part should be lowercase, imperative mood, and concise
   - Build the PR description from the JIRA ticket details:
     - Start with a `## Summary` section with a brief description based on the JIRA ticket description
     - Add a `## JIRA` section with a link to the ticket: `[PROJ-123](https://<site>.atlassian.net/browse/PROJ-123)`
   - Run the `gh pr create` command:
     - Use `--draft` flag unless `--no-draft` was passed
     - Use `--base <base-branch>` with the branch determined in step 5
     - Use a HEREDOC to pass the body
   - If PR creation fails, show the error and **STOP**

8. **Show success message:**

   Display a summary with all relevant information:

   ```
   ## PR Created

   - JIRA: PROJ-123
   - Branch: fix/proj-123 → main
   - PR: https://github.com/org/repo/pull/42 (draft)
   - Title: fix: resolve null pointer in user lookup
   ```
