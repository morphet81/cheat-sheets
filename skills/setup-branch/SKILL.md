---
name: setup-branch
description: Create a new branch and worktree from a JIRA ID or URL. Determines branch prefix (fix/ or feat/) from the JIRA item type, sets up the worktree one level up, and runs npm ci.
argument-hint: "<JIRA-ID or URL>"
---

Create a new git branch and worktree from a JIRA ticket. Automatically names the branch based on the JIRA item type and sets up the worktree ready to work in.

**Usage:**
- `/setup-branch PROJ-123` - Create branch from JIRA ID
- `/setup-branch https://mycompany.atlassian.net/browse/PROJ-123` - Create branch from JIRA URL

**Instructions:**

1. **Parse the JIRA reference from $ARGUMENTS:**
   - If the argument is a URL (contains `atlassian.net/browse/` or similar), extract the JIRA ID from the URL path (e.g., `https://mycompany.atlassian.net/browse/PROJ-123` → `PROJ-123`)
   - If the argument is already a JIRA ID (matches pattern like `PROJ-123`, `ABC-1`, etc.), use it directly
   - If no argument is provided or it cannot be parsed, inform the user and STOP

2. **Fetch the JIRA item type:**
   - Use the JIRA MCP tool or API to fetch the issue details for the extracted JIRA ID
   - Identify the issue type (Bug, Story, Task, Epic, Sub-task, etc.)
   - If the JIRA API is not available or the fetch fails, ask the developer to provide the issue type manually using `AskUserQuestion` with options: "Bug", "Story/Task/Other"

3. **Determine the branch name:**
   - If the issue type is **Bug**: branch name is `fix/<JIRA-ID>` (e.g., `fix/PROJ-123`)
   - For **all other types** (Story, Task, Epic, Sub-task, etc.): branch name is `feat/<JIRA-ID>` (e.g., `feat/PROJ-123`)

4. **Ask which base branch to branch from:**
   - Use `AskUserQuestion` to ask the developer which branch to use as the base
   - Default option should be `main`
   - Let the developer type a different branch name via the "Other" option

5. **Fetch and pull the base branch:**
   - Run `git fetch origin <base-branch>`
   - If the current branch is not the base branch, run `git checkout <base-branch>`
   - Run `git pull origin <base-branch>`
   - **If any of these commands fail, show the error and STOP immediately.** Do not continue with branch or worktree creation.

6. **Create the new branch and worktree together:**
   - Determine the worktree path: take the **parent directory** of the current working directory and append the branch name with `/` replaced by `-`
     - Example: if CWD is `/Users/dev/my-project` and branch is `fix/PROJ-123`, the worktree path is `/Users/dev/fix-PROJ-123`
   - Run `git worktree add <worktree-path> -b <branch-name>`
     - This creates the new branch AND the worktree in a single command
   - If the command fails (e.g., branch already exists, worktree path conflict), show the error and STOP

7. **Install dependencies in the new worktree:**
   - Change to the worktree directory
   - Run `npm ci`
   - If `npm ci` fails, show the error but do NOT delete the worktree — the developer may want to fix the issue manually

8. **Show success message:**

   Display a summary with all relevant information:

   ```
   ## Branch Setup Complete

   - JIRA: PROJ-123
   - Type: Bug → fix/PROJ-123
   - Base: main
   - Worktree: /Users/dev/fix-PROJ-123
   - Dependencies: installed (npm ci)

   To start working:
     cd /Users/dev/fix-PROJ-123
   ```

9. **Handle edge cases:**
   - If no argument is provided, inform the user of the expected usage and STOP
   - If the JIRA ID cannot be parsed from the URL, show what was received and STOP
   - If the branch name already exists locally, inform the user and STOP (do not force-create)
   - If the worktree directory already exists, inform the user and STOP
   - If the base branch does not exist on the remote, show the error and STOP
   - If `npm ci` fails, still show the success message for branch/worktree creation but warn about the failed install
