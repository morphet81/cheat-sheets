---
name: review-changes
version: 3.8.0
description: Review code changes in two modes — local branch review (compare current branch against a base branch) or PR review (review an open pull request on GitHub). By default, performs a solo review covering all focus areas. With `--team`, spawns a specialized team of 8 reviewer agents covering code quality, security, performance, best practices, testing, and documentation. In PR mode, builds an exclusion list from existing reviews, optionally spawns a 9th ticket-compliance agent if a Jira ticket is referenced, and posts findings as pending review comments (never submits the review — the developer submits it manually). Use `--headless` for fully autonomous execution where a challenger agent validates findings instead of asking the developer.
argument-hint: "[--team] [--headless] [base-branch] or <PR number or URL> [repository]"
---

Review code changes in two modes: **local branch review** or **PR review**.

**Usage:**
- `/review-changes` — Compare current branch against `main` (solo review)
- `/review-changes <branch>` — Compare current branch against specified branch (solo review)
- `/review-changes --team` — Compare current branch against `main` with a team of 8 specialist agents
- `/review-changes --team <branch>` — Compare against specified branch with a team
- `/review-changes <PR-number>` — Review PR in current repo (solo review)
- `/review-changes <PR-number> <owner/repo>` — Review PR in specific repo (solo review)
- `/review-changes <PR-URL>` — Review PR by URL (solo review)
- Add `--team` to any command above to spawn a specialized review team instead of reviewing solo
- Add `--headless` to any command above for fully autonomous execution (a challenger agent validates findings instead of asking the developer)

**Instructions:**

1. **Parse arguments and determine mode:**

   Scan `$1`, `$2`, `$3` for flags (`--team`, `--headless`). The first non-flag argument is the **target argument**; the second non-flag argument (if any) is the **extra argument** (used as `owner/repo` in PR mode).

   - If any argument is `--team`, set **team mode = true**. Otherwise, set **team mode = false** (solo review).
   - If any argument is `--headless`, set **headless = true**. Otherwise, set **headless = false**.
   - If the target argument is a GitHub PR URL (matches `https://github.com/.../pull/\d+`) → **PR mode** (extract owner, repo, and PR number from the URL)
   - If the target argument is a pure number (e.g., `1654`) → **PR mode** (use as PR number; if the extra argument is provided, use it as `owner/repo`, otherwise run `gh repo view --json nameWithOwner -q .nameWithOwner` to get the current repo)
   - Otherwise → **local branch mode**:
     - If the target argument is provided, use it as the base branch
     - Otherwise, check if a `.agent` file exists in the current directory. If it contains a `baseBranch=<value>` line, use that value
     - If no target argument and no `.agent` file, default to `main`

---

## Local Branch Mode

2. **Gather branch changes:**

   - Get the current branch name and verify we're not on the base branch
   - Run `git diff <base-branch>...HEAD` to see all changes
   - Run `git log <base-branch>..HEAD --oneline` to see commit history
   - Run `git diff --name-only <base-branch>...HEAD` to get the list of changed files

3. **Review the changes:**

   - **If team mode:** Spawn the review team (see [Step 3: Spawn the review team](#step-3-spawn-the-review-team) below), then follow [Steps 4-6](#steps-4-6-review-consolidation-output) for review, consolidation, and output.
   - **If solo mode:** Perform the review yourself (see [Solo Review](#solo-review) below).

4. **Address findings locally:**

   **If headless = false (default):**

   After presenting the review, ask the user which findings they want addressed using `AskUserQuestion`. If in team mode, the team fixes the selected issues locally. If in solo mode, fix them yourself.

   **If headless = true:**

   Instead of asking the developer, spawn a **challenger agent** to validate the review findings. The challenger acts as a skeptical second opinion.

   **a) Spawn the challenger agent** with:
   - The consolidated review findings
   - The full diff and changed files
   - The instruction: "You are a senior engineer challenging a code review. For each finding, assess whether it is a real issue or a false positive. Check that severities are appropriate — is a 🔴 Critical truly critical? Is a 🔵 Suggestion actually a warning? Are any findings nitpicks that would add noise? Be concise: for each finding, state 'valid', 'false positive', or 'severity should be X' with a brief rationale."

   **b) Collect the challenger's assessment.** The lead agent (you) reads both the original findings and the challenger's assessment, then decides:
   - Dismiss findings flagged as false positives (if the rationale is convincing)
   - Adjust severities where the challenger makes a good case
   - Select all remaining validated findings (🔴 Critical and 🟡 Warning) to fix automatically
   - 🔵 Suggestions are noted in the output but not auto-fixed

   **c)** Fix the selected findings. If in team mode, the team fixes them. If in solo mode, fix them yourself.

5. **Cleanup** (team mode only) (see [Step 8: Cleanup](#step-8-cleanup) below)

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
   - If found, attempt to fetch Jira ticket details (summary, description, acceptance criteria) using the Atlassian CLI:
     ```bash
     acli jira workitem view <JIRA-ID> --fields summary,description,acceptance-criteria --json
     ```
   - Store the ticket details for the review team; if fetch fails, note the ticket reference but proceed without details

   **d) Build the exclusion list and collect all unresolved threads:**

   These findings must be **excluded** from the final review output to avoid duplication. Additionally, **every unresolved thread will receive a reply** from the agent after the review (see step 5b).

   - **Existing reviews, inline comments, and general comments:** Fetch in a single call:
     ```bash
     gh pr view <number> --repo <owner/repo> --json reviews,reviewComments,comments
     ```
     From the JSON output, record:
     - `reviews`: author, state (APPROVED, CHANGES_REQUESTED, COMMENTED), body
     - `reviewComments`: file path, line number, body, author
     - `comments`: substantive general PR conversation comments (skip bot comments and simple acknowledgements)

   - **Unresolved review threads** (requires GraphQL since `gh pr view` does not expose thread resolution status):
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
     Collect all **unresolved** threads with their thread `id`, file paths, line numbers, and comment bodies.

   - **Compile the exclusion list** with: file path + line (if applicable), summary of the issue raised, author.
   - **Store all unresolved threads** (with their thread IDs) separately — these will be used in step 5b to post replies.

3. **Review the changes:**

   - **If team mode:** Spawn the review team (see [Step 3: Spawn the review team](#step-3-spawn-the-review-team) below), then follow [Steps 4-6](#steps-4-6-review-consolidation-output) for review, consolidation, and output.
   - **If solo mode:** Perform the review yourself (see [Solo Review](#solo-review) below), incorporating the exclusion list to avoid duplicating existing review comments.

   **PR mode additions (team mode only):**
   - All reviewers also receive the exclusion list with instructions: "Do NOT report these issues — they have already been raised in existing reviews or unresolved comments. However, for each excluded comment relevant to your focus area, provide a brief assessment: do you agree with the comment, and is the issue still present in the current code? Report these assessments to `senior-lead` separately from your new findings."
   - If a Jira ticket was found, spawn a 9th agent: `ticket-compliance` (see table below)

4. **Review, consolidation, output** (team mode: see [Steps 4-6](#steps-4-6-review-consolidation-output) below; solo mode: see [Solo Review](#solo-review) below)

   **PR mode additions to consolidation:**
   - Re-check all findings against the exclusion list — remove any finding that overlaps with existing reviews or unresolved comments
   - If a `ticket-compliance` agent participated (team mode), include a "Ticket Compliance" section in the report noting any gaps between the code changes and the Jira ticket requirements
   - In solo mode with a Jira ticket, include a "Ticket Compliance" section yourself by comparing the changes against the ticket requirements

5. **Post findings as PR review comments:**

   **If headless = false (default):**

   After presenting the consolidated review, ask the user which findings they want posted as PR review comments using `AskUserQuestion`:

   > Here are the findings from the review. Which ones would you like me to post as review comments on the PR?
   >
   > Please provide the finding numbers (e.g., "1, 3, 5" or "all" or "none").

   - If the user says "none", skip to cleanup
   - If the user says "all", select every finding
   - Otherwise, parse the comma-separated list of finding numbers
   - Confirm the selection back to the user before proceeding

   **If headless = true:**

   Instead of asking the developer, spawn a **challenger agent** to validate the review findings before posting.

   **a) Spawn the challenger agent** with:
   - The consolidated review findings
   - The full diff, changed files, and exclusion list
   - The instruction: "You are a senior engineer challenging a code review before it is posted on a pull request. For each finding, assess whether it is a real issue or a false positive. Check that severities are appropriate. Flag any finding that is a nitpick, already covered by existing comments, or unlikely to be actionable. Be concise: for each finding, state 'post', 'skip' (with rationale), or 'adjust severity to X'."

   **b) Collect the challenger's assessment.** The lead agent (you) reads both the original findings and the challenger's assessment, then decides:
   - Skip findings the challenger convincingly flagged as false positives or duplicates
   - Adjust severities where the challenger makes a good case
   - Select all remaining validated findings to post as PR comments

   **c)** Proceed to post the selected findings (steps 5a–5h below).

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

   **CRITICAL: Every comment MUST contain a meaningful body explaining the issue.** Never post a comment that only pinpoints lines without explanation. The comment body is the primary value — it tells the PR author *what* the problem is, *why* it matters, and *how* to fix it.

   Every comment body must start with a `## From AI agent` heading. Format:
   ```
   ## From AI agent

   **[<severity>]** <title>

   <explanation from the consolidated review — this MUST be a substantive description
   of the issue, not just a file/line reference. Explain what is wrong, why it matters,
   and what the expected behavior or correct approach should be.>

   **Suggested fix:** <concrete suggestion for how to resolve the issue>

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
   - **Never** post a comment with an empty or placeholder body — if you cannot produce a meaningful explanation for a finding, skip it and warn the user

   **f) Reply to all existing unresolved comment threads:**

   For **every** unresolved thread collected in step 2d, post a reply using the reviewers' assessments consolidated by `senior-lead`. This ensures every existing comment gets a response, not just those that overlap with new findings.

   Each reply must start with `## From AI agent` and contain one of:
   - **Agreement + status:** Confirm the issue is valid and whether it's still present or has been addressed
   - **Disagreement + rationale:** Explain why the agent believes the comment is no longer applicable or was incorrect
   - **Partial agreement:** Acknowledge part of the comment while noting what has changed

   Post each reply using:
   ```bash
   gh api graphql -f query='
     mutation($threadId: ID!, $body: String!) {
       addPullRequestReviewThreadReply(input: {
         pullRequestReviewThreadId: $threadId,
         body: $body
       }) {
         comment {
           id
         }
       }
     }
   ' -f threadId='{thread_id}' -f body='{reply_body}'
   ```

   **g) Do NOT submit the review.**

   Never submit the review programmatically. The developer will review the comments and submit the review manually from the GitHub UI. Inform the user:
   > Comments have been added to your pending review. Please review them and submit the review from the GitHub UI when you're ready.

   **h) Report what was posted:**
   ```
   ## Review Comments Posted

   **PR:** #<number> — <title>
   **Review:** <"New pending review created" | "Added to your existing pending review"> — submit manually from the GitHub UI
   **New comments posted:** <count>
   **Replies to existing threads:** <count>

   ### New findings
   - #<N> — `<file>:<line>` — <title> — Posted ✓
   - #<N> — `<file>:<line>` — <title> — Posted ✓

   ### Replies to existing comments
   - `<file>:<line>` — <summary of original comment> — Replied ✓
   - `<file>:<line>` — <summary of original comment> — Replied ✓
   ...
   ```

6. **Cleanup** (team mode only) (see [Step 8: Cleanup](#step-8-cleanup) below)

---

## Shared Steps

### Solo Review

When **team mode is false**, perform the review yourself without spawning any agents or teams. Cover all focus areas in a single pass:

- **Code Quality**: Bugs, edge cases, error handling issues. Think about data conflicts and overlaps — what happens when two items occupy the same slot, time range, or index?
- **Security**: Vulnerabilities — injection, XSS, secrets exposure, auth issues
- **Performance**: Inefficiencies, bottlenecks, unnecessary allocations, resource usage
- **Best Practices**: Coding standards, design patterns, conventions, code consistency. Check new code against conventions in sibling files. Flag hardcoded values that should use existing constants/variables. Flag dead or unreachable code.
- **Testing**: Missing tests for new or changed functionality. Check that test descriptions describe behavior, assertions are resilient, and there are no duplicate test cases.
- **Documentation**: Missing or outdated documentation, inline comment gaps

**Convention check:** Before reporting findings, scan the directory of each changed file to identify sibling files. Note any conventions (naming, patterns, utilities, shared variables) that the new code should follow but doesn't.

**Only report potential issues.** Do NOT include findings that conclude with "no action needed" or "looks good". Every finding must identify a concrete problem, risk, or improvement opportunity.

Use the same output format as the team mode (see [Steps 4-6](#steps-4-6-review-consolidation-output) output format).

In PR mode, also incorporate the exclusion list — do not report issues already raised in existing reviews or unresolved comments.

---

### Step 3: Spawn the review team

Use `TeamCreate` with name `review-changes`. Spawn all agents simultaneously using the `Agent` tool (`subagent_type: general-purpose`) with `run_in_background: true` and the team name.

**Shared instructions for all reviewers:**
> Focus on the changes introduced (in the diff). Only review code that was added or modified — do not flag pre-existing issues in surrounding code that was not changed. However, when reviewing new files or significant additions, **read 2-3 sibling files** (same directory, same type) to understand existing patterns and conventions. Flag any deviation from established patterns (naming, variable usage, style composition, utility reuse).
>
> **Convention check:** Before reporting findings, scan the directory of each changed file to identify sibling files. Note any conventions (naming, patterns, utilities, shared variables) that the new code should follow but doesn't.
>
> **Only report potential issues.** Do NOT include findings that conclude with "no action needed", "looks good", "correctly handled", or similar affirmations. If you reviewed an area and found nothing wrong, simply state "No issues found" for that area — do not list things that are fine. Every finding you report must identify a concrete problem, risk, or improvement opportunity.

Each reviewer receives the full diff, the list of changed files, and their specific focus area:

| # | Name | Role | Focus |
|---|------|------|-------|
| 1 | `code-quality` | Code Quality Engineer | Bugs, edge cases, error handling issues. Think about **data conflicts and overlaps** — what happens when two items occupy the same slot, time range, or index? What if the same entity appears twice? Question assumptions: if code skips or filters items, is the skip logic correct from a domain perspective? |
| 2 | `security` | Security Engineer | Vulnerabilities: injection, XSS, secrets exposure, auth issues |
| 3 | `performance` | Performance Engineer | Inefficiencies, bottlenecks, unnecessary allocations, resource usage |
| 4 | `best-practices` | Best Practices Engineer | Coding standards, design patterns, conventions, code consistency. Check new code against conventions in sibling files (e.g., global CSS vars vs hardcoded values, style composition patterns, prop type patterns). Flag hardcoded values that should use existing constants/variables. Flag dead or unreachable code that doesn't contribute to the outcome. |
| 5 | `qa-coverage` | QA Engineer (Coverage) | Missing tests for new or changed functionality |
| 6 | `qa-consistency` | QA Engineer (Consistency) | Do test descriptions describe **behavior** (not implementation details like "diagonal stripes", "renders a div")? Are assertions **resilient to implementation changes** — would adding content to a component cause false positives/negatives? Does each test actually validate what its title claims, and does the expected behavior make **domain sense**? Are there duplicate or near-duplicate test cases? Would a reasonable implementation change break these tests for the wrong reasons? |
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
   - **Filter out non-issues:** During consolidation, discard any finding that concludes as "no action needed", "good as is", "correctly implemented", or otherwise affirms the current code without identifying a concrete problem. Only actionable findings (bugs, risks, missing coverage, improvement opportunities) belong in the final report.

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
