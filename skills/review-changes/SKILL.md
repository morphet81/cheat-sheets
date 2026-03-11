---
name: review-changes
version: 3.0.0
description: Review code changes in two modes — local branch review (compare current branch against a base branch) or PR review (review an open pull request on GitHub). Spawns a specialized team of 8 reviewer agents covering code quality, security, performance, best practices, testing, and documentation. In PR mode, builds an exclusion list from existing reviews, optionally spawns a 9th ticket-compliance agent if a Jira ticket is referenced, and posts findings as GitHub review comments.
argument-hint: "[base-branch] or <PR number or URL> [repository]"
---

Review code changes in two modes: **local branch review** or **PR review**.

**Usage:**
- `/review-changes` — Compare current branch against `main`
- `/review-changes <branch>` — Compare current branch against specified branch
- `/review-changes <PR-number>` — Review PR in current repo
- `/review-changes <PR-number> <owner/repo>` — Review PR in specific repo
- `/review-changes <PR-URL>` — Review PR by URL

**Instructions:**

1. **Parse arguments and determine mode:**

   - If `$ARGUMENTS` contains a GitHub PR URL (matches `https://github.com/.../pull/\d+`) → **PR mode** (extract owner, repo, and PR number from the URL)
   - If `$ARGUMENTS` is a pure number (e.g., `1654`) → **PR mode** (use as PR number; if a second argument is provided, use it as `owner/repo`, otherwise run `gh repo view --json nameWithOwner -q .nameWithOwner` to get the current repo)
   - Otherwise → **local branch mode**:
     - If an argument is provided, use it as the base branch
     - Otherwise, check if a `.agent` file exists in the current directory. If it contains a `baseBranch=<value>` line, use that value
     - If no argument and no `.agent` file, default to `main`

---

## Local Branch Mode

2. **Gather branch changes:**

   - Get the current branch name and verify we're not on the base branch
   - Run `git diff <base-branch>...HEAD` to see all changes
   - Run `git log <base-branch>..HEAD --oneline` to see commit history
   - Run `git diff --name-only <base-branch>...HEAD` to get the list of changed files

3. **Spawn the review team** (see [Step 3: Spawn the review team](#step-3-spawn-the-review-team) below)

4. **Review, consolidation, output** (see [Steps 4-6](#steps-4-6-review-consolidation-output) below)

5. **Address findings locally:**

   After presenting the consolidated review, ask the user which findings they want addressed using `AskUserQuestion`. The team fixes the selected issues locally in the code.

6. **Cleanup** (see [Step 8: Cleanup](#step-8-cleanup) below)

---

## PR Mode

2. **Gather PR context:**

   **a) Verify the PR exists and gather metadata:**
   ```bash
   gh pr view <number> --repo <owner/repo> --json number,title,url,state,baseRefName,headRefName,author,additions,deletions,changedFiles,files
   ```
   - If the PR does not exist or is not open, display an error and **STOP**
   - Store the PR metadata for later reference

   **b) Fetch the full diff and changed files:**
   ```bash
   gh pr diff <number> --repo <owner/repo>
   ```
   ```bash
   gh pr view <number> --repo <owner/repo> --json files --jq '.files[].path'
   ```
   - If the diff is extremely large (more than 5000 lines), note this for the reviewers so they can focus on the most impactful changes

   **c) Check for Jira ticket reference:**
   - Scan the PR title, description, and branch name for a Jira ticket reference (pattern: project key + number, e.g., `PROJ-123`, `ABC-42`)
   - If found, attempt to fetch Jira ticket details (summary, description, acceptance criteria) using available tools (`jira-mcp` or similar)
   - Store the ticket details for the review team; if fetch fails, note the ticket reference but proceed without details

   **d) Build the exclusion list:**

   These findings must be **excluded** from the final review output to avoid duplication.

   - **Existing reviews:** Fetch all submitted reviews:
     ```bash
     gh api repos/{owner}/{repo}/pulls/{number}/reviews --paginate
     ```
     For each review, record: author, state (APPROVED, CHANGES_REQUESTED, COMMENTED), review body.

   - **Review comments (inline):**
     ```bash
     gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate
     ```
     For each comment, record: file path, line number, body, author.

   - **Unresolved review threads:**
     ```bash
     gh api graphql -f query='
       query($owner: String!, $repo: String!, $pr: Int!) {
         repository(owner: $owner, name: $repo) {
           pullRequest(number: $pr) {
             reviewThreads(first: 100) {
               nodes {
                 id
                 isResolved
                 comments(first: 20) {
                   nodes {
                     body
                     path
                     line
                     author { login }
                   }
                 }
               }
             }
           }
         }
       }
     ' -f owner='{owner}' -f repo='{repo}' -F pr={number}
     ```
     Collect all **unresolved** threads with their file paths, line numbers, and comment bodies.

   - **General PR conversation comments:**
     ```bash
     gh api repos/{owner}/{repo}/issues/{number}/comments --paginate
     ```
     Record substantive comments (skip bot comments and simple acknowledgements).

   - **Compile the exclusion list** with: file path + line (if applicable), summary of the issue raised, author.

3. **Spawn the review team** (see [Step 3: Spawn the review team](#step-3-spawn-the-review-team) below)

   **PR mode additions:**
   - All reviewers also receive the exclusion list with instructions: "Do NOT report these issues — they have already been raised in existing reviews or unresolved comments."
   - If a Jira ticket was found, spawn a 9th agent: `ticket-compliance` (see table below)

4. **Review, consolidation, output** (see [Steps 4-6](#steps-4-6-review-consolidation-output) below)

   **PR mode additions to consolidation:**
   - Re-check all findings against the exclusion list — remove any finding that overlaps with existing reviews or unresolved comments
   - If a `ticket-compliance` agent participated, include a "Ticket Compliance" section in the report noting any gaps between the code changes and the Jira ticket requirements

5. **Post findings as PR review comments:**

   After presenting the consolidated review, ask the user which findings they want posted as PR review comments using `AskUserQuestion`:

   > Here are the findings from the review. Which ones would you like me to post as review comments on the PR?
   >
   > Please provide the finding numbers (e.g., "1, 3, 5" or "all" or "none").

   - If the user says "none", skip to cleanup
   - If the user says "all", select every finding
   - Otherwise, parse the comma-separated list of finding numbers
   - Confirm the selection back to the user before proceeding

   **a) Determine the authenticated user:**
   ```bash
   gh api user --jq .login
   ```

   **b) Check for an existing pending review by the user:**
   ```bash
   gh api graphql -f query='
     query($owner: String!, $repo: String!, $pr: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $pr) {
           reviews(states: PENDING, first: 10) {
             nodes {
               id
               author { login }
             }
           }
         }
       }
     }
   ' -f owner='{owner}' -f repo='{repo}' -F pr={number}
   ```
   - If a pending review exists for the authenticated user: use its `id` as `review_id`, set `agent_created_review = false`
   - If no pending review: set `agent_created_review = true`

   **c) Create a pending review if none exists:**
   ```bash
   gh api graphql -f query='
     mutation($prId: ID!) {
       addPullRequestReview(input: {pullRequestId: $prId}) {
         pullRequestReview {
           id
         }
       }
     }
   ' -f prId='{pullRequest_node_id}'
   ```
   To get the PR node ID (if not already available):
   ```bash
   gh api graphql -f query='
     query($owner: String!, $repo: String!, $pr: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $pr) {
           id
         }
       }
     }
   ' -f owner='{owner}' -f repo='{repo}' -F pr={number}
   ```

   **d) Determine the latest commit SHA:**
   ```bash
   gh pr view <number> --repo <owner/repo> --json commits --jq '.commits[-1].oid'
   ```

   **e) Add review comments for each selected finding:**

   Every comment body must start with a `## From AI agent` heading. Format:
   ```
   ## From AI agent

   **[<severity>]** <title>

   <explanation from the consolidated review>

   **Suggested fix:** <suggestion if applicable>

   **Confidence:** <High|Medium|Debated>
   ```

   Add each comment using the GraphQL `addPullRequestReviewThread` mutation:
   ```bash
   gh api graphql -f query='
     mutation($reviewId: ID!, $body: String!, $path: String!, $line: Int!, $side: DiffSide!) {
       addPullRequestReviewThread(input: {
         pullRequestReviewId: $reviewId,
         body: $body,
         path: $path,
         line: $line,
         side: RIGHT
       }) {
         thread {
           id
         }
       }
     }
   ' -f reviewId='{review_id}' -f body='{comment_body}' -f path='{file_path}' -F line={line_number}
   ```
   - If a finding references a range of lines, use the last line
   - If a finding has no specific line number, fall back to a top-level review body comment

   **f) Submit the review (only if agent-created):**
   ```bash
   gh api graphql -f query='
     mutation($reviewId: ID!, $event: PullRequestReviewEvent!) {
       submitPullRequestReview(input: {
         pullRequestReviewId: $reviewId,
         event: $event
       }) {
         pullRequestReview {
           id
           state
         }
       }
     }
   ' -f reviewId='{review_id}' -f event='COMMENT'
   ```
   If `agent_created_review` is `false`, do **NOT** submit. Inform the user:
   > Comments have been added to your existing pending review. Submit it when you're ready from the GitHub UI.

   **g) Report what was posted:**
   ```
   ## Review Comments Posted

   **PR:** #<number> — <title>
   **Review:** <"New review created and submitted" | "Added to your existing pending review">
   **Comments posted:** <count>

   - #<N> — `<file>:<line>` — <title> — Posted ✓
   - #<N> — `<file>:<line>` — <title> — Posted ✓
   ...
   ```

6. **Cleanup** (see [Step 8: Cleanup](#step-8-cleanup) below)

---

## Shared Steps

### Step 3: Spawn the review team

Use `TeamCreate` with name `review-changes`. Spawn all agents simultaneously using the `Agent` tool (`subagent_type: general-purpose`) with `run_in_background: true` and the team name.

**Shared instructions for all reviewers:**
> Focus exclusively on the changes introduced (in the diff). Only review code that was added or modified — do not flag pre-existing issues in surrounding code that was not changed. The goal is to review what these changes introduce, not to audit the entire codebase.

Each reviewer receives the full diff, the list of changed files, and their specific focus area:

| # | Name | Role | Focus |
|---|------|------|-------|
| 1 | `code-quality` | Code Quality Engineer | Bugs, edge cases, error handling issues |
| 2 | `security` | Security Engineer | Vulnerabilities: injection, XSS, secrets exposure, auth issues |
| 3 | `performance` | Performance Engineer | Inefficiencies, bottlenecks, unnecessary allocations, resource usage |
| 4 | `best-practices` | Best Practices Engineer | Coding standards, design patterns, conventions, code consistency |
| 5 | `qa-coverage` | QA Engineer (Coverage) | Missing tests for new or changed functionality |
| 6 | `qa-consistency` | QA Engineer (Consistency) | Do test descriptions match actual test logic? Do tests make sense? Are there redundant tests? |
| 7 | `documentation` | Documentation Engineer | Missing or outdated documentation, changelog needs, inline comment gaps |
| 8 | `senior-lead` | Senior Engineer (Lead) | See below |
| 9 | `ticket-compliance` | Ticket Compliance Engineer | *(PR mode only, if Jira ticket found)* Compare code changes against Jira ticket requirements and acceptance criteria, report any gaps or missing items |

**Senior Engineer responsibilities:**
- Available throughout the review to answer questions and assist other reviewers — reviewers should message `senior-lead` when they need guidance or want to validate a finding
- Once all specialists have reported their findings, verify each finding for accuracy and relevance
- Orchestrate a team-wide conversation (via `broadcast` and direct messages) where reviewers share findings and debate the best approaches
- Produce the final consolidated report (step format below) incorporating the team's discussion
- After the final report is ready, clean up: send `shutdown_request` to each reviewer, then `TeamDelete`

**Ticket Compliance Engineer** *(only spawned in PR mode when a Jira ticket is referenced)*:
- Receives the Jira ticket details (summary, description, acceptance criteria) and the full diff
- Compares the code changes against every requirement and acceptance criterion in the ticket
- Reports: which requirements are addressed, which are partially addressed, and which are missing entirely
- Messages `senior-lead` with the compliance assessment

### Steps 4-6: Review, consolidation, output

4. Each specialist reviewer must:
   - Read the full diff and changed files relevant to their focus area
   - Message `senior-lead` with their findings (or confirm no issues found)
   - Mark their task as completed
   - Respond to any follow-up questions from `senior-lead` during the team discussion

5. The senior-lead consolidates all findings and produces the report.

6. Format the review as:
   - Start with a brief summary of what the changes do
   - List specific issues found with file paths and line references
   - Categorize feedback by severity: 🔴 Critical, 🟡 Warning, 🔵 Suggestion
   - **Assign a sequential number to each finding** (e.g., #1, #2, #3) across all severity categories, so the developer can easily reference specific findings (e.g., "fix #3, dismiss #5")
   - End with an overall assessment and recommendation

**Example output format:**

```
## Summary
Brief description of what the changes introduce.

## Changes Reviewed
- `path/to/file.ts` - Description of changes
- `path/to/other.ts` - Description of changes

## Findings

### 🔴 Critical
- **#1** — **file.ts:42** - Description of critical issue
- **#2** — **file.ts:58** - Description of another critical issue

### 🟡 Warnings
- **#3** — **other.ts:15** - Description of warning

### 🔵 Suggestions
- **#4** — **file.ts:78** - Suggestion for improvement
- **#5** — **other.ts:90** - Another suggestion

## Ticket Compliance (PR mode only, if applicable)
- ✅ Requirement A — addressed in `file.ts`
- ⚠️ Requirement B — partially addressed, missing edge case handling
- ❌ Requirement C — not addressed in this PR

## Overall Assessment
Summary and recommendation (approve, request changes, etc.)
```

### Step 8: Cleanup

- Send `shutdown_request` to all agents via `SendMessage`
- Once confirmed, call `TeamDelete`
- Present the final summary to the user

---

## Edge Cases

- If the PR diff is empty, report "No changes to review" and **STOP**
- If `gh` is not authenticated (PR mode), display setup instructions and **STOP**
- If the exclusion list is very large (>30 items), summarize it for reviewers by grouping related items
- If reviewers find no new issues beyond the exclusion list, report: "No new issues found beyond the <N> already-raised items in existing reviews."
- If the PR URL points to a different host (e.g., GitHub Enterprise), pass the full URL to `gh` commands which handle enterprise hosts automatically
- If a GraphQL mutation fails when posting a comment (e.g., invalid line number because the diff has changed), skip that comment, log a warning, and continue with the remaining comments
- If all comment postings fail, inform the user and suggest they post manually based on the findings
