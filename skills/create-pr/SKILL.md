---
name: create-pr
version: 1.8.0
description: Push the current branch and create a pull request on GitHub. Derives the title and description from any JIRA ticket referenced by the branch, and references every issue (JIRA, GitHub, etc.) the PR actually fixes — never related items. Draft by default, use --no-draft for a ready PR.
argument-hint: "[--no-draft]"
---

Push the current branch and create a GitHub pull request. When the branch name contains a JIRA ID and the ticket can be loaded, the PR title and description follow the ticket. When there is no JIRA ID or the ticket cannot be fetched, still push the branch, propose several PR title options for the developer to choose from (or a custom title), then create the PR. The PR description always references every issue this PR actually fixes — JIRA tickets, GitHub issues, etc. — and only those, never related-but-not-addressed items.

**Usage:**
- `/create-pr` - Push and create a draft PR
- `/create-pr --no-draft` - Push and create a ready-for-review PR

**Instructions:**

1. **Check prerequisites (GitHub — always):**
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

2. **Parse options:**
   - If `$1` is `--no-draft`, the PR will be created as ready for review
   - Otherwise (default, no arguments), the PR will be created as a draft

3. **Get the current branch and extract the JIRA ID:**
   - Run `git branch --show-current` to get the current branch name
   - Extract the JIRA ID by matching the pattern `[A-Z][A-Z0-9]+-[0-9]+` (e.g., `PROJ-123`, `AB-1`, `MYAPP-4567`)
   - The JIRA ID can appear anywhere in the branch name (e.g., `fix/proj-123`, `feat/PROJ-123`, `PROJ-123-some-description`)
   - The match should be case-insensitive — normalize the extracted ID to uppercase for the JIRA API lookup
   - If no JIRA ID is found, continue without stopping — you will use the **no-JIRA-ticket path** after pushing (see step 8)

4. **Fetch JIRA ticket details (only if a JIRA ID was found in step 3):**
   - **Atlassian CLI (`acli`):** Run `acli auth status` to check if the CLI is installed and authenticated.
     - If the command is not found, display the following message and **STOP**:
       ```
       ## Missing Prerequisite: Atlassian CLI

       The `acli` command is not installed. A JIRA ID was found in the branch name; install the CLI to load the ticket, or rename the branch to remove the JIRA ID if you want a PR without JIRA.

       Install it with: brew tap atlassian/acli && brew install acli
       ```
     - If the command fails with an authentication error, display the following message and **STOP**:
       ```
       ## Missing Prerequisite: Atlassian CLI Authentication

       The Atlassian CLI is not authenticated. Please run `acli auth login` to authenticate, or fix the branch/ticket access before continuing.
       ```
   - Use the Atlassian CLI to retrieve the issue by its JIRA ID:
     ```bash
     acli jira workitem view <JIRA-ID> --fields summary,description,issuetype --json
     ```
   - If the command succeeds, extract **summary**, **description**, **issue type** (Bug, Story, Task, etc.) — you have **JIRA context** for step 8
   - If the command fails (ticket missing, permission, network, etc.), inform the developer briefly and continue on the **no-JIRA-ticket path** in step 8 (do **not** stop). You may still know the raw `JIRA-ID` string for an optional link in the description if you can form a correct browse URL; otherwise omit it

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

7. **Identify the issues this PR fixes or addresses:**

   The goal is to build a list of **only the items this PR actually fixes or addresses** — never related items, dependencies, or items merely mentioned in passing.

   **a) Collect candidate references from all available sources:**
   - **Branch name:** any JIRA ID from step 3, and any GitHub issue-number hints — patterns like `issue-123`, `gh-123`, a leading numeric segment such as `123-some-description`, or `#123`.
   - **Commit messages on this branch:** run `git log <base-branch>..HEAD --pretty=%B` and scan the output for:
     - GitHub issue refs: `#NNN`, `GH-NNN`, or cross-repo `owner/repo#NNN`
     - Closing-keyword refs: `Fixes #NNN`, `Closes #NNN`, `Resolves #NNN` (any case)
     - Additional JIRA keys matching `[A-Z][A-Z0-9]+-[0-9]+`
   - **PR title (if from JIRA):** the JIRA key is already a candidate.

   **b) Filter to items this PR actually fixes/addresses:**
   - Include a reference only when the PR's changes resolve or implement that item. Use these signals:
     - Branch name's primary JIRA ID (from step 3) and any GitHub issue number embedded in the branch name → almost always being addressed by this PR; include them.
     - A reference appearing with a closing keyword (`Fixes`, `Closes`, `Resolves`) in a commit on this branch → include it.
     - A bare `#NNN` mention in a commit message → only include if the commit body clearly indicates the PR resolves that issue; otherwise treat as related and **exclude**.
     - Additional JIRA keys mentioned in commits without explicit "fixes/addresses" intent → exclude as related context.
   - **When uncertain whether a candidate is being fixed vs merely related, ask the developer** with `AskUserQuestion` listing the ambiguous candidates, each with options **"This PR fixes it — include"** and **"Just related — exclude"**. Skip the prompt entirely if there are no ambiguous candidates.
   - Deduplicate the final list.

   **c) Format the references for the PR body:**
   - **JIRA tickets:** `[PROJ-123](https://<site>.atlassian.net/browse/PROJ-123)` followed by the ticket summary if known (e.g., ` — Add bulk export`). Use the same `<site>` host you confirmed during the `acli` lookup.
   - **GitHub issues (same repo):** use a closing keyword so GitHub auto-closes on merge — `Fixes #123` (prefer `Fixes` for bugs, `Closes` otherwise; either works for auto-close).
   - **GitHub issues (cross-repo):** `Fixes owner/repo#123`.

   Keep the result for step 8. If the filtered list is empty, there will be no `## Fixes` section.

8. **Create the pull request:**

   **If you have JIRA context from step 4 (successful fetch):**
   - Build the PR title using the commit prefix convention based on issue type, followed by a concise summary derived from the JIRA ticket summary:
     - Bug → `fix: <summary>` (e.g., `fix: resolve null pointer in user lookup`)
     - All other types → `feat: <summary>` (e.g., `feat: add bulk export for reports`)
     - The summary part should be lowercase, imperative mood, and concise
   - Build the PR description:
     - `## Summary` — a brief description based on the JIRA ticket description.
     - `## Fixes` — list every confirmed reference from step 7, one per line as a bullet. Always include the branch's JIRA ticket here as the first bullet. Omit the section entirely only if step 7 produced an empty list (which should be rare when JIRA context exists).
   - Run `gh pr create` with that title and body (see below for shared flags)

   **If you do not have JIRA context (no JIRA ID in branch, or fetch failed in step 4):**
   - Gather hints: branch name (without remote prefixes), and the latest commit subject (e.g. `git log -1 --pretty=%s`); optionally the first line of the commit body
   - Use `AskUserQuestion` so the developer **chooses a PR title** before `gh pr create`. Present **at least three distinct options**, for example:
     - A conventional title derived from the branch slug (imperative, lowercase phrase after `feat:`, `fix:`, or `chore:` — pick `fix:` if the branch suggests a bugfix, else prefer `feat:` unless the change is clearly chore/docs-only, then `chore:`)
     - A title based on the latest commit subject (adjust to conventional form if needed)
     - A shorter or alternative wording
     - Plus an option for the developer to **enter a custom title** (free text), if your tool supports it
   - After the developer selects a title, build the PR description:
     - `## Summary` — brief explanation from the branch name and recent commit message(s). If a JIRA ID was known but the ticket could not be loaded, you may add a sentence noting the intended ticket key.
     - `## Fixes` — list every confirmed reference from step 7, one per line as a bullet. Omit the section entirely if step 7 produced an empty list.
   - Run `gh pr create` with the chosen title and that body

   **Shared `gh pr create` behavior:**
   - Use `--draft` flag unless `--no-draft` was passed. **Exception:** if the push in step 6 used `--no-verify`, always use `--draft` regardless of the `--no-draft` option, and inform the developer:
     ```
     ⚠️ PR created as draft because pre-push checks were skipped (--no-verify).
     Mark it as ready for review after ensuring all checks pass.
     ```
   - Use `--base <base-branch>` with the branch determined in step 5
   - Use a HEREDOC to pass the body
   - If PR creation fails, show the error and **STOP**

9. **Show success message:**

   Display a summary with all relevant information. List every reference included in the `## Fixes` section, or state "none" if the section was omitted:

   ```
   ## PR Created

   - Fixes: PROJ-123, #45 (or "none")
   - Branch: my-branch → main
   - PR: https://github.com/org/repo/pull/42 (draft)
   - Title: <chosen title>
   ```
