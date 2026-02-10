---
name: cleanup
description: Review uncommitted changes, verify tests, fix lint and audit issues, then present a change plan for approval before committing.
argument-hint: ""
---

Orchestrate a full cleanup of the current working directory: review changes, verify tests, fix linting and audit issues, and commit.

**Usage:**
- `/cleanup` - Run the full cleanup workflow

**Instructions:**

1. **Review uncommitted changes:**
   - Run `git status` to see all modified, staged, and untracked files
   - Run `git diff` to see unstaged changes and `git diff --cached` to see staged changes
   - Read each changed file to understand the full context of modifications
   - Produce a brief summary of all uncommitted changes grouped by category (new features, bug fixes, refactoring, etc.)

2. **Verify new test cases:**
   - Invoke the `/verify-test-cases` skill to check all test files modified since last push
   - Record any issues found (nonsensical tests, duplicates, missing coverage)
   - These issues will be included in the change plan later

3. **Fix lint issues:**
   - Auto-detect the project type by checking for configuration files:
     - `package.json` (Node.js/JS/TS)
     - `pyproject.toml`, `setup.py`, `requirements.txt` (Python)
     - `Cargo.toml` (Rust)
     - `go.mod` (Go)

   - **Use the auto-fix command when available:**
     - **Node.js/JS/TS:**
       - Check `package.json` scripts for a `lint:fix` script. If found, run `npm run lint:fix`
       - Otherwise, check for ESLint and run `npx eslint . --fix`
       - Check for Prettier and run `npx prettier --write .`
     - **Python:**
       - Check for `ruff` and run `ruff check --fix .` then `ruff format .`
       - Or check for `black` and run `black .`
       - Or check for `autopep8` and run `autopep8 --in-place --recursive .`
     - **Rust:**
       - Run `cargo fmt` and `cargo clippy --fix --allow-dirty`
     - **Go:**
       - Run `gofmt -w .` and `go vet ./...`

   - Record any remaining lint issues that could not be auto-fixed

4. **Run auditing and fix issues:**
   - **Node.js:** Run `npm audit`. If vulnerabilities are found, run `npm audit fix`. If that is not enough, note remaining issues but do NOT run `npm audit fix --force` automatically
   - **Python:** Run `pip audit` if available. Note any vulnerabilities found
   - **Rust:** Run `cargo audit` if available. Note any vulnerabilities found
   - **Go:** Run `govulncheck ./...` if available. Note any vulnerabilities found
   - Record any audit issues that could not be auto-fixed

5. **Present the change plan:**

   Compile all findings into a structured plan and present it to the developer using the `AskUserQuestion` tool with `multiSelect: true`. Each item should be a selectable checkbox so the developer can choose which changes to keep.

   Group the items by category:
   - **Lint fixes applied** — list each file that was modified by the linter
   - **Audit fixes applied** — list each dependency change from audit fix
   - **Test issues found** — list each issue from test verification (these are suggestions for the developer to fix manually)
   - **Remaining issues** — anything that could not be auto-fixed

   Example question format:
   ```
   "Which changes do you want to proceed with?"
   Options:
   - "Lint fixes: 5 files auto-formatted by ESLint"
   - "Audit fix: updated lodash 4.17.20 → 4.17.21"
   - "Revert: test changes in user.test.ts (duplicate tests found)"
   ```

   If there are more items than fit in 4 options, group them logically (e.g., "All lint fixes (8 files)" as one option).

6. **Apply selected changes:**
   - For items the developer selected: keep the changes staged
   - For items the developer deselected: revert those specific changes using `git checkout -- <file>` or `git restore <file>`
   - If the developer deselected lint fixes, revert the linter's modifications to those files
   - If the developer deselected audit fixes, run `git checkout -- package-lock.json package.json` (or equivalent) to undo dependency changes
   - Stage all approved changes with `git add`

7. **Propose final action:**

   Use `AskUserQuestion` to offer two options:

   - **Commit** — Commit the approved changes locally (generate an appropriate commit message based on the changes)
   - **Commit and push** — Commit and push to the current remote branch

   After the developer chooses:
   - If **Commit**: create the commit with a descriptive message
   - If **Commit and push**: create the commit, then push to the remote tracking branch (or `origin/<current-branch>` if no tracking branch is set)

8. **Handle edge cases:**
   - If there are no uncommitted changes, inform the user and STOP
   - If no lint tools are detected, skip the lint step and note it in the plan
   - If no audit tools are detected, skip the audit step and note it in the plan
   - If the `/verify-test-cases` skill reports no test files modified, skip that section in the plan
   - If all checks pass with no issues, skip the change plan and go straight to the commit options
   - If the developer deselects all changes, inform them that there is nothing to commit and STOP

**Example output format:**

```
## Cleanup Summary

### Changes Reviewed
- 3 files modified, 1 file added
- New feature: user profile endpoint
- Bug fix: corrected date parsing in utils

### Lint
✅ 5 files auto-fixed by ESLint
⚠️ 1 issue could not be auto-fixed:
  - src/api.ts:42 — Unexpected any. Specify a different type.

### Test Verification
✅ All test cases verified — no issues found

### Audit
✅ npm audit fix applied — resolved 2 vulnerabilities
⚠️ 1 moderate vulnerability remains (no auto-fix available)

---

[Interactive checklist presented to developer]

---

✅ Committed: "Add user profile endpoint and fix date parsing"
```
