---
name: address-ticket
description: Read the JIRA ticket associated with the current branch and propose an implementation plan. Requires JIRA MCP and a branch named with a conventional commit prefix and JIRA ID.
argument-hint: ""
---

Read the JIRA ticket for the current branch and propose a plan to address it. The branch must follow the `<conventional-commit-key>/<JIRA-ID>` naming convention.

**Usage:**
- `/address-ticket` - Analyze the JIRA ticket and propose an implementation plan

**Instructions:**

1. **Validate that JIRA MCP is available:**
   - Check that a JIRA MCP tool is configured and accessible
   - If JIRA MCP is NOT available, display the following error and STOP:
     ```
     ❌ JIRA MCP is not configured. This skill requires a working JIRA MCP integration.
     Please configure the JIRA MCP server before using /address-ticket.
     ```

2. **Validate the current branch name:**
   - Run `git branch --show-current` to get the current branch name
   - The branch name must match the pattern `<conventional-commit-key>/<JIRA-ID>` where:
     - `<conventional-commit-key>` is one of: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
     - `<JIRA-ID>` matches the pattern `[A-Z][A-Z0-9]+-[0-9]+` (e.g., `PROJ-123`, `AB-1`, `MYAPP-4567`)
   - Examples of valid branch names: `fix/PROJ-123`, `feat/MYAPP-456`, `refactor/AB-12`, `chore/CORE-99`
   - If the branch name does not match, display the following error and STOP:
     ```
     ❌ Invalid branch name: "<current-branch>"
     Expected format: <conventional-commit-key>/<JIRA-ID>
     Valid prefixes: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
     Example: fix/PROJ-123, feat/MYAPP-456
     ```

3. **Extract info from the branch name:**
   - Parse the conventional commit key (the part before `/`)
   - Parse the JIRA ID (the part after `/`)

4. **Fetch the JIRA ticket:**
   - Use the JIRA MCP tool to retrieve the issue by its JIRA ID
   - Fetch the following fields:
     - **Summary** (title)
     - **Description** (full body)
     - **Comments** (all comments on the ticket)
     - **Issue type** (Bug, Story, Task, etc.)
     - **Priority**
     - **Acceptance criteria** (if available, often in description or a custom field)
   - If the JIRA fetch fails (issue not found, permission denied, etc.), show the error and STOP

5. **Analyze the ticket and codebase:**
   - Read the ticket summary, description, and all comments thoroughly
   - Identify the key requirements, constraints, and acceptance criteria
   - Explore the codebase to understand:
     - Which files and modules are relevant to the ticket
     - Existing patterns and conventions in the affected areas
     - Any related tests that exist or will need updating
   - Consider the conventional commit key from the branch name as context for the type of work expected (e.g., `fix` implies a bug fix, `feat` implies new functionality, `refactor` implies restructuring)

6. **Propose an implementation plan:**

   Present a structured plan to the developer:

   ```
   ## Ticket: <JIRA-ID>
   **<Summary>**
   Type: <issue-type> | Priority: <priority> | Branch: <conventional-commit-key>/<JIRA-ID>

   ### Understanding
   <Brief summary of what the ticket is asking for, synthesized from the description and comments. Call out any ambiguities or conflicting information in the comments.>

   ### Acceptance Criteria
   <List the acceptance criteria extracted from the ticket. If none are explicit, derive them from the description.>

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

7. **Handle edge cases:**
   - If the ticket description is empty, note it and base the plan on the summary and comments only
   - If there are no comments, skip that section in the analysis
   - If the codebase exploration reveals the ticket may already be addressed, inform the developer
   - If the ticket is too vague to produce a concrete plan, list what is understood and what needs clarification
