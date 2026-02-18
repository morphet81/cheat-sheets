---
name: address-comments
version: 1.0.0
description: Retrieve unresolved PR review comments from the current branch's pull request, propose a plan to address them, and optionally use Claude Teams for parallel execution.
argument-hint: ""
---

Retrieve unresolved review comments from the current branch's PR, analyze them, propose a plan to address each comment, and implement the fixes after developer approval.

**Usage:**
- `/address-comments` - Fetch and address unresolved PR comments for the current branch

**Instructions:**

1. **Check for Claude Teams:**

   Before doing any work, check whether Claude Teams (multi-agent parallel execution) is available and offer it to the developer.

   **a) Detect availability:**
   - Run `echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` via the Bash tool to check the environment variable
   - If the value is not `1`, Claude Teams is not enabled — skip this step silently

   **b) Ask the developer:**
   - If the environment variable is `1`, use `AskUserQuestion` to ask:
     > Claude Teams is available on this machine. Would you like to enable parallel agents to address comments? Teams mode will assign independent comments to separate agents for faster execution.
   - Provide two options: **Yes — use Teams** and **No — single agent**

   **c) Remember the decision:**
   - Store the developer's choice internally for use in step 6

2. **Identify the PR for the current branch:**
   - Run `git branch --show-current` to get the current branch name
   - Run `gh pr view --json number,title,url,state` to find the PR associated with the current branch
   - If no PR exists for the current branch, display the following error and STOP:
     ```
     ❌ No pull request found for branch "<current-branch>".
     Please create a PR first, then run /address-comments.
     ```
   - If the PR is closed or merged, display a warning:
     ```
     ⚠️ PR #<number> is <state>. Comments may no longer be actionable.
     ```
     Then use `AskUserQuestion` to ask the developer if they want to continue anyway.

3. **Retrieve unresolved review comments:**
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
     ✅ No unresolved review comments on PR #<number>. Nothing to address!
     ```

4. **Analyze comments and the codebase:**
   - For each unresolved comment thread:
     - Read the referenced file and surrounding code to understand the context
     - Understand what the reviewer is asking for (code change, question, suggestion, concern)
     - Categorize the comment:
       - **Code change** — reviewer wants specific code modifications
       - **Question** — reviewer is asking for clarification (may need a reply, not a code change)
       - **Suggestion** — reviewer suggests an improvement (optional but recommended)
       - **Concern** — reviewer flags a potential issue that needs investigation
   - Cross-reference related comments that touch the same file or area of code

5. **Propose an implementation plan using Plan Mode:**

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

6. **Implement the approved plan:**

   After the developer approves the plan:

   **If Claude Teams is enabled (from step 1):**
   - Group comments by independence: comments affecting different files or non-overlapping code regions can be addressed in parallel
   - Use the `Task` tool with `run_in_background: true` to spawn parallel agents for independent groups of comments
   - Each agent should:
     - Make the required code changes for its assigned comments
     - Ensure changes don't conflict with other agents' work
   - Wait for all agents to complete, then verify there are no conflicts
   - Handle comments requiring replies (questions) sequentially after code changes

   **If Claude Teams is not enabled:**
   - Address each comment sequentially in the order presented in the plan
   - For code changes: modify the relevant files
   - For questions: note the reply to be posted

   **For all comment types:**
   - **Code changes:** Make the modifications, ensuring they follow existing code patterns and conventions
   - **Questions:** Draft a reply for the developer to review
   - **Suggestions:** Implement the improvement as planned
   - **Concerns:** Address the concern with appropriate code changes or explanations

7. **Report results:**

   After all comments are addressed, provide a summary:

   ```
   ## Comments Addressed

   ### ✅ Code Changes Made
   - **Comment #1** (`file.ts:42`) — <brief description of change>
   - **Comment #3** (`other.ts:15`) — <brief description of change>

   ### 💬 Replies Drafted
   - **Comment #2** (`file.ts:78`) — <draft reply for developer to review>

   ### Files Modified
   - `path/to/file.ts`
   - `path/to/other.ts`

   ### Next Steps
   - Review the changes and reply drafts
   - Run tests to verify nothing is broken
   - Push the changes and mark comment threads as resolved
   ```

8. **Handle edge cases:**
   - If `gh` CLI is not installed or not authenticated, display an error and STOP:
     ```
     ❌ GitHub CLI (gh) is not installed or not authenticated.
     Please install gh and run `gh auth login` before using /address-comments.
     ```
   - If a comment references a file that no longer exists, note it and skip
   - If a comment references lines that have changed since the review, read the current file and adapt the fix to the current code
   - If two comments conflict with each other (e.g., one says "add X" and another says "don't add X"), flag the conflict in the plan and ask the developer to decide
   - If a comment is ambiguous or unclear, include it in the plan with a note asking the developer for clarification
