---
name: review-changes
version: 2.0.0
description: Review changes introduced by the current branch compared to a base branch. Spawns a specialized team of 8 reviewer agents covering code quality, security, performance, best practices, testing, and documentation. Use when you want to review code changes before creating a PR or merging.
argument-hint: "[base-branch]"
---

Review changes introduced by the current branch compared to a base branch.

**Usage:**
- `/review-changes` - Compare current branch against `main`
- `/review-changes <branch>` - Compare current branch against specified branch

**Instructions:**

1. First, determine the base branch to compare against:
   - If an argument is provided via $ARGUMENTS, use that as the base branch
   - Otherwise, check if a `.agent` file exists in the current directory. If it contains a `baseBranch=<value>` line, use that value as the base branch
   - If no argument and no `.agent` file, default to `main`

2. Get the current branch name and verify we're not on the base branch

3. Gather the changes:
   - Run `git diff <base-branch>...HEAD` to see all changes
   - Run `git log <base-branch>..HEAD --oneline` to see commit history
   - Run `git diff --name-only <base-branch>...HEAD` to get the list of changed files

4. Spawn a specialized review team:

   Use `TeamCreate` with name `review-changes`. Spawn all 8 agents simultaneously using the `Agent` tool (`subagent_type: general-purpose`) with `run_in_background: true` and the team name.

   **Shared instructions for all reviewers:**
   > Focus exclusively on the changes introduced by the current branch. Only review code that was added or modified in the diff — do not flag pre-existing issues in surrounding code that was not changed. The goal is to review what this branch introduces, not to audit the entire codebase.

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

   **Senior Engineer responsibilities:**
   - Available throughout the review to answer questions and assist other reviewers — reviewers should message `senior-lead` when they need guidance or want to validate a finding
   - Once all 7 specialists have reported their findings, verify each finding for accuracy and relevance
   - Orchestrate a team-wide conversation (via `broadcast` and direct messages) where reviewers share findings and debate the best approaches to fix identified issues
   - Produce the final consolidated report (step 6 format) incorporating the team's discussion
   - After the final report is ready, clean up: send `shutdown_request` to each reviewer, then `TeamDelete`

5. Each specialist reviewer must:
   - Read the full diff and changed files relevant to their focus area
   - Message `senior-lead` with their findings (or confirm no issues found)
   - Mark their task as completed
   - Respond to any follow-up questions from `senior-lead` during the team discussion

6. Format the review as:
   - Start with a brief summary of what the changes do
   - List specific issues found with file paths and line references
   - Categorize feedback by severity: 🔴 Critical, 🟡 Warning, 🔵 Suggestion
   - **Assign a sequential number to each finding** (e.g., #1, #2, #3) across all severity categories, so the developer can easily reference specific findings (e.g., "fix #3, dismiss #5")
   - End with an overall assessment and recommendation

**Example output format:**

```
## Summary
Brief description of what this branch introduces.

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

## Overall Assessment
Summary and recommendation (approve, request changes, etc.)
```
