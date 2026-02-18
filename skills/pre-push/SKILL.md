---
name: pre-push
version: 1.1.0
description: Run pre-push checks including tests and linting to ensure code is clean and ready to push. Automatically detects project type and available scripts.
argument-hint: ""
---

Run pre-push checks to ensure code quality before pushing to remote.

**Usage:**
- `/pre-push` - Run all pre-push checks for the current project

**Instructions:**

1. **Check for Claude Teams:**

   Before running checks, check whether Claude Teams (multi-agent parallel execution) is available and offer it to the developer.

   **a) Detect availability:**
   - Run `echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` via the Bash tool to check the environment variable
   - If the value is not `1`, Claude Teams is not enabled — skip this step silently

   **b) Ask the developer:**
   - If the environment variable is `1`, use `AskUserQuestion` to ask:
     > Claude Teams is available on this machine. Would you like to enable parallel agents for this task? Teams mode will run linting, testing, and build checks in parallel for faster execution.
   - Provide two options: **Yes — use Teams** and **No — single agent**

   **c) Enable teams:**
   - If the developer chooses to use Teams, use the `Task` tool with `run_in_background: true` to spawn parallel agents for independent checks (e.g., separate agents for linting, testing, and building when they don't depend on each other)
   - If the developer declines, proceed as usual with single-agent execution

2. **Check for npm pre-push script:**
   - Look for `package.json` in the current directory
   - If found, check if it has a `pre-push` script in the `scripts` section
   - If the script exists, run `npm run pre-push` and report the results
   - If successful, inform the user and STOP here

3. **If no pre-push script exists, auto-detect project checks:**

   a. **Identify project type:**
      - Check for `package.json` (Node.js/JavaScript/TypeScript project)
      - Check for `pyproject.toml`, `setup.py`, `requirements.txt` (Python project)
      - Check for `Cargo.toml` (Rust project)
      - Check for `go.mod` (Go project)
      - Check for other language-specific files

   b. **Detect and run linting tools:**
      - **Node.js/JavaScript/TypeScript:**
        - Check for ESLint: `eslint` in package.json scripts or `.eslintrc*` file
        - Check for Prettier: `prettier` in package.json scripts or `.prettierrc*` file
        - Check for TypeScript: `tsc` in package.json scripts or `tsconfig.json` file
        - Run: `npm run lint` or `npx eslint .` or `npm run type-check` or `npx tsc --noEmit`

      - **Python:**
        - Check for: `pylint`, `flake8`, `black`, `mypy`, `ruff`
        - Run available linters (e.g., `pylint src/`, `flake8 .`, `black --check .`, `mypy .`)

      - **Rust:**
        - Run: `cargo fmt --check` and `cargo clippy`

      - **Go:**
        - Run: `go fmt ./...` and `golint ./...` or `go vet ./...`

   c. **Detect and run tests:**
      - **Node.js:** Check for test scripts in package.json
        - Run: `npm test` or `npm run test:ci` (if available)

      - **Python:**
        - Check for: `pytest`, `unittest`, `nose2`
        - Run: `pytest` or `python -m pytest` or `python -m unittest discover`

      - **Rust:**
        - Run: `cargo test`

      - **Go:**
        - Run: `go test ./...`

   d. **Check for build errors:**
      - If applicable, try building the project to ensure no compilation errors
      - **Node.js:** `npm run build` (if script exists)
      - **Rust:** `cargo build`
      - **Go:** `go build ./...`

4. **Report results:**
   - Provide a clear summary of all checks performed
   - Report pass/fail status for each check
   - If any checks fail, show the errors and suggest fixes
   - Include the commands that were run for transparency
   - If all checks pass, confirm the code is ready to push

5. **Handle edge cases:**
   - If no tests or linting tools are detected, warn the user and ask if they want to proceed without checks
   - If commands fail due to missing dependencies, suggest installation commands
   - If in a monorepo or workspace, detect and handle appropriately

**Example output format:**

```
## Pre-Push Checks

### Linting
✅ ESLint passed
✅ Prettier check passed
✅ TypeScript compilation passed

### Testing
✅ All tests passed (24 tests, 0 failures)

### Build
✅ Build successful

---

🎉 All pre-push checks passed! Code is ready to push.

Commands run:
- npm run lint
- npm test
- npm run build
```

**On failure:**

```
## Pre-Push Checks

### Linting
❌ ESLint failed

Error in src/components/Button.tsx:
  15:7  error  'onClick' is missing in props validation  react/prop-types

### Testing
✅ All tests passed

---

⚠️ Pre-push checks failed. Please fix the issues above before pushing.
```
