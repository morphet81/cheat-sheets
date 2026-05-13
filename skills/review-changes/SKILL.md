---
name: review-changes
version: 4.2.0
description: Review code changes with a small team — two senior engineers review independently, debate their findings, then a team lead reports a consolidated list. Local mode compares the current branch against a base branch; PR mode (auto-enabled when a PR URL or number is supplied) offers to post the findings as PR review comments. When the developer chooses to address findings, the same two engineers implement the fixes in auto mode. Engineers read the project's AI documentation (architecture first) before reviewing, and explicitly check for reuse violations and unused established practices.
argument-hint: "[base-branch] | <PR number or URL>"
---

Review code changes with a focused 3-agent team:
- Two **senior engineers** each review the changes independently, covering every focus area.
- They share findings, **challenge each other**, and converge on a consolidated list.
- A **team lead** receives the consolidated list and reports it back to the developer.
- **PR mode** (auto-detected when the argument is a PR URL or number): the team lead offers to post the findings as pending PR review comments.
- **Local mode**: the team lead shows the findings and asks which to address now. Selected findings are implemented by the same two engineers in auto mode.

**Usage:**
- `/review-changes` — Local review against `main`
- `/review-changes <branch>` — Local review against `<branch>`
- `/review-changes <PR-number>` — Review the PR in the current repo
- `/review-changes <PR-URL>` — Review a PR by URL (use this for PRs in another repo)

**Instructions:**

1. **Parse arguments and determine mode:**

   `$1` is the only argument.

   - If `$1` matches a GitHub PR URL (`https://github.com/.../pull/\d+`) → **PR mode**. Extract owner, repo, and PR number from the URL.
   - If `$1` is a pure number → **PR mode**. Use it as the PR number, and run `gh repo view --json nameWithOwner -q .nameWithOwner` to derive the current repo. For a PR in another repo, pass the full PR URL instead.
   - Otherwise → **local mode**. Base branch = `$1` if given, else the `baseBranch=...` value from a `.agent` file in the working directory if present, else `main`.

---

## Local Mode — Gather Changes

2. **Gather branch changes:**
   - Get the current branch name and verify we are not on the base branch
   - `git diff <base-branch>...HEAD` — full diff
   - `git log <base-branch>..HEAD --oneline` — commit history
   - `git diff --name-only <base-branch>...HEAD` — list of changed files

---

## PR Mode — Gather Context

2. **Gather PR context:**

   **a) Verify the PR exists and gather metadata:**
   ```bash
   gh pr view <number> --repo <owner/repo> --json number,title,url,state,baseRefName,headRefName,author,additions,deletions,changedFiles,files
   ```
   - If the PR does not exist or is not open, display an error and **STOP**.
   - Store the PR metadata for later reference.

   **b) Fetch the full diff and changed files:**
   ```bash
   gh pr diff <number> --repo <owner/repo>
   ```
   ```bash
   gh pr view <number> --repo <owner/repo> --json files --jq '.files[].path'
   ```
   - If the diff exceeds ~5000 lines, note this for the engineers so they can prioritise the most impactful changes.

   **c) Check for a Jira ticket reference:**
   - Scan the PR title, description, and branch name for a Jira key (pattern: `[A-Z][A-Z0-9]+-[0-9]+`, e.g., `PROJ-123`).
   - If found, attempt to fetch the ticket details:
     ```bash
     acli jira workitem view <JIRA-ID> --fields summary,description,acceptance-criteria --json
     ```
   - If the fetch succeeds, pass the ticket details to both engineers and instruct the team lead to include a **Ticket Compliance** section in the final report. If it fails, note the ticket key but proceed without details.

   **d) Build the exclusion list and collect unresolved threads:**

   Findings in the exclusion list must be **excluded** from the final report (no duplication of existing review comments). Additionally, **every unresolved thread will receive a reply** when the lead posts comments (see step 8a).

   - Existing reviews, inline comments, and general comments — one call:
     ```bash
     gh pr view <number> --repo <owner/repo> --json reviews,reviewComments,comments
     ```
     Record from the output:
     - `reviews`: author, state, body
     - `reviewComments`: file path, line, body, author
     - `comments`: substantive general PR conversation comments (skip bot comments and acknowledgements)

   - Unresolved review threads via GraphQL (since `gh pr view` does not expose resolution status):
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
     Collect all **unresolved** threads with thread `id`, file paths, line numbers, and comment bodies.

   - Compile the exclusion list with: file path + line (if applicable), summary of the issue raised, author.
   - Store all unresolved threads separately — they will be replied to in step 8a.

---

## Shared Steps

3. **Spawn the review team:**

   Use `TeamCreate` with name `review-changes`. Spawn three agents simultaneously via the `Agent` tool (`subagent_type: general-purpose`, `run_in_background: true`, with the team name):

   | Name | Role |
   |------|------|
   | `engineer-1` | Senior Engineer — independent reviewer |
   | `engineer-2` | Senior Engineer — independent reviewer |
   | `team-lead` | Team Lead — coordinates the engineers and reports to the developer |

   **Shared brief for both engineers:**
   > You are one of two senior engineers reviewing this change set independently. Cover **every focus area** below. Do NOT communicate with the other engineer during your initial review — your value comes from forming an independent opinion.
   >
   > **Read the project's AI documentation first.** Before reviewing the diff, look for AI-oriented documentation in the repo. Common locations:
   > - `CLAUDE.md` (root, and per-directory if present)
   > - `AGENTS.md`
   > - `.claude/` and `.cursor/rules/`
   > - `docs/ai/`, `docs/agents/`, `docs/architecture/`
   > - `ARCHITECTURE.md`, `README.md` (architecture sections only)
   >
   > The documentation is often split across multiple files. **You must read the most important ones — especially anything describing the app's architecture, module boundaries, data flow, or core conventions** — because findings made without that context tend to be wrong. For multi-file doc sets, skim the index/README of the doc directory, then read only the entries relevant to the files you're reviewing. Do **not** read documentation that is clearly unrelated to the changes. If the project provides no AI documentation, skip this step.
   >
   > **Scope:** Focus on the changes introduced (the diff). Only review code that was added or modified — do not flag pre-existing issues in surrounding code. When reviewing new files or significant additions, read 2–3 sibling files (same directory, same type) to understand the existing conventions and flag deviations.
   >
   > **Only report potential issues.** Do NOT list things that look fine. Every finding must identify a concrete problem, risk, or improvement opportunity. If a focus area looks clean, simply state "No issues found".
   >
   > **Focus areas — cover all of them:**
   > - **Code Quality** — Bugs, edge cases, error handling. Think about data conflicts and overlaps — what happens when two items occupy the same slot, time range, or index? Question assumptions: if code skips or filters items, is the skip logic correct from a domain perspective?
   > - **Security** — Vulnerabilities: injection, XSS, secrets exposure, auth issues.
   > - **Performance** — Inefficiencies, bottlenecks, unnecessary allocations, resource usage.
   > - **Best Practices** — Coding standards, design patterns, conventions, consistency with sibling files. Flag hardcoded values that should use existing constants/variables. Flag dead or unreachable code.
   > - **Testing** — see the **Test Review Checklist** below.
   > - **Documentation** — Missing or outdated documentation, changelog needs, inline comment gaps.
   >
   > **Test Review Checklist** — read each new or modified test carefully and verify all of:
   > 1. **Description is generic enough** — describes behaviour, not implementation details (e.g., "shows an error" instead of "renders a red div with class `error-box`").
   > 2. **Does not test implementation** — assertions target stable contracts, not styling or internal markup. Example: assert that a button has an `alert` class, not that it is red; assert that an error is announced to the user, not that a specific element exists.
   > 3. **No duplicates** — flag tests (or near-duplicate tests) that cover the same scenario.
   > 4. **No cross-component re-testing** — a component that uses another component must not re-test the inner component's behaviour. Each component has its own test suite; the outer test should only verify the integration, not the inner component's internals.
   > 5. **Description matches assertions** — for every test, verify the assertions actually prove what the description claims. Flag missing assertions (claim made, no assertion for it) and extraneous assertions (assertion not described). Flag silent passes (a test that would still pass if the feature it claims to cover were removed).
   >
   > **Reuse & Project Practices Checklist** — before approving any new code, verify all of:
   > 1. **No reinvention of existing components** — flag any new component, hook, helper, or utility that could have been created by **extending or reusing** an existing one. Grep the relevant directories for similar names, props, or responsibilities before assuming something is new. If the diff genuinely needs a new variant, it must come with a clear architectural rationale (in the code, commit message, PR description, or ticket); otherwise flag it as a reuse violation and recommend extending the existing primitive.
   > 2. **Established practices are used** — identify the project's higher-order patterns (read the AI documentation and skim sibling files for examples): things like a modal-visibility HOC/hook, a permissioned-button wrapper, a form helper, a request-state hook, a feature-flag gate, etc. Verify the new code uses them. **Example:** if the project provides a HOC or hook for managing modal visibility, any new conditionally-visible modal must use it instead of rolling its own `useState(open)` boilerplate. Flag any new code that bypasses an established practice without justification.
   > 3. **Existing utilities, constants, and shared variables are reused** — flag inline implementations of behaviour already covered by an existing utility, and hardcoded values that have a named constant or shared variable available.
   >
   > **Convention check:** Before reporting findings, scan the directory of each changed file to identify sibling files. Note any conventions (naming, patterns, utilities, shared variables) that the new code should follow but doesn't.
   >
   > When finished, message `team-lead` with your findings. For each finding, provide: title, `file:line`, severity (🔴 Critical / 🟡 Warning / 🔵 Suggestion), rationale, suggested fix. State "No issues found in <area>" for any clean focus area.

   **PR mode additions to the engineers' brief:**
   - Attach the **exclusion list** with the instruction: "Do NOT report these issues — they have already been raised. For each excluded item that falls in a focus area you reviewed, send the lead a brief assessment: do you agree with the comment, and is the issue still present in the current code?"
   - Attach the **Jira ticket details** if available, with the instruction: "Also compare the changes against the ticket's requirements and acceptance criteria. Flag any missing or partially-addressed items."

   **Team Lead brief:**
   > You coordinate two independent senior engineers reviewing a change set. Your responsibilities:
   > 1. **Wait** for both engineers to submit their independent findings.
   > 2. **Share & challenge** — relay each engineer's findings to the other. Instruct each to challenge anything they disagree with (false positive, wrong severity, missing context) and to add anything the other engineer missed within their own analysis.
   > 3. **Discuss & consolidate** — facilitate a short discussion (one round-trip is usually enough) where the engineers converge on a single, deduplicated list of findings with agreed severities. When they genuinely disagree, keep the finding and mark it **Debated** with both perspectives noted.
   > 4. **Filter non-issues** — drop anything that concludes with "no action needed", "looks good", etc. Only actionable findings remain.
   > 5. **Produce the consolidated report** using the format in step 7.
   > 6. **Deliver the report** to the developer. In PR mode, also propose posting the findings as PR review comments (step 8a). In local mode, ask which findings to address now (step 8b).
   > 7. When fixes are required, **dispatch the same two engineers in auto mode** to implement them (step 9).
   > 8. Once all work is done, send `shutdown_request` to both engineers and call `TeamDelete`.

4. **Independent review (parallel):**

   Both engineers begin reviewing in parallel. Each:
   - Reads the full diff and changed files
   - Covers every focus area
   - Sends findings to `team-lead`
   - Marks their task completed

5. **Cross-review & challenge:**

   Once both reports arrive, `team-lead`:
   - Sends `engineer-1`'s findings to `engineer-2`, and `engineer-2`'s findings to `engineer-1`
   - Asks each engineer to **challenge** anything they consider a false positive, wrongly-severed, or duplicated, and to **add** anything the other engineer missed within their own analysis
   - Collects the challenges and rebuttals

6. **Discussion & consolidation:**

   `team-lead` facilitates a brief discussion where the engineers converge on:
   - A single deduplicated list of findings
   - An agreed severity for each (🔴 Critical / 🟡 Warning / 🔵 Suggestion)
   - Any items the engineers cannot agree on are kept and marked **Debated**, with both perspectives recorded

7. **Team lead reports to the developer:**

   The team lead presents the consolidated report:

   ```
   ## Summary
   Brief description of what the changes introduce.

   ## Changes Reviewed
   - `path/to/file.ts` — Description of changes
   - `path/to/other.ts` — Description of changes

   ## Findings

   ### 🔴 Critical
   - **#1** — `file.ts:42` — Title and explanation
     - **Suggested fix:** …

   ### 🟡 Warnings
   - **#2** — `other.ts:15` — Title and explanation
     - **Suggested fix:** …

   ### 🔵 Suggestions
   - **#3** — `file.ts:78` — Title and explanation
     - **Suggested fix:** …

   ### ⚖️ Debated *(only if engineers disagreed)*
   - **#4** — `file.ts:120` — Description
     - `engineer-1`: …
     - `engineer-2`: …

   ## Ticket Compliance *(PR mode, if a Jira ticket was found)*
   - ✅ Requirement A — addressed in `file.ts`
   - ⚠️ Requirement B — partially addressed, missing edge case handling
   - ❌ Requirement C — not addressed in this PR

   ## Overall Assessment
   Summary and recommendation.
   ```

   Findings are numbered sequentially across all severity categories so the developer can reference them by number.

8. **Handle the findings:**

   **a) PR mode — propose posting comments:**

   The team lead suggests posting the consolidated findings as pending PR review comments and asks the developer (via `AskUserQuestion`) which to post: `all`, `none`, or a list of finding numbers (e.g., `1, 3, 5`). After selection:

   - Determine the authenticated user:
     ```bash
     gh api user --jq .login
     ```
   - Check for an existing pending review by the user:
     ```bash
     gh api graphql -f query='
       query($owner: String!, $repo: String!, $pr: Int!) {
         repository(owner: $owner, name: $repo) {
           pullRequest(number: $pr) {
             reviews(states: PENDING, first: 10) {
               nodes { id author { login } }
             }
           }
         }
       }
     ' -f owner='{owner}' -f repo='{repo}' -F pr={number}
     ```
     - If a pending review exists for the authenticated user, reuse its `id`.
     - Otherwise create a new pending review:
       ```bash
       gh api graphql -f query='
         mutation($prId: ID!) {
           addPullRequestReview(input: {pullRequestId: $prId}) {
             pullRequestReview { id }
           }
         }
       ' -f prId='{pullRequest_node_id}'
       ```
       Obtain the PR node ID via:
       ```bash
       gh api graphql -f query='
         query($owner: String!, $repo: String!, $pr: Int!) {
           repository(owner: $owner, name: $repo) {
             pullRequest(number: $pr) { id }
           }
         }
       ' -f owner='{owner}' -f repo='{repo}' -F pr={number}
       ```
   - Determine the latest commit SHA:
     ```bash
     gh pr view <number> --repo <owner/repo> --json commits --jq '.commits[-1].oid'
     ```
   - For each selected finding, post a review thread with a substantive body. **Every comment body MUST start with `## From AI agent` and contain a meaningful explanation — never just a file/line reference.** Format:

     ```
     ## From AI agent

     **[<severity>]** <title>

     <explanation: what is wrong, why it matters, what the expected behaviour should be>

     **Suggested fix:** <concrete suggestion>

     **Confidence:** <High|Medium|Debated>
     ```

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
           thread { id }
         }
       }
     ' -f reviewId='{review_id}' -f body='{comment_body}' -f path='{file_path}' -F line={line_number}
     ```
     - For range findings, use the last line.
     - For findings without a specific line, fall back to a top-level review body comment.
     - Never post an empty body — if you cannot write a meaningful explanation for a finding, skip it and warn the developer.

   - **Reply to every unresolved thread** collected in step 2d using the engineers' assessments, even when the thread is not duplicated by a new finding. Each reply begins with `## From AI agent` and contains one of: agreement + current status, disagreement + rationale, or partial agreement.
     ```bash
     gh api graphql -f query='
       mutation($threadId: ID!, $body: String!) {
         addPullRequestReviewThreadReply(input: {
           pullRequestReviewThreadId: $threadId,
           body: $body
         }) {
           comment { id }
         }
       }
     ' -f threadId='{thread_id}' -f body='{reply_body}'
     ```
   - **Never submit the review programmatically.** Tell the developer:
     > Comments have been added to your pending review. Please review them and submit the review from the GitHub UI when you're ready.
   - Print a posting summary:
     ```
     ## Review Comments Posted

     **PR:** #<number> — <title>
     **Review:** <"New pending review created" | "Added to your existing pending review">
     **New comments posted:** <count>
     **Replies to existing threads:** <count>
     ```

   **b) Local mode — ask which to address:**

   The team lead asks the developer (via `AskUserQuestion`) which findings to address now. Accept `all`, `none`, or a list of finding numbers. Continue to step 9 with the selected findings (skip step 9 entirely if the developer selects `none`).

9. **Address the selected findings (local mode, auto mode):**

   When findings are selected for fixing, the team lead dispatches `engineer-1` and `engineer-2` to implement them in **auto mode**:
   - Split the selected findings between the two engineers (roughly by file or focus area) so they work in parallel without stepping on each other.
   - Each engineer implements its assigned fixes directly in the working tree, validating with the relevant tests/lints when sensible.
   - When both engineers report completion, the team lead summarises what changed and lists any follow-up work the developer should review manually.
   - **Do not commit.** The developer commits when satisfied.

10. **Cleanup:**

    - The team lead sends `shutdown_request` to `engineer-1` and `engineer-2`.
    - After both confirm, call `TeamDelete`.
    - Present the final summary to the developer.

---

## Edge Cases

- If the PR diff is empty (PR mode) or there are no commits ahead of base (local mode), report "No changes to review" and **STOP**.
- If `gh` is not authenticated (PR mode), display setup instructions and **STOP**.
- If the exclusion list is very large (>30 items), summarise it for the engineers by grouping related items.
- If the engineers find no new issues beyond the exclusion list, report: "No new issues found beyond the <N> already-raised items in existing reviews."
- If the PR URL points to GitHub Enterprise, pass the full URL to `gh` commands; they handle enterprise hosts.
- If a GraphQL mutation fails when posting a comment (e.g., the diff has moved), skip that comment, log a warning, and continue with the rest.
- If all comment postings fail, inform the developer and suggest they post manually based on the report.
