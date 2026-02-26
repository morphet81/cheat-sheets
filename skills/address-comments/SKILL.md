---
name: address-comments
version: 1.1.0
description: Retrieve unresolved PR review comments from the current branch's pull request, propose a plan to address them, and spawn a developer team to implement fixes in parallel.
argument-hint: ""
---

Retrieve unresolved review comments from the current branch's PR, analyze them, propose a plan to address each comment, and implement the fixes after developer approval using a coordinated developer team.

**Usage:**
- `/address-comments` - Fetch and address unresolved PR comments for the current branch

**Instructions:**

1. **Identify the PR for the current branch:**
   - Run `git branch --show-current` to get the current branch name
   - Run `gh pr view --json number,title,url,state` to find the PR associated with the current branch
   - If no PR exists for the current branch, display the following error and STOP:
     ```
     No pull request found for branch "<current-branch>".
     Please create a PR first, then run /address-comments.
     ```
   - If the PR is closed or merged, display a warning:
     ```
     PR #<number> is <state>. Comments may no longer be actionable.
     ```
     Then use `AskUserQuestion` to ask the developer if they want to continue anyway.

2. **Retrieve unresolved review comments:**
   - Run `gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --paginate` to get all PR review comments
   - Filter for unresolved comments: look at the `position` and `in_reply_to_id` fields to identify top-level comment threads
   - Also run `gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews --paginate` to get review-level comments
   - For each comment thread, determine if it is resolved or unresolved:
     - Use `gh api graphql` if needed to check the `isResolved` status of review threads:
       ```bash
       gh api graphql -f query='
         query($owner: String!, $repo: String!, $pr: Int!) {
           repository(owner: $owner, name: $repo) {
             pullRequest(number: $pr) {
               reviewThreads(first: 100) {
                 nodes {
                   isResolved
                   comments(first: 10) {
                     nodes {
                       body
                       path
                       line
                       author { login }
                       createdAt
                     }
                   }
                 }
               }
             }
           }
         }
       ' -f owner='{owner}' -f repo='{repo}' -F pr={pr_number}
       ```
   - Collect only **unresolved** threads with their:
     - File path and line number
     - Comment body (the full thread — original comment + replies)
     - Author
   - If there are no unresolved comments, inform the developer and STOP:
     ```
     No unresolved review comments on PR #<number>. Nothing to address!
     ```

3. **Analyze comments and the codebase:**
   - For each unresolved comment thread:
     - Read the referenced file and surrounding code to understand the context
     - Understand what the reviewer is asking for (code change, question, suggestion, concern)
     - Categorize the comment:
       - **Code change** — reviewer wants specific code modifications
       - **Question** — reviewer is asking for clarification (may need a reply, not a code change)
       - **Suggestion** — reviewer suggests an improvement (optional but recommended)
       - **Concern** — reviewer flags a potential issue that needs investigation
   - Cross-reference related comments that touch the same file or area of code

4. **Propose an implementation plan using Plan Mode:**

   Use `EnterPlanMode` to switch to plan mode, then write the plan. This ensures the developer reviews and approves before any changes are made.

   Structure the plan as follows:

   ```
   ## PR Comments: #<pr-number> — <PR title>
   **Unresolved comments:** <count>

   ### Comment #1 — `<file>:<line>` — @<author>
   > <quoted comment body (abbreviated if long)>

   **Category:** Code change | Question | Suggestion | Concern
   **Plan:** <Brief description of how to address this comment>
   **Files:** `path/to/file.ts` — <what changes are needed>

   ### Comment #2 — `<file>:<line>` — @<author>
   > <quoted comment body>

   **Category:** Question
   **Plan:** Reply to the reviewer explaining <...>. No code change needed.

   ### Comment #3 — `<file>:<line>` — @<author>
   > <quoted comment body>

   **Category:** Suggestion
   **Plan:** <Brief description of the improvement>
   **Files:** `path/to/file.ts` — <what changes are needed>

   ...

   ### Summary
   - **Code changes:** <N> comments requiring code modifications
   - **Replies only:** <N> comments that need a reply but no code change
   - **Files affected:** <list of unique files>
   ```

   Use `ExitPlanMode` to present the plan for developer approval. Only proceed with implementation after the developer approves.

5. **Implement the approved plan:**

   After the developer approves, spawn a team to address the comments in parallel.

   **a) Create the team:**
   - Use `TeamCreate` with name `address-comments-<pr-number>`

   **b) Determine team size** based on the number of comments requiring code changes:
   - 1–2 comments → 1 developer agent
   - 3–5 comments → 2 developer agents
   - 6+ comments → 3 developer agents
   - Comments that only need a reply (no code change) are handled by the team lead directly — they do not count toward team size

   **c) Divide work:**
   - Group comments so that comments touching the **same file or overlapping code** go to the **same developer** to avoid conflicts
   - Balance workload roughly evenly across developers

   **d) Spawn developers** using the `Task` tool (`subagent_type: general-purpose`) with `run_in_background: true` and the team name:
   - Each developer receives their assigned comments with the approved fix descriptions, relevant file paths, and code context
   - Developers must communicate with each other via `SendMessage` to coordinate:
     - Before editing a file, read the latest version (another developer may have changed it)
     - After editing, message the team with which files and line ranges were modified
   - Developers must **not commit** — only make code changes and mark tasks as completed

   **e) Monitor and finalize:**
   - Wait for all developers to finish
   - Review combined changes with `git diff` to check for conflicts
   - Resolve any conflicts or overlapping changes
   - Handle reply-only comments (questions) directly — draft the replies

   **f) Clean up the team:**
   - Send `shutdown_request` to each developer via `SendMessage`
   - Once all confirm, call `TeamDelete`

6. **Report results:**

   After all comments are addressed, provide a summary:

   ```
   ## Comments Addressed

   ### Code Changes Made
   - **Comment #1** (`file.ts:42`) — <brief description of change>
   - **Comment #3** (`other.ts:15`) — <brief description of change>

   ### Replies Drafted
   - **Comment #2** (`file.ts:78`) — <draft reply for developer to review>

   ### Files Modified
   - `path/to/file.ts`
   - `path/to/other.ts`

   ### Next Steps
   - Review the changes and reply drafts
   - Run tests to verify nothing is broken
   - Push the changes and mark comment threads as resolved
   ```

7. **Handle edge cases:**
   - If `gh` CLI is not installed or not authenticated, display an error and STOP:
     ```
     GitHub CLI (gh) is not installed or not authenticated.
     Please install gh and run `gh auth login` before using /address-comments.
     ```
   - If a comment references a file that no longer exists, note it and skip
   - If a comment references lines that have changed since the review, read the current file and adapt the fix to the current code
   - If two comments conflict with each other (e.g., one says "add X" and another says "don't add X"), flag the conflict in the plan and ask the developer to decide
   - If a comment is ambiguous or unclear, include it in the plan with a note asking the developer for clarification
