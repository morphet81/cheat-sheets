---
name: address-ticket
version: 2.0.0
description: End-to-end ticket implementation. Reads the JIRA ticket, writes requirements and acceptance criteria for developer approval, spawns an implementation team, verifies tests, runs a code review with dedicated reviewers, and fixes any issues found.
argument-hint: ""
---

Read the JIRA ticket for the current branch and drive it to completion end-to-end: write requirements, get developer approval, implement with a team, verify tests, review changes, and fix any issues found.

**Usage:**
- `/address-ticket` - Analyze the JIRA ticket and drive it to full implementation

**Instructions:**

## Phase 1 — Gather Context

1. **Validate that JIRA MCP is available:**
   - Run `/mcp` to list the MCP servers available in the current context
   - Check that a JIRA (or Atlassian) MCP server is present and shows as connected/authenticated
   - If JIRA MCP is NOT available or not authenticated, display the following error and STOP:
     ```
     ❌ JIRA MCP is not configured or not authenticated.
     This skill requires a working JIRA MCP integration.
     Please configure and authenticate the JIRA MCP server before using /address-ticket.
     ```

2. **Extract the JIRA ID from the current branch name:**
   - Run `git branch --show-current` to get the current branch name
   - Extract the JIRA ID by matching the pattern `[A-Z][A-Z0-9]+-[0-9]+` (e.g., `PROJ-123`, `AB-1`, `MYAPP-4567`)
   - The JIRA ID can appear anywhere in the branch name (e.g., `fix/PROJ-123`, `feat/PROJ-123`, `PROJ-123-some-description`, `feature/PROJ-123-add-login`)
   - If no JIRA ID is found in the branch name, display the following error and STOP:
     ```
     ❌ No JIRA ID found in branch name: "<current-branch>"
     Expected a branch name containing a JIRA ID (e.g., PROJ-123).
     Examples: fix/PROJ-123, feat/MYAPP-456, PROJ-123-add-login
     ```

3. **Fetch the JIRA ticket:**
   - Use the JIRA MCP tool to retrieve the issue by its JIRA ID
   - Fetch **all available fields** on the ticket. Beyond the standard fields (summary, description, issue type, priority, comments), use every field that provides useful context — for example, bugs often have "Expected Behavior" and "Actual Behavior" fields, stories may have "Acceptance Criteria" fields, etc. Custom fields vary by project, so read whatever the ticket provides.
   - **Attachments**: Check for any images or files attached to the ticket. Download and analyze all attachments that are relevant to understanding the ticket (screenshots, mockups, diagrams, config files, logs, etc.). Use images as visual context for UI work. Use attached files (CSV, JSON, logs, etc.) as input for understanding the expected behavior or reproducing the issue.
   - If an attachment is too large to process or in an unsupported format, **continue working** with the remaining information but notify the developer:
     ```
     ⚠️ Could not analyze attachment: "<filename>" (<reason: too large / unsupported format / etc.>)
     Proceeding with the available information.
     ```
   - If the JIRA fetch fails (issue not found, permission denied, etc.), offer a fallback: use `AskUserQuestion` to ask the developer if they want to paste the ticket content manually. If the developer declines, STOP. If the developer provides content, continue with that.

4. **Retrieve Figma designs (if referenced):**

   Figma design links can appear in two places: directly as URLs in ticket fields, or as issue-level entity properties set by the Figma for Jira app ("Add Design" button). Check both sources.

   **a) Check ticket fields for Figma URLs:**
   - Search all ticket fields (description, comments, attachments, custom fields) for Figma URLs (e.g., `https://www.figma.com/design/...`, `https://www.figma.com/file/...`, `https://www.figma.com/proto/...`)

   **b) Check issue-level entity properties (Figma for Jira app):**
   - Figma designs added via the "Add Design" button are **not** stored in standard issue fields, remote links, or attachments. They are stored as **issue-level entity properties** — a separate data layer that the standard `GET /rest/api/3/issue/{key}` call does not return.
   - The Atlassian MCP tools do not include a "get issue properties" endpoint, so you must hit the REST API directly using the Bash tool:
     1. **List the issue's entity properties:**
        ```bash
        curl -s -H "Authorization: Bearer $ATLASSIAN_TOKEN" \
          "https://<site>.atlassian.net/rest/api/3/issue/<JIRA-ID>/properties/"
        ```
        Or use the `gh` CLI or any available HTTP tool. The Cloud ID and auth credentials should match the Atlassian MCP configuration.
     2. **Identify the Figma property key:** In the response, look for a property key related to Figma (the exact key name varies by installation, but typically contains "figma" or "design").
     3. **Fetch the Figma URL data:**
        ```bash
        curl -s -H "Authorization: Bearer $ATLASSIAN_TOKEN" \
          "https://<site>.atlassian.net/rest/api/3/issue/<JIRA-ID>/properties/<figma-property-key>"
        ```
        The response will contain the Figma design URL(s) and metadata.
   - If the REST API calls fail (auth issues, no properties found, etc.), **continue** with the remaining information — this is a best-effort retrieval.

   **c) Use retrieved Figma designs:**
   - If Figma URLs are found from either source:
     - Use the Figma MCP tools to retrieve design information (component structure, layout, spacing, colors, typography, assets, etc.)
     - Use the retrieved design data as visual and structural context for the implementation plan
     - If the Figma MCP is not installed or the request fails, display the following message and **continue** with the remaining ticket information:
       ```
       ⚠️ Figma MCP is not available or failed to retrieve design data.
       Figma reference found: <URL>
       Please review the design manually and share relevant details if needed.
       Continuing with the available ticket information.
       ```
   - If no Figma URLs are found from either source, skip this step silently

5. **Determine the conventional commit prefix:**
   - Based on all available ticket fields (issue type, summary, description, custom fields, etc.), deduce the most appropriate conventional commit prefix:
     - `feat` — new functionality or feature
     - `fix` — bug fix
     - `docs` — documentation-only changes
     - `style` — code style changes (formatting, whitespace, etc.)
     - `refactor` — code restructuring without behavior change
     - `perf` — performance improvement
     - `test` — adding or updating tests only
     - `build` — build system or dependency changes
     - `ci` — CI/CD configuration changes
     - `chore` — maintenance tasks, tooling, etc.
     - `revert` — reverting a previous change
   - Use the issue type as the primary signal (e.g., Bug → `fix`, Story with new functionality → `feat`)
   - Use the summary and description to refine when the issue type is ambiguous (e.g., a Task could be `refactor`, `chore`, `docs`, etc.)
   - If the branch name already contains a conventional commit prefix (e.g., `fix/PROJ-123`), use it as a hint but verify it makes sense given the ticket content
   - If you hesitate between multiple prefixes, use `AskUserQuestion` to let the developer choose. Present the top candidates with a brief explanation of why each could apply.

6. **Analyze the codebase:**
   - Read all available ticket fields thoroughly — summary, description, comments, and any custom fields (expected/actual behavior, acceptance criteria, steps to reproduce, etc.)
   - Incorporate any attached images or files into the analysis (e.g., use screenshots to understand UI expectations, use logs to identify error patterns, use mockups to guide implementation)
   - Explore the codebase to understand:
     - Which files and modules are relevant to the ticket
     - Existing patterns and conventions in the affected areas
     - Any related unit tests that exist or will need updating
     - The e2e test setup: look for Playwright config (`playwright.config.ts`), existing e2e test files, test directory structure, authentication patterns (storage state, global setup), and helper utilities
   - Consider the conventional commit prefix as context for the type of work expected (e.g., `fix` implies a bug fix, `feat` implies new functionality, `refactor` implies restructuring)

7. **Maintain the epic lore file:**

   Before writing requirements, check whether the current ticket belongs to a parent epic and maintain a lore file that captures accumulated context about the epic and its child tickets.

   **a) Identify the parent epic:**
   - From the ticket fields fetched in step 3, look for the parent epic link (e.g., the `Epic Link` field, `parent` field, or any field that references an epic).
   - If the ticket has a parent epic, fetch the epic using the JIRA MCP to get its summary, description, and acceptance criteria.
   - If the ticket has no parent epic, skip this step entirely.

   **b) Check for an existing lore file:**
   - Look for a `lore/` directory at the root of the project.
   - Check if a lore file already exists for this epic. The file should be named after the epic key: `lore/<EPIC-KEY>.md` (e.g., `lore/PROJ-42.md`).

   **c) Create or update the lore file:**
   - **If no `lore/` directory exists**, create it.
   - **If no lore file exists for this epic**, create `lore/<EPIC-KEY>.md` with the following structure:
     ```markdown
     # <EPIC-KEY>: <Epic Summary>

     ## Epic Description
     <Epic description and acceptance criteria from the epic ticket>

     ## Tickets

     ### <JIRA-ID>: <Ticket Summary>
     - **Type:** <issue-type> | **Priority:** <priority>
     - **Description:** <Brief summary of the ticket>
     - **Acceptance Criteria:** <Key acceptance criteria>
     ```
   - **If a lore file already exists for this epic**, append a new entry under the `## Tickets` section for the current ticket:
     ```markdown
     ### <JIRA-ID>: <Ticket Summary>
     - **Type:** <issue-type> | **Priority:** <priority>
     - **Description:** <Brief summary of the ticket>
     - **Acceptance Criteria:** <Key acceptance criteria>
     ```
   - The lore file serves as a living document that builds context as tickets in the epic are worked on. Each ticket entry should be concise but capture enough detail to understand the ticket's purpose within the broader epic.

## Phase 2 — Requirements & Acceptance Criteria

8. **Write requirements and acceptance criteria:**

   Based on all the context gathered in Phase 1 (ticket fields, Figma designs, codebase analysis, epic lore), write a comprehensive requirements document. Use `EnterPlanMode` to present it for developer approval.

   Structure the requirements as follows:

   ```
   ## Ticket: <JIRA-ID>
   **<Summary>**
   Type: <issue-type> | Priority: <priority> | Commit prefix: <conventional-commit-prefix>

   ### Understanding
   <Brief summary of what the ticket is asking for, synthesized from the description, comments, and Figma designs. Call out any ambiguities or conflicting information.>

   ### Requirements
   1. <Requirement 1 — clear, testable statement of what the implementation must do>
   2. <Requirement 2>
   3. ...

   ### Acceptance Criteria
   - [ ] <Criterion 1 — specific, verifiable condition that must be true when done>
   - [ ] <Criterion 2>
   - [ ] ...

   ### Implementation Plan
   1. <Step 1 — what to do and which files to touch>
   2. <Step 2>
   3. ...

   ### Files to Modify
   - `path/to/file.ts` — <what changes are needed>
   - `path/to/other.ts` — <what changes are needed>

   ### New Files
   - `path/to/new-file.ts` — <purpose>
   (or "None" if no new files are needed)

   ### Unit Tests
   - <Which unit test files to update or create>
   - <What scenarios to cover>

   ### E2E Tests
   - <Which e2e test files to update or create>
   - <User flows to cover: describe each flow as a sequence of actions and expected outcomes>
   - <Authentication requirements for the test scenarios>
   (or "None — changes are not user-facing" if e2e tests are not applicable)

   ### Risks / Open Questions
   - <Any uncertainties, assumptions, or things to clarify with the team>
   ```

   **E2E test planning guidelines:**
   - Include e2e tests for any user-facing changes: new pages, new UI flows, modified interactions, form submissions, navigation changes, etc.
   - Follow the project's existing e2e conventions: file naming, directory structure, authentication approach, helper utilities, and assertion patterns
   - Each e2e test should cover a complete user flow (e.g., "navigate to settings, change profile name, save, verify success toast and updated name")
   - For bug fixes, add an e2e test that reproduces the original bug scenario and verifies it is resolved
   - If the project has no e2e test setup, note this in the plan and propose setting one up as part of the implementation
   - Skip e2e tests only for non-user-facing changes (e.g., pure refactors with no behavior change, CI config, build tooling)

   Use `ExitPlanMode` to present the requirements for developer approval. **Do NOT proceed until the developer approves.** The developer may request changes — iterate on the requirements until they are satisfied.

## Phase 3 — Implementation

9. **Set up the implementation team:**

   Once the developer approves the requirements, spawn a team of agents to implement them. Use the `Task` tool with `run_in_background: true` to spawn parallel agents for independent work.

   **a) Partition the work:**
   - Analyze the approved plan and group implementation steps by independence — steps that touch different files or non-overlapping code regions can run in parallel
   - Common partitioning:
     - **Agent 1 — Source changes:** Implement the core code changes (new files, modified files)
     - **Agent 2 — Unit tests:** Write or update unit tests for the changes
     - **Agent 3 — E2E tests:** Write or update e2e tests (if applicable)
   - If steps have dependencies (e.g., tests depend on the source changes being written first), run the dependent steps sequentially after their prerequisites complete
   - For simple tickets where parallelization isn't beneficial (e.g., a single-file change with one test), a single agent is fine — don't force unnecessary splitting

   **b) Spawn the agents:**
   - Use the `Task` tool to spawn each agent with a clear, detailed prompt that includes:
     - The full approved requirements and acceptance criteria
     - The specific steps from the plan that the agent is responsible for
     - The relevant file paths and what changes are needed
     - The coding conventions and patterns observed in the codebase (from step 6)
     - Instructions to follow existing project patterns and not introduce new dependencies or abstractions unless specified in the plan

   **c) Monitor and merge:**
   - Wait for all agents to complete
   - Verify there are no conflicts between their changes (e.g., two agents modifying the same file)
   - If conflicts exist, resolve them by reading both agents' changes and merging them intelligently
   - Run a quick sanity check: ensure the codebase compiles/lints after all changes are applied

## Phase 4 — Test Verification

10. **Verify test coverage and correctness:**

    After the implementation team finishes, verify that all tests pass and coverage is adequate.

    **a) Run the test suites:**
    - Detect the project's test runner (e.g., `jest`, `vitest`, `pytest`, `go test`, etc.) and run the full unit test suite
    - If e2e tests were written, run them too using the project's e2e runner (e.g., `npx playwright test`, `npx cypress run`)
    - Capture the output of each test run

    **b) Verify coverage against acceptance criteria:**
    - Check that every acceptance criterion from step 8 has at least one test (unit or e2e) that verifies it
    - Check that edge cases identified in the plan are covered
    - Check that existing tests still pass (no regressions)

    **c) If all tests pass and coverage is adequate:**
    - Log the results and continue to Phase 5

    **d) If tests fail or coverage is insufficient:**
    - Spawn 1–2 tester agents using the `Task` tool with `run_in_background: true` to fix the issues:
      - Provide the failing test output, the acceptance criteria, and the relevant source files
      - Agent responsibilities:
        - Fix failing tests (both test code bugs and source code bugs exposed by tests)
        - Add missing test coverage for uncovered acceptance criteria
        - Ensure e2e tests run end-to-end without flakiness
    - Wait for the tester agents to complete
    - Re-run the test suites to confirm everything passes
    - If tests still fail after the fix attempt, report the remaining failures to the developer and continue to Phase 5 with a warning

## Phase 5 — Code Review

11. **Spawn review engineers:**

    Spawn 2 review agents using the `Task` tool with `run_in_background: true`. Each reviewer independently analyzes the changes from a different angle.

    **a) Reviewer 1 — Architecture & Security:**
    - Prompt the agent with the full diff (`git diff <base-branch>...HEAD`), the approved requirements, and the acceptance criteria
    - Review focus:
      - **Architecture:** Does the implementation follow existing patterns? Are there unnecessary abstractions or over-engineering? Is the code organized logically? Are there tight couplings or hidden dependencies?
      - **Security:** Are there injection vulnerabilities (SQL, XSS, command injection)? Is user input validated at system boundaries? Are authentication and authorization handled correctly? Are secrets or sensitive data exposed?
      - **Error handling:** Are error paths handled gracefully? Are there unhandled promise rejections or uncaught exceptions? Are error messages helpful without leaking internals?
      - **Performance:** Are there N+1 queries, unnecessary re-renders, memory leaks, or expensive operations in hot paths?
    - Output a numbered list of findings with severity (Critical / Major / Minor / Nit)

    **b) Reviewer 2 — Functionality & Completeness:**
    - Prompt the agent with the same diff, requirements, and acceptance criteria
    - Review focus:
      - **Requirements coverage:** Does every requirement and acceptance criterion have a corresponding implementation? Is anything missing?
      - **Feature correctness:** Are there logic errors, off-by-one mistakes, incorrect conditions, or wrong assumptions? Does the implementation handle edge cases?
      - **API contracts:** If new or modified APIs are involved, are request/response shapes correct? Are error responses consistent with existing patterns? Is backward compatibility maintained where needed?
      - **Test quality:** Do tests actually test what they claim? Are assertions meaningful? Are there missing test scenarios?
    - Output a numbered list of findings with severity (Critical / Major / Minor / Nit)

    **c) Collect and deduplicate findings:**
    - Wait for both reviewers to complete
    - Merge their findings into a single list, removing duplicates
    - Group by severity: Critical → Major → Minor → Nit

12. **Fix review findings:**

    **a) Filter actionable findings:**
    - Keep all Critical and Major findings — these must be fixed
    - Keep Minor findings that are straightforward to fix
    - Discard Nits unless they are trivially fixable (one-line changes)

    **b) If there are actionable findings:**
    - Present the findings to the developer:
      ```
      ## Code Review Findings

      ### Critical
      - **#1** — <description> (`file.ts:42`)
      - **#2** — <description> (`other.ts:15`)

      ### Major
      - **#3** — <description> (`file.ts:78`)

      ### Minor
      - **#4** — <description> (`file.ts:90`)

      Total: <N> findings to fix
      ```
    - Spawn a fix team (1–2 agents) using the `Task` tool with `run_in_background: true`:
      - Provide the full list of findings, the relevant files, and the project conventions
      - Each agent fixes their assigned findings
      - Agents must also ensure their fixes don't break existing tests
    - Wait for the fix team to complete
    - Re-run the test suites to confirm nothing is broken after the fixes
    - If tests fail after fixes, resolve the failures (spawn another agent if needed)

    **c) If there are no actionable findings:**
    - Log that the review passed cleanly and continue

## Phase 6 — Report

13. **Suggest ticket description improvements:**

    **a) Analyze the gap:**
    - Re-read the original ticket description (from step 3)
    - Review the actual changes made: files modified, features implemented, bugs fixed, edge cases handled
    - Identify discrepancies: was the scope broader or narrower than described? Were acceptance criteria missing or inaccurate? Were there undocumented requirements discovered during implementation?

    **b) Draft an improved description:**
    - Write a revised ticket description that accurately reflects what was implemented
    - Preserve any useful original content (context, background, links, references)
    - Add or improve:
      - **Clear problem statement** or feature rationale
      - **Acceptance criteria** that match the actual deliverables
      - **Technical notes** on the approach taken (briefly — not a code review, just enough for future readers to understand the change)
      - **Files/areas affected** (high-level, e.g., "Authentication module", "Settings page")
    - Keep the tone consistent with existing ticket descriptions in the project

    **c) Present to the developer:**
    - Show the proposed description in a clear before/after format:
      ```
      ## Suggested Ticket Description Update

      ### Current Description
      > <original description, or "(empty)" if there was none>

      ### Proposed Description
      <new description>

      ### What changed
      - <bullet list of key differences>
      ```
    - Use `AskUserQuestion` to ask the developer:
      > Would you like to update the JIRA ticket description with the proposed improvements?
    - Options: **Yes — update the ticket**, **No — skip**

    **d) Update the ticket (if approved):**
    - If the developer approves, use the JIRA MCP tool to update the ticket's description field
    - Confirm the update was successful:
      ```
      ✅ Ticket <JIRA-ID> description updated.
      ```
    - If the update fails, show the error and provide the proposed description as copyable text so the developer can update it manually

14. **Final report:**

    Present a comprehensive summary to the developer:

    ```
    ## Ticket Complete: <JIRA-ID>
    **<Summary>**

    ### Implementation
    - Files modified: <N>
    - Files added: <N>
    - Lines changed: +<additions> / -<deletions>

    ### Tests
    - Unit tests: <N> passing
    - E2E tests: <N> passing
    - Test fixes needed: <yes/no — how many rounds>

    ### Code Review
    - Findings: <N> critical, <N> major, <N> minor, <N> nits
    - All actionable findings fixed: <yes/no>
    - Remaining issues: <list, or "None">

    ### Acceptance Criteria
    - [ ] <Criterion 1> ✅
    - [ ] <Criterion 2> ✅
    - ...

    ### Next Steps
    - <Any remaining manual steps, e.g., "Run database migration", "Update env vars">
    - <Any findings that were deferred or need human judgment>
    ```

15. **Handle edge cases:**
    - If the ticket description is empty, note it and base the requirements on the summary and comments only
    - If there are no comments, skip that section in the analysis
    - If the codebase exploration reveals the ticket may already be addressed, inform the developer
    - If the ticket is too vague to produce concrete requirements, list what is understood and what needs clarification
    - If the project has no test framework, note it and skip Phase 4
    - If the review team finds no issues, report a clean review and skip the fix step
    - If fixes introduce new test failures in a loop (fix → fail → fix → fail), stop after 2 attempts and report the remaining issues to the developer
