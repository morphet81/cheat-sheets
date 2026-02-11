---
name: verify-test-cases
version: 1.0.0
description: Verify test cases in all test files modified since last push. Checks that test cases make sense, have no duplications, and provide meaningful coverage.
argument-hint: ""
---

Verify the quality and correctness of test cases in all test files modified since last push.

**Usage:**
- `/verify-test-cases` - Verify test files modified since the last push

**Instructions:**

1. **Identify modified test files since last push:**
   - Run `git log --oneline @{push}..HEAD` to see unpushed commits (if this fails, fall back to `git diff --name-only origin/$(git branch --show-current)..HEAD`)
   - Run `git diff --name-only @{push}..HEAD` to get all files modified since last push (if this fails, fall back to `git diff --name-only origin/$(git branch --show-current)..HEAD`)
   - Filter for test files using common patterns:
     - `*.test.*`, `*.spec.*` (JS/TS)
     - `test_*.py`, `*_test.py` (Python)
     - `*_test.go` (Go)
     - `*_test.rs`, files under `tests/` (Rust)
     - Files under `__tests__/`, `test/`, `tests/`, `spec/` directories
   - If no test files were modified, inform the user and STOP

2. **Read and analyze each test file:**
   - Read the full content of each modified test file
   - Also read the source file(s) being tested to understand the code under test

3. **Verify test cases make sense:**
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

4. **Check for duplications:**
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

5. **Report findings:**

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

6. **Handle edge cases:**
   - If there are no unpushed commits, inform the user and STOP
   - If modified files include both test and source files, use the source files for context but only report on the test files
   - If a test file imports from files you can't find, note it but continue analysis
   - For very large test files (>500 lines), focus on the changed sections using `git diff` for those specific files
