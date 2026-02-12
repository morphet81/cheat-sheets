---
name: address-ticket
version: 1.4.0
description: Read the JIRA ticket associated with the current branch and propose an implementation plan. Requires JIRA MCP and a branch named with a JIRA ID.
argument-hint: ""
---

Read the JIRA ticket for the current branch and propose a plan to address it. The branch must contain a JIRA ID (e.g., `feat/PROJ-123`, `fix/PROJ-123`, or just `PROJ-123`).

**Usage:**
- `/address-ticket` - Analyze the JIRA ticket and propose an implementation plan

**Instructions:**

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

6. **Analyze the ticket and codebase:**
   - Read all available ticket fields thoroughly — summary, description, comments, and any custom fields (expected/actual behavior, acceptance criteria, steps to reproduce, etc.)
   - Incorporate any attached images or files into the analysis (e.g., use screenshots to understand UI expectations, use logs to identify error patterns, use mockups to guide implementation)
   - Identify the key requirements, constraints, and acceptance criteria from all available fields
   - Explore the codebase to understand:
     - Which files and modules are relevant to the ticket
     - Existing patterns and conventions in the affected areas
     - Any related unit tests that exist or will need updating
     - The e2e test setup: look for Playwright config (`playwright.config.ts`), existing e2e test files, test directory structure, authentication patterns (storage state, global setup), and helper utilities
   - Consider the conventional commit prefix as context for the type of work expected (e.g., `fix` implies a bug fix, `feat` implies new functionality, `refactor` implies restructuring)

7. **Propose an implementation plan using Plan Mode:**

   Use `EnterPlanMode` to switch to plan mode, then write the implementation plan. This ensures the developer reviews and approves the plan before any code is written.

   Structure the plan as follows:

   ```
   ## Ticket: <JIRA-ID>
   **<Summary>**
   Type: <issue-type> | Priority: <priority> | Commit prefix: <conventional-commit-prefix>

   ### Understanding
   <Brief summary of what the ticket is asking for, synthesized from the description and comments. Call out any ambiguities or conflicting information in the comments.>

   ### Acceptance Criteria
   <List the acceptance criteria extracted from the ticket summary and description. If none are explicit, derive them from the description.>

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

   Use `ExitPlanMode` to present the plan for developer approval. Only proceed with implementation after the developer approves.

8. **Handle edge cases:**
   - If the ticket description is empty, note it and base the plan on the summary and comments only
   - If there are no comments, skip that section in the analysis
   - If the codebase exploration reveals the ticket may already be addressed, inform the developer
   - If the ticket is too vague to produce a concrete plan, list what is understood and what needs clarification
