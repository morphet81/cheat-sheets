---
name: create-pr
version: 1.6.0
description: Push the current branch and create a pull request on GitHub. Derives PR title and description from the JIRA ticket found in the branch name. Draft by default, use --no-draft for a ready PR.
argument-hint: "[--no-draft]"
---

Push the current branch and create a GitHub pull request with title and description derived from the JIRA ticket in the branch name.

**Usage:**
- `/create-pr` - Push and create a draft PR
- `/create-pr --no-draft` - Push and create a ready-for-review PR

**Instructions:**

1. **Check prerequisites:**
   - **Atlassian CLI (`acli`):** Run `acli auth status` to check if the CLI is installed and authenticated.
     - If the command is not found, display the following message and **STOP**:
       ```
       ## Missing Prerequisite: Atlassian CLI

       The `acli` command is not installed. This skill requires the Atlassian CLI to fetch JIRA issue details.

       Install it with: brew tap atlassian/acli && brew install acli
       ```
     - If the command fails with an authentication error, display the following message and **STOP**:
       ```
       ## Missing Prerequisite: Atlassian CLI Authentication

       The Atlassian CLI is not authenticated. Please run `acli auth login` to authenticate before using this skill.
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
   - Use the Atlassian CLI to retrieve the issue by its JIRA ID:
     ```bash
     acli jira workitem view <JIRA-ID> --fields summary,description,issuetype --json
     ```
   - Extract: **summary**, **description**, **issue type** (Bug, Story, Task, etc.)
   - If the fetch fails, ask the developer to provide the issue type and summary manually using `AskUserQuestion`

5. **Determine the base branch:**
   - Check if a `.agent` file exists in the current directory
   - If it exists, read it and look for a `baseBranch=<value>` line to extract the base branch
   - Use `AskUserQuestion` to let the developer choose the base branch:
     - If a base branch was found in `.agent`: first option is that branch with "(from .agent)" suffix, second option is `main` (if different)
     - If no `.agent` file or no `baseBranch` key: first option is `main`
     - The developer can type a different branch name via the "Other" option if the PR targets a different base branch

6. **Push the branch:**

   The push strategy depends on whether the PR is a draft or ready for review:

   **If creating a draft PR (no `--no-draft` option):**
   - Run `git push -u origin <branch-name> --no-verify`
   - Since this is a draft PR, pre-push checks can be skipped — they will run in CI and the developer will address any issues before marking the PR as ready
   - If the push fails, show the error and **STOP**

   **If creating a ready-for-review PR (`--no-draft` was passed):**
   - Run `git push -u origin <branch-name>`
   - If the branch is already up to date on the remote, that's fine — continue to the next step
   - If the push fails due to a **pre-push hook** (look for signs like `husky`, `pre-push`, hook script output, or interactive prompts in the error output):

     **a) Offer to bypass with `--no-verify`:**
     - Use `AskUserQuestion` to ask the developer:
       > The push was blocked by a pre-push hook. Would you like to bypass it with `--no-verify`?
     - Options: **Yes — push with --no-verify** and **No — resolve the pre-push hook**

     **b) If the developer chooses `--no-verify`:**
     - Run `git push -u origin <branch-name> --no-verify`
     - **IMPORTANT:** Force the PR to be created as a **draft** regardless of `--no-draft`. Since pre-push checks were skipped, the PR should not be marked as ready for review.
     - If this push also fails, show the error and **STOP**

     **c) If the developer chooses to resolve the hook:**
     - Show the full pre-push hook output to the developer so they can see what is being asked or what failed
     - If the hook output contains a prompt or question (e.g., "Do you want to continue? [y/n]"), present the options to the developer using `AskUserQuestion` and use their answer to interact with the hook
     - Re-run `git push -u origin <branch-name>` after resolving
     - If the push still fails, show the error and **STOP**

   - If the push fails for any other reason (not a pre-push hook), show the error and **STOP**

7. **Create the pull request:**
   - Build the PR title using the commit prefix convention based on issue type, followed by a concise summary derived from the JIRA ticket summary:
     - Bug → `fix: <summary>` (e.g., `fix: resolve null pointer in user lookup`)
     - All other types → `feat: <summary>` (e.g., `feat: add bulk export for reports`)
     - The summary part should be lowercase, imperative mood, and concise
   - Build the PR description from the JIRA ticket details:
     - Start with a `## Summary` section with a brief description based on the JIRA ticket description
     - Add a `## JIRA` section with a link to the ticket: `[PROJ-123](https://<site>.atlassian.net/browse/PROJ-123)`
   - Run the `gh pr create` command:
     - Use `--draft` flag unless `--no-draft` was passed. **Exception:** if the push in step 6 used `--no-verify`, always use `--draft` regardless of the `--no-draft` option, and inform the developer:
       ```
       ⚠️ PR created as draft because pre-push checks were skipped (--no-verify).
       Mark it as ready for review after ensuring all checks pass.
       ```
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
