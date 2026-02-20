---
name: verify-test-cases
version: 1.2.0
description: Verify test cases in all test files modified since branching out from base branch. Checks that test cases make sense, have no duplications, and provide meaningful coverage.
argument-hint: ""
---

Verify the quality and correctness of test cases in all test files modified since branching out from the base branch.

**Usage:**
- `/verify-test-cases` - Verify test files modified since branching from base branch

**Instructions:**

1. **Check for Claude Teams:**

   Before analyzing test files, check whether Claude Teams (multi-agent parallel execution) is available and offer it to the developer.

   **a) Detect availability:**
   - Run `echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` via the Bash tool to check the environment variable
   - If the value is not `1`, Claude Teams is not enabled — skip this step silently

   **b) Ask the developer:**
   - If the environment variable is `1`, use `AskUserQuestion` to ask:
     > Claude Teams is available on this machine. Would you like to enable parallel agents for this task? Teams mode will analyze different test files in parallel for faster execution.
   - Provide two options: **Yes — use Teams** and **No — single agent**

   **c) Enable teams:**
   - If the developer chooses to use Teams, use the `Task` tool with `run_in_background: true` to spawn parallel agents for independent test file analysis (e.g., separate agents analyzing different test files simultaneously)
   - If the developer declines, proceed as usual with single-agent execution

2. **Determine the base branch:**
   - Check if a `.agent` file exists in the current directory
   - If it exists, read it and look for a `baseBranch=<value>` line to extract the base branch
   - If no `.agent` file or no `baseBranch` key, default to `main`

3. **Identify modified test files since branching:**
   - Run `git diff --name-only <base-branch>...HEAD` to get all files modified since branching from the base branch
   - Filter for test files using common patterns:
     - `*.test.*`, `*.spec.*` (JS/TS)
     - `test_*.py`, `*_test.py` (Python)
     - `*_test.go` (Go)
     - `*_test.rs`, files under `tests/` (Rust)
     - Files under `__tests__/`, `test/`, `tests/`, `spec/` directories
   - If no test files were modified, inform the user and STOP

4. **Read and analyze each test file:**
   - Read the full content of each modified test file
   - Also read the source file(s) being tested to understand the code under test

5. **Verify test cases make sense:**
   For each test file, check that:

   a. **Test descriptions match behavior:**
      - Test names/descriptions accurately reflect what is being tested
      - The test body actually tests what the name says it does

   b. **Assertions are meaningful:**
      - Tests have actual assertions (not just running code without checking results)
      - Assertions verify the right thing (not just `toBeTruthy()` on everything)
      - Edge cases and boundary conditions are covered where appropriate

   c. **Test setup is correct:**
      - Mocks and stubs make sense for what's being tested
      - Test fixtures and data are realistic
      - Setup/teardown properly initializes and cleans up state

   d. **Tests are independent:**
      - Tests don't rely on execution order
      - Shared state isn't leaking between tests

   e. **Tests match the source code:**
      - Tests cover the actual function signatures and behavior
      - Tests aren't testing stale or non-existent APIs

6. **Check for duplications:**
   For each test file and across all modified test files:

   a. **Exact duplicates:**
      - Tests with identical or near-identical test bodies
      - Copy-pasted tests that weren't modified

   b. **Logical duplicates:**
      - Different tests that verify the exact same behavior
      - Tests that overlap significantly in what they cover

   c. **Redundant assertions:**
      - Multiple assertions in separate tests that check the same thing
      - Tests that are strict subsets of other tests

7. **Report findings:**

   Format the output as follows:

```
## Test Verification Report

### Files Analyzed
- `path/to/file.test.ts` (N tests)
- `path/to/other.spec.js` (N tests)

### Issues Found

#### Nonsensical / Incorrect Tests
- **file.test.ts:42** `"should handle empty input"` - Test passes a non-empty string, contradicting its description
- **file.test.ts:67** `"should return user"` - No assertion on the return value

#### Duplicate Tests
- **file.test.ts:30** and **file.test.ts:55** - Both test the same "valid email" scenario with identical logic
- **other.spec.js:12** and **other.spec.js:40** - Logically equivalent: both verify default config values

#### Missing Coverage
- `createUser()` has no test for the error/rejection path
- Edge case: empty array input is not tested for `processItems()`

### Summary
- Total test files analyzed: N
- Total test cases reviewed: N
- Issues found: N
- Duplicates found: N
- Verdict: PASS / NEEDS ATTENTION
```

8. **Handle edge cases:**
   - If there are no commits on the branch compared to the base branch, inform the user and STOP
   - If modified files include both test and source files, use the source files for context but only report on the test files
   - If a test file imports from files you can't find, note it but continue analysis
   - For very large test files (>500 lines), focus on the changed sections using `git diff` for those specific files
