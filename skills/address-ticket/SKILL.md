---
name: address-ticket
version: 3.3.0
description: End-to-end ticket implementation with a multi-agent team. Retrieves JIRA ticket details and Figma designs, spawns a PO to write requirements, gets developer approval, then ramps up designers (if needed), developers, and testers to implement everything.
argument-hint: ""
---

Read the JIRA ticket for the current branch and drive it to completion using a multi-agent team: a PO writes requirements, the developer approves, then designers, developers, and testers execute the work.

**Usage:**
- `/address-ticket` - Retrieve the ticket and drive it to full implementation with a team

**Instructions:**

## Phase 1 — Gather Context

1. **Validate that the Atlassian CLI is available and authenticated:**
   - Run `acli auth status` to check if the CLI is installed and authenticated
   - If the command is not found, display the following error and STOP:
     ```
     Atlassian CLI (acli) is not installed.
     This skill requires the Atlassian CLI.
     Install it with: brew tap atlassian/acli && brew install acli
     ```
   - If the command fails with an authentication error, display the following error and STOP:
     ```
     Atlassian CLI is not authenticated.
     This skill requires an authenticated Atlassian CLI.
     Please run `acli auth login` to authenticate before using /address-ticket.
     ```

2. **Extract the JIRA ID from the current branch name:**
   - Run `git branch --show-current` to get the current branch name
   - Extract the JIRA ID by matching the pattern `[A-Z][A-Z0-9]+-[0-9]+` (e.g., `PROJ-123`, `AB-1`, `MYAPP-4567`)
   - The JIRA ID can appear anywhere in the branch name (e.g., `fix/PROJ-123`, `feat/PROJ-123`, `PROJ-123-some-description`, `feature/PROJ-123-add-login`)
   - If no JIRA ID is found in the branch name, display the following error and STOP:
     ```
     No JIRA ID found in branch name: "<current-branch>"
     Expected a branch name containing a JIRA ID (e.g., PROJ-123).
     Examples: fix/PROJ-123, feat/MYAPP-456, PROJ-123-add-login
     ```

3. **Fetch the JIRA ticket:**
   - Use the Atlassian CLI to retrieve the issue by its JIRA ID:
     ```bash
     acli jira workitem view <JIRA-ID> --fields '*all' --json
     ```
   - This fetches **all available fields** on the ticket. Beyond the standard fields (summary, description, issue type, priority, comments), use every field that provides useful context — for example, bugs often have "Expected Behavior" and "Actual Behavior" fields, stories may have "Acceptance Criteria" fields, etc. Custom fields vary by project, so read whatever the ticket provides.
   - **Attachments**: Check for any images or files attached to the ticket. Download and analyze all attachments that are relevant to understanding the ticket (screenshots, mockups, diagrams, config files, logs, etc.). Use images as visual context for UI work. Use attached files (CSV, JSON, logs, etc.) as input for understanding the expected behavior or reproducing the issue.
   - If an attachment is too large to process or in an unsupported format, **continue working** with the remaining information but notify the developer:
     ```
     Could not analyze attachment: "<filename>" (<reason: too large / unsupported format / etc.>)
     Proceeding with the available information.
     ```
   - If the JIRA fetch fails (issue not found, permission denied, etc.), offer a fallback: use `AskUserQuestion` to ask the developer if they want to paste the ticket content manually. If the developer declines, STOP. If the developer provides content, continue with that.

4. **Retrieve Figma designs (if referenced):**

   Figma design links can appear in two places: directly as URLs in ticket fields, or as issue-level entity properties set by the Figma for Jira app ("Add Design" button). Check both sources.

   **a) Check ticket fields for Figma URLs:**
   - Search all ticket fields (description, comments, attachments, custom fields) for Figma URLs (e.g., `https://www.figma.com/design/...`, `https://www.figma.com/file/...`, `https://www.figma.com/proto/...`)

   **b) Check issue-level entity properties (Figma for Jira app):**
   - Figma designs added via the "Add Design" button are **not** stored in standard issue fields, remote links, or attachments. They are stored as **issue-level entity properties** — a separate data layer that the standard issue view does not return.
   - Retrieve the Atlassian site URL from `acli config list` or the authenticated site context, then hit the REST API directly using the Bash tool:
     1. **List the issue's entity properties:**
        ```bash
        acli jira workitem view <JIRA-ID> --json
        ```
        Extract the site URL from the `self` link in the response, then:
        ```bash
        curl -s -H "Authorization: Bearer $(acli auth token)" \
          "https://<site>.atlassian.net/rest/api/3/issue/<JIRA-ID>/properties/"
        ```
     2. **Identify the Figma property key:** In the response, look for a property key related to Figma (the exact key name varies by installation, but typically contains "figma" or "design").
     3. **Fetch the Figma URL data:**
        ```bash
        curl -s -H "Authorization: Bearer $(acli auth token)" \
          "https://<site>.atlassian.net/rest/api/3/issue/<JIRA-ID>/properties/<figma-property-key>"
        ```
        The response will contain the Figma design URL(s) and metadata.
   - If the REST API calls fail (auth issues, no properties found, etc.), **continue** with the remaining information — this is a best-effort retrieval.

   **c) Request design assets from the user:**
   - If Figma URLs are found from either source:
     - Display the Figma URLs to the developer and use `AskUserQuestion` to request design assets:
       > Figma design link(s) found in the ticket:
       > - <URL 1>
       > - <URL 2>
       >
       > Please export the relevant screens/components as PNG or SVG files and provide the file path(s).
       > You can drag and drop the files into the chat, or provide absolute paths to already-exported files.
     - Options: **"I've provided the files"**, **"Skip — no design assets needed"**
     - If the developer provides file paths, read and analyze the PNG/SVG files to understand the design (layout, components, spacing, colors, typography, visual hierarchy, interaction states)
     - Store the design data extracted from the images — it will be passed to the PO and design agents
     - If the developer chooses to skip, **continue** with the remaining ticket information and note that Figma designs were referenced but no assets were provided
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
   - Use the issue type as the primary signal (e.g., Bug -> `fix`, Story with new functionality -> `feat`)
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

   Before spawning the PO, check whether the current ticket belongs to a parent epic and maintain a lore file that captures accumulated context about the epic and its child tickets.

   **a) Identify the parent epic:**
   - From the ticket fields fetched in step 3, look for the parent epic link (e.g., the `Epic Link` field, `parent` field, or any field that references an epic).
   - If the ticket has a parent epic, fetch the epic using the Atlassian CLI to get its summary, description, and acceptance criteria:
     ```bash
     acli jira workitem view <EPIC-KEY> --fields summary,description,acceptance-criteria --json
     ```
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

## Phase 2 — Product Owner: Requirements & Acceptance Criteria

8. **Spawn the Product Owner agent:**

   Use the `Task` tool to spawn a PO agent. This agent is responsible for writing requirements and acceptance criteria based on all the context gathered in Phase 1. The PO agent does NOT implement anything — it only produces a requirements document.

   **a) Prepare the PO prompt:**
   - Pass the PO agent ALL context gathered so far:
     - The full JIRA ticket content (summary, description, all fields, comments, attachments)
     - Figma design data (if any was retrieved)
     - The conventional commit prefix determined in step 5
     - The codebase analysis from step 6 (relevant files, patterns, conventions, test setup)
     - The epic lore file content (if any)
   - Instruct the PO agent to produce a requirements document with the following structure:

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

   ### Design Needs
   - <Whether this ticket requires design work: Yes / No>
   - <If yes, what aspects need design: UI layout, component design, interaction patterns, etc.>
   - <If Figma designs are provided, note which aspects are already covered and which need further design work>

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

   **b) E2E test planning guidelines (include in the PO prompt):**
   - Include e2e tests for any user-facing changes: new pages, new UI flows, modified interactions, form submissions, navigation changes, etc.
   - Follow the project's existing e2e conventions: file naming, directory structure, authentication approach, helper utilities, and assertion patterns
   - Each e2e test should cover a complete user flow (e.g., "navigate to settings, change profile name, save, verify success toast and updated name")
   - For bug fixes, add an e2e test that reproduces the original bug scenario and verifies it is resolved
   - If the project has no e2e test setup, note this and propose setting one up as part of the implementation
   - Skip e2e tests only for non-user-facing changes (e.g., pure refactors with no behavior change, CI config, build tooling)

   **c) Wait for the PO agent to complete** and collect its requirements document.

9. **Present requirements to the developer for approval:**

   Display the PO's requirements document to the developer and use `AskUserQuestion` to ask for confirmation:
   > The Product Owner has prepared the following requirements and acceptance criteria. Would you like to proceed?

   - **Approve** — requirements are accepted, proceed to Phase 3
   - **Request changes** — the developer provides feedback on what to adjust
   - **Reject** — stop the skill execution entirely

   **If "Request changes":**
   - Use `AskUserQuestion` to collect the developer's feedback
   - Re-spawn the PO agent with the original context plus the developer's feedback, asking it to revise the requirements
   - Present the revised requirements again for approval
   - Repeat until the developer approves or rejects

   **Do NOT proceed to Phase 3 until the developer explicitly approves.**

## Phase 3 — Implementation Team

10. **Determine team composition:**

    Based on the approved requirements, decide which agents to spawn. The team always includes developers and testers, but designers are conditional.

    **a) Designers — conditional:**
    - If the requirements' "Design Needs" section says **No**: skip designers entirely
    - If the requirements say **Yes** and Figma designs were provided (step 4): spawn **1 designer** agent
    - If the requirements say **Yes** and no Figma designs are available: spawn **2 designer** agents

    **b) Developers:** always spawn **2–3 developer** agents (based on the scope of implementation work)

    **c) Testers:** always spawn **1–2 tester** agents (based on the amount of test work needed)

11. **Spawn designer agents (if needed):**

    If designers are needed, spawn them FIRST and wait for them to complete before spawning developers and testers.

    **If 1 designer (design assets provided):**
    - Spawn 1 designer agent using the `Task` tool
    - The designer's job is to:
      - Analyze the PNG/SVG design assets provided by the developer in step 4
      - Map visual components in the designs to existing codebase components
      - Produce a design implementation guide: which components to use, spacing, colors, typography, responsive behavior, interaction states
      - Identify any gaps between the design assets and the requirements
    - Pass the agent: the approved requirements, the design asset file paths (so the agent can read/view them), and the codebase analysis (existing components, design system, styling patterns)

    **If 2 designers (no Figma):**
    - Spawn 2 designer agents in parallel using the `Task` tool with `run_in_background: true`
    - **Designer 1 — Research:** Explore the existing codebase for design patterns, component libraries, design tokens, and styling conventions. Document the design system already in use.
    - **Designer 2 — Propose:** Based on the requirements and the existing design patterns (share Designer 1's findings once available), propose a UI/UX approach: component structure, layout, interactions, and visual design decisions.
    - Wait for both to complete and consolidate their output into a design guide for the developers.

    **Pass the design guide to the developer and tester agents** as additional context.

12. **Spawn developer agents:**

    Spawn 2–3 developer agents using the `Task` tool with `run_in_background: true`. Partition the work so agents work on independent areas and don't conflict.

    **a) Partition the work:**
    - Analyze the approved implementation plan and group steps by independence — steps that touch different files or non-overlapping code regions can run in parallel
    - Common partitioning strategies:
      - By feature area (e.g., one agent does the API changes, another does the UI)
      - By layer (e.g., one agent does the backend, another does the frontend)
      - By file group (e.g., one agent modifies existing files, another creates new files)
    - For simple tickets where parallelization isn't beneficial (e.g., a single-file change), 2 agents is fine — one implements, the other reviews and assists
    - If steps have dependencies (e.g., one change depends on another being written first), note this and have the dependent agent wait

    **b) Prompt each developer agent with:**
    - The full approved requirements and acceptance criteria
    - Their specific assigned steps from the implementation plan
    - The relevant file paths and what changes are needed
    - The coding conventions and patterns observed in the codebase (from step 6)
    - The design guide (if designers produced one)
    - Instructions to follow existing project patterns and not introduce new dependencies or abstractions unless specified in the plan

    **c) Wait for all developer agents to complete.**

    **d) Merge and verify:**
    - Check for conflicts between agents' changes (two agents modifying the same file)
    - If conflicts exist, resolve them by reading both agents' changes and merging intelligently
    - Run a quick sanity check: ensure the codebase compiles/lints after all changes are applied

13. **Spawn tester agents:**

    Spawn 1–2 tester agents using the `Task` tool with `run_in_background: true`. Testers work AFTER developers so they can test the actual implementation.

    **a) Prompt each tester agent with:**
    - The full approved requirements and acceptance criteria
    - The list of files modified/created by the developer agents
    - The unit test and e2e test plans from the requirements
    - The project's test setup, conventions, and existing test files
    - Instructions to:
      - Write or update unit tests covering the acceptance criteria
      - Write or update e2e tests for user-facing changes (if applicable)
      - Run the tests and fix any failures
      - Ensure existing tests still pass (no regressions)

    **b) Wait for all tester agents to complete.**

    **c) Verify test results:**
    - Run the full test suite (unit + e2e if applicable) to confirm everything passes
    - If tests fail, spawn 1 additional tester agent to fix the failures
    - If tests still fail after the fix attempt, report the remaining failures to the developer

## Phase 4 — Suggest JIRA Ticket Updates

14. **Suggest ticket edits based on requirements and acceptance criteria:**

    After the team finishes, suggest improvements to the original JIRA ticket based on the requirements and acceptance criteria written during this skill's execution.

    **a) Analyze the gap:**
    - Re-read the original ticket description (from step 3)
    - Compare it against the PO's approved requirements and acceptance criteria (from step 9)
    - Identify what is missing from the ticket:
      - Acceptance criteria that were written by the PO but aren't in the original ticket
      - Requirements that were clarified or expanded during the PO phase
      - Design decisions made by the designers (if applicable)
      - Technical notes on the approach taken

    **b) Draft an improved description:**
    - Write a revised ticket description that incorporates the requirements and acceptance criteria
    - Preserve any useful original content (context, background, links, references)
    - Add or improve:
      - **Clear problem statement** or feature rationale
      - **Acceptance criteria** from the PO's document
      - **Technical notes** on the approach taken (briefly — just enough for future readers)
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
    - If the developer approves, write the description as an ADF JSON payload and use `--from-json` to update (see [ADF Format Reference](#adf-format-reference) below):
      ```bash
      acli jira workitem edit --from-json <temp-file.json> --yes
      ```
      The JSON file must contain the full edit payload with the description as an ADF object:
      ```json
      {
        "issues": ["<JIRA-ID>"],
        "description": {
          "version": 1,
          "type": "doc",
          "content": [ ... ADF nodes ... ]
        }
      }
      ```
    - Confirm the update was successful:
      ```
      Ticket <JIRA-ID> description updated.
      ```
    - If the update fails, show the error and provide the proposed description as copyable text so the developer can update it manually

15. **Final report:**

    Present a comprehensive summary to the developer:

    ```
    ## Ticket Complete: <JIRA-ID>
    **<Summary>**

    ### Team
    - PO: requirements and acceptance criteria written
    - Designers: <N> (or "None — no design work needed")
    - Developers: <N>
    - Testers: <N>

    ### Implementation
    - Files modified: <N>
    - Files added: <N>
    - Lines changed: +<additions> / -<deletions>

    ### Tests
    - Unit tests: <N> passing
    - E2E tests: <N> passing (or "N/A")
    - Test fixes needed: <yes/no — how many rounds>

    ### Acceptance Criteria
    - [x] <Criterion 1>
    - [x] <Criterion 2>
    - ...

    ### JIRA Ticket
    - Description updated: <yes/no>

    ### Next Steps
    - <Any remaining manual steps, e.g., "Run database migration", "Update env vars">
    - <Any issues that need human judgment>
    ```

16. **Handle edge cases:**
    - If the ticket description is empty, note it and the PO should base requirements on the summary and comments only
    - If there are no comments, skip that section in the analysis
    - If the codebase exploration reveals the ticket may already be addressed, inform the developer before spawning the PO
    - If the ticket is too vague, the PO should list what is understood and flag open questions for the developer to answer during the approval step
    - If the project has no test framework, note it and skip tester agents
    - If designer agents produce conflicting recommendations, present both to the developer and let them choose
    - If developer agents produce conflicting changes to the same file, resolve the conflicts before spawning testers
    - If test fixes loop (fix -> fail -> fix -> fail), stop after 2 attempts and report remaining issues to the developer

---

## ADF Format Reference

JIRA does **not** render Markdown. Descriptions must use **Atlassian Document Format (ADF)** — a JSON-based document format. The `--description-file` flag treats file content as a plain text string, so it cannot be used for rich descriptions. Use `--from-json` instead.

**Important:** `--from-json` expects a structured JSON file with the full edit payload. The `description` field must be an ADF object, not a string. You can run `acli jira workitem edit --generate-json` to see the expected schema.

**Edit payload format (`--from-json`):**

```json
{
  "issues": ["<JIRA-ID>"],
  "description": {
    "version": 1,
    "type": "doc",
    "content": [
      {
        "type": "heading",
        "attrs": { "level": 2 },
        "content": [{ "type": "text", "text": "Description" }]
      },
      {
        "type": "paragraph",
        "content": [{ "type": "text", "text": "What was implemented." }]
      },
      {
        "type": "heading",
        "attrs": { "level": 2 },
        "content": [{ "type": "text", "text": "Acceptance Criteria" }]
      },
      {
        "type": "taskList",
        "attrs": { "localId": "ac-list" },
        "content": [
          {
            "type": "taskItem",
            "attrs": { "localId": "ac-1", "state": "TODO" },
            "content": [{ "type": "text", "text": "First criterion" }]
          }
        ]
      }
    ]
  }
}
```

**Common ADF node types:**

| Markdown | ADF `type` | Notes |
|----------|-----------|-------|
| `## Heading` | `heading` with `attrs.level` | Levels 1–6 |
| Plain text | `paragraph` with `text` children | |
| `**bold**` | `text` with `marks: [{"type": "strong"}]` | |
| `*italic*` | `text` with `marks: [{"type": "em"}]` | |
| `- item` | `bulletList` > `listItem` > `paragraph` | |
| `1. item` | `orderedList` > `listItem` > `paragraph` | |
| `- [ ] task` | `taskList` > `taskItem` (state: `TODO`/`DONE`) | |
| `` `code` `` | `text` with `marks: [{"type": "code"}]` | Inline code |
| Code block | `codeBlock` with `attrs.language` | |
| `---` | `rule` | Horizontal rule |
| `[link](url)` | `text` with `marks: [{"type": "link", "attrs": {"href": "url"}}]` | |
