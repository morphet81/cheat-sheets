---
name: review-pull-request
version: 1.1.0
description: Review an open pull request by spawning a team of 2 independent reviewer agents. Each reviewer examines the full PR diff, takes notes, then they debate their findings before producing a consolidated review. Excludes findings already covered by existing reviews and unresolved comments. The user selects which findings to post as GitHub review comments.
argument-hint: "<PR number or URL> [repository]"
---

Review an open pull request by spawning two independent reviewer agents. Each reviewer examines the entire PR diff, writes down their observations, then they debate and challenge each other's findings. The final output is a deduplicated, consolidated review that excludes issues already raised in existing PR reviews and unresolved comments.

**Usage:**
- `/review-pull-request 1654` — Review PR #1654 in the current repo
- `/review-pull-request 1654 owner/repo` — Review PR #1654 in a specific repository
- `/review-pull-request https://github.com/owner/repo/pull/1654` — Review a PR by URL

**Instructions:**

1. **Parse arguments and identify the PR:**

   - If `$ARGUMENTS` contains a GitHub URL, extract the owner, repo, and PR number from it
   - If `$ARGUMENTS` contains just a number, use it as the PR number. If a second argument is provided, use it as `owner/repo`. Otherwise:
     - Run `gh repo view --json nameWithOwner -q .nameWithOwner` to get the current repo
   - Run the following to verify the PR exists and gather metadata:
     ```bash
     gh pr view <number> --repo <owner/repo> --json number,title,url,state,baseRefName,headRefName,author,additions,deletions,changedFiles,files
     ```
   - If the PR does not exist or is not open, display an error and **STOP**
   - Store the PR metadata for later reference

2. **Gather the PR diff and changed files:**

   - Fetch the full diff:
     ```bash
     gh pr diff <number> --repo <owner/repo>
     ```
   - Fetch the list of changed files:
     ```bash
     gh pr view <number> --repo <owner/repo> --json files --jq '.files[].path'
     ```
   - If the diff is extremely large (more than 5000 lines), note this for the reviewers so they can focus on the most impactful changes

3. **Collect existing reviews and unresolved comments (exclusion list):**

   These findings must be **excluded** from the final review output to avoid duplication.

   **a) Existing reviews:**
   - Fetch all submitted reviews:
     ```bash
     gh api repos/{owner}/{repo}/pulls/{number}/reviews --paginate
     ```
   - For each review, record:
     - Author, state (APPROVED, CHANGES_REQUESTED, COMMENTED)
     - The review body (top-level review comment)
   - Fetch all review comments (inline comments from reviews):
     ```bash
     gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate
     ```
   - For each review comment, record:
     - File path, line number, body, author

   **b) Unresolved review threads:**
   - Use the GitHub GraphQL API to fetch review threads and their resolution status:
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
   - Collect all **unresolved** threads with their file paths, line numbers, and comment bodies

   **c) General PR conversation comments:**
   - Fetch issue comments:
     ```bash
     gh api repos/{owner}/{repo}/issues/{number}/comments --paginate
     ```
   - Record substantive comments (skip bot comments and simple acknowledgements)

   **d) Build the exclusion list:**
   - Compile all existing findings into a structured list with:
     - File path + line (if applicable)
     - Summary of the issue raised
     - Author
   - This list will be given to both reviewers so they skip already-raised issues

4. **Create the review team:**

   - Use `TeamCreate` with name `review-pr-<number>` (e.g., `review-pr-1654`)
   - Create the following tasks with `TaskCreate`:
     - "Reviewer A: independent review of PR #<number>"
     - "Reviewer B: independent review of PR #<number>"
     - "Debate: reviewers challenge each other's findings"
     - "Consolidation: produce final deduplicated review"

5. **Spawn Reviewer A and Reviewer B** using the `Task` tool (`subagent_type: general-purpose`) with `run_in_background: true` and the team name:

   Give each reviewer the following prompt (adapted with their name):

   > You are **Reviewer <A|B>** on team `review-pr-<number>`. Your job is to independently review PR #<number> in `<owner/repo>`.
   >
   > ## PR Context
   > - **Title:** <title>
   > - **Author:** @<author>
   > - **Base:** <baseRefName> ← <headRefName>
   > - **Changed files:** <count> (+<additions>, -<deletions>)
   >
   > ## The Diff
   > <full PR diff>
   >
   > ## Exclusion List — DO NOT report these issues
   > The following issues have already been raised in existing reviews or unresolved comments on this PR. **Do not include any of these in your findings.** If you independently find the same issue, skip it.
   >
   > <formatted exclusion list with file:line and summary for each>
   >
   > ## Review Criteria
   > Review the PR changes (not surrounding unchanged code) for:
   > - **Correctness**: Bugs, logic errors, off-by-one errors, null/undefined risks, race conditions
   > - **Security**: Injection, XSS, secrets exposure, auth issues, OWASP top 10
   > - **Performance**: N+1 queries, unnecessary re-renders, missing memoization, algorithmic complexity
   > - **Error handling**: Missing try/catch, unhandled promise rejections, silent failures
   > - **Best practices**: Naming, code organization, DRY violations, dead code, anti-patterns
   > - **Testing**: Missing test coverage for new functionality, untested edge cases
   > - **Design**: Architectural concerns, coupling, API design, backwards compatibility
   >
   > ## Output Format
   > Write your findings as a numbered list. For each finding:
   > ```
   > #<N>. [<severity>] <file>:<line> — <title>
   >     <detailed explanation of the issue>
   >     <suggested fix if applicable>
   > ```
   > Severity: CRITICAL, WARNING, or SUGGESTION
   >
   > After your findings, write a section called **"Overall Impression"** with 2-3 sentences about the PR quality and whether you'd approve or request changes.
   >
   > **Important:**
   > - Be thorough — review every changed file and every hunk
   > - Take notes as you go — don't skip details you can revisit during debate
   > - Be specific — include file paths and line numbers for every finding
   > - Do NOT duplicate anything from the exclusion list
   > - When you are done, send your full findings to the team lead via `SendMessage` and mark your task as completed via `TaskUpdate`

6. **Wait for both reviewers to complete their independent reviews:**

   - Both reviewers will send their findings via `SendMessage`
   - Once both are done, proceed to the debate phase

7. **Initiate the debate phase:**

   Send a message to **both reviewers** (individually, not broadcast) with the other's findings:

   > ## Debate Phase
   >
   > Your fellow reviewer has completed their independent review. Here are their findings:
   >
   > <other reviewer's findings>
   >
   > Now, carefully review their findings and compare with yours:
   >
   > 1. **Challenge**: Are any of their findings incorrect, overstated, or based on a misunderstanding of the code? Point these out with your reasoning.
   > 2. **Acknowledge**: Which of their findings are valid and important that you missed? Note these.
   > 3. **Defend**: If they missed something you found, explain why you think it's important.
   > 4. **Reconsider**: Looking at both sets of findings together, do you want to change the severity of any of your own findings? Do you want to retract anything?
   >
   > Write your debate response and send it to the team lead via `SendMessage`. Mark the debate task as completed via `TaskUpdate`.

   Wait for both reviewers to respond with their debate notes.

8. **Consolidate the final review:**

   Using both reviewers' original findings and their debate responses, produce a consolidated review:

   **a) Merge findings:**
   - Combine findings from both reviewers
   - Deduplicate: if both reviewers found the same issue, keep one entry and note it was found by both (higher confidence)
   - Remove findings that were successfully challenged during debate
   - Adjust severities based on debate consensus
   - **Re-check against the exclusion list** — remove any finding that overlaps with existing reviews or unresolved comments

   **b) Assign final numbers** sequentially (#1, #2, #3, ...) to all remaining findings

   **c) Format the final review:**

   ```
   ## PR Review: #<number> — <title>

   **Repository:** <owner/repo>
   **Author:** @<author>
   **Reviewers:** Reviewer A, Reviewer B (independent review + debate)

   ### Summary
   <2-3 sentence summary of what this PR does>

   ### Existing Feedback (excluded from this review)
   <N> issues were already raised in prior reviews and unresolved comments. These have been excluded from the findings below.

   ### Changes Reviewed
   - `path/to/file.ts` — Description of changes
   - `path/to/other.ts` — Description of changes

   ### Findings

   #### 🔴 Critical
   - **#1** — **file.ts:42** — <title>
     <explanation>
     **Confidence:** High (found by both reviewers) | Medium (found by one, unchallenged) | Debated (see note)
     **Suggested fix:** <suggestion>

   #### 🟡 Warnings
   - **#2** — **other.ts:15** — <title>
     <explanation>
     **Confidence:** ...

   #### 🔵 Suggestions
   - **#3** — **file.ts:78** — <title>
     <explanation>

   ### Debate Highlights
   <Summarize key points of disagreement between reviewers and how they were resolved.
   This gives the PR author insight into the reasoning behind the findings.>

   ### Overall Assessment
   <Consolidated recommendation: approve, request changes, or comment.
   Include both reviewers' individual impressions and the consensus view.>
   ```

9. **Select findings to post as review comments:**

   After presenting the consolidated review, ask the user which findings they want posted as PR review comments using `AskUserQuestion`:

   > Here are the findings from the review. Which ones would you like me to post as review comments on the PR?
   >
   > Please provide the finding numbers (e.g., "1, 3, 5" or "all" or "none").

   - If the user says "none", skip to step 11 (clean up)
   - If the user says "all", select every finding
   - Otherwise, parse the comma-separated list of finding numbers
   - Confirm the selection back to the user before proceeding:
     > I'll post comments for findings: #1, #3, #5. Proceeding.

10. **Post review comments on GitHub:**

    **a) Determine the authenticated user:**
    - Run `gh api user --jq .login` to get the current GitHub username

    **b) Check for an existing pending review by the user:**
    - Query pending reviews on the PR:
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
    - Look for a review where `author.login` matches the authenticated user
    - Record whether a pending review already exists:
      - If **yes**: use its `id` as `review_id` and set `agent_created_review = false`
      - If **no**: set `agent_created_review = true` (will create one in the next sub-step)

    **c) Create a pending review if none exists:**
    - If `agent_created_review` is `true`, create a new pending review:
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
    - To get the PR node ID (if not already available):
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
    - Store the `review_id` from the response

    **d) Determine the latest commit SHA on the PR:**
    - Fetch the head commit OID:
      ```bash
      gh pr view <number> --repo <owner/repo> --json commits --jq '.commits[-1].oid'
      ```

    **e) Add review comments for each selected finding:**

    For each selected finding, create an inline review comment. **Every comment body must start with a `## From AI agent` heading.**

    Format each comment body as:
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

    - Use the file path and line number from each finding
    - If a finding references a range of lines, use the last line of the range
    - If a finding does not have a specific line number (rare), fall back to posting it as a top-level review body comment instead of an inline comment

    **f) Submit the review (only if agent-created):**

    - If `agent_created_review` is `true`, submit the review:
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
    - If `agent_created_review` is `false` (comments were added to the user's existing pending review), do **NOT** submit. Inform the user:
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

11. **Clean up:**

    - Send `shutdown_request` to both reviewers via `SendMessage`
    - Once confirmed, call `TeamDelete`
    - Present the final summary to the user

12. **Handle edge cases:**
    - If the PR diff is empty, report "No changes to review" and **STOP**
    - If `gh` is not authenticated, display setup instructions and **STOP**
    - If one reviewer fails or times out, proceed with the other reviewer's findings alone (note this in the output)
    - If the exclusion list is very large (>30 items), summarize it for reviewers by grouping related items rather than listing each one individually
    - If reviewers find no new issues beyond the exclusion list, report: "No new issues found beyond the <N> already-raised items in existing reviews."
    - If the PR URL points to a different host (e.g., GitHub Enterprise), pass the full URL to `gh` commands which handle enterprise hosts automatically
    - If a GraphQL mutation fails when posting a comment (e.g., invalid line number because the diff has changed), skip that comment, log a warning, and continue with the remaining comments
    - If all comment postings fail, inform the user and suggest they post manually based on the findings
