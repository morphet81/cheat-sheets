---
name: address-ticket
version: 1.1.0
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

4. **Determine the conventional commit prefix:**
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

5. **Analyze the ticket and codebase:**
   - Read all available ticket fields thoroughly — summary, description, comments, and any custom fields (expected/actual behavior, acceptance criteria, steps to reproduce, etc.)
   - Incorporate any attached images or files into the analysis (e.g., use screenshots to understand UI expectations, use logs to identify error patterns, use mockups to guide implementation)
   - Identify the key requirements, constraints, and acceptance criteria from all available fields
   - Explore the codebase to understand:
     - Which files and modules are relevant to the ticket
     - Existing patterns and conventions in the affected areas
     - Any related tests that exist or will need updating
   - Consider the conventional commit prefix as context for the type of work expected (e.g., `fix` implies a bug fix, `feat` implies new functionality, `refactor` implies restructuring)

6. **Propose an implementation plan using Plan Mode:**

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

   ### Tests
   - <Which test files to update or create>
   - <What scenarios to cover>

   ### Risks / Open Questions
   - <Any uncertainties, assumptions, or things to clarify with the team>
   ```

   Use `ExitPlanMode` to present the plan for developer approval. Only proceed with implementation after the developer approves.

7. **Handle edge cases:**
   - If the ticket description is empty, note it and base the plan on the summary and comments only
   - If there are no comments, skip that section in the analysis
   - If the codebase exploration reveals the ticket may already be addressed, inform the developer
   - If the ticket is too vague to produce a concrete plan, list what is understood and what needs clarification
