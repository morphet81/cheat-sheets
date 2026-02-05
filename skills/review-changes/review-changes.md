### /review-changes - Review Current Changes

Review changes introduced by the current branch compared to a base branch.

**Usage:**
- `/review-changes` - Compare current branch against `main`
- `/review-changes <branch>` - Compare current branch against specified branch

**Instructions:**

1. First, determine the base branch to compare against:
   - If an argument is provided, use that as the base branch
   - Otherwise, default to `main`

2. Get the current branch name and verify we're not on the base branch

3. Gather the changes:
   - Run `git diff <base-branch>...HEAD` to see all changes
   - Run `git log <base-branch>..HEAD --oneline` to see commit history

4. Review the changes and provide feedback on:
   - **Code Quality**: Look for bugs, edge cases, error handling issues
   - **Security**: Check for vulnerabilities (injection, XSS, secrets, etc.)
   - **Performance**: Identify potential performance issues or inefficiencies
   - **Best Practices**: Verify adherence to coding standards and patterns
   - **Testing**: Note if tests are missing for new functionality
   - **Documentation**: Check if changes need documentation updates

5. Format the review as:
   - Start with a brief summary of what the changes do
   - List specific issues found with file paths and line references
   - Categorize feedback by severity: 🔴 Critical, 🟡 Warning, 🔵 Suggestion
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
- **file.ts:42** - Description of critical issue

### 🟡 Warnings
- **other.ts:15** - Description of warning

### 🔵 Suggestions
- **file.ts:78** - Suggestion for improvement

## Overall Assessment
Summary and recommendation (approve, request changes, etc.)
```
