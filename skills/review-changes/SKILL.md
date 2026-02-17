---
name: review-changes
version: 1.3.0
description: Review changes introduced by the current branch compared to a base branch. Use when you want to review code changes before creating a PR or merging.
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

4. Review the changes and provide feedback on:

   **IMPORTANT: Focus exclusively on the changes introduced by the current branch.** Only review code that was added or modified in the diff — do not flag pre-existing issues in surrounding code that was not changed. The goal is to review what this branch introduces, not to audit the entire codebase.

   - **Code Quality**: Look for bugs, edge cases, error handling issues in the changed code
   - **Security**: Check for vulnerabilities (injection, XSS, secrets, etc.) introduced by the changes
   - **Performance**: Identify potential performance issues or inefficiencies in the new/modified code
   - **Best Practices**: Verify adherence to coding standards and patterns in the changed code
   - **Testing**: Note if tests are missing for new functionality introduced by this branch
   - **Documentation**: Check if the changes need documentation updates

5. Format the review as:
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
