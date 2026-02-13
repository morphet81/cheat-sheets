---
name: create-ticket
version: 1.0.0
description: Create a JIRA ticket from developer instructions. Previews the ticket before creation. Supports attaching Figma design links via the Figma for Jira integration.
argument-hint: "<description of the ticket>"
---

Create a JIRA ticket based on instructions provided by the developer. Shows a preview of the ticket before creating it. Supports attaching Figma design links.

**Usage:**
- `/create-ticket <description>` - Create a JIRA ticket from the provided description

**Instructions:**

1. **Validate that JIRA MCP is available:**
   - Run `/mcp` to list the MCP servers available in the current context
   - Check that a JIRA (or Atlassian) MCP server is present and shows as connected/authenticated
   - If JIRA MCP is NOT available or not authenticated, display the following error and STOP:
     ```
     ❌ JIRA MCP is not configured or not authenticated.
     This skill requires a working JIRA MCP integration.
     Please configure and authenticate the JIRA MCP server before using /create-ticket.
     ```

2. **Determine the target project:**
   - Check if the current branch contains a JIRA ID (pattern `[A-Z][A-Z0-9]+-[0-9]+`). If so, extract the project key from it (e.g., `PROJ` from `PROJ-123`).
   - If no JIRA ID is found in the branch, use the JIRA MCP to list available projects and ask the developer to choose one using `AskUserQuestion`.

3. **Parse the developer's instructions from $ARGUMENTS:**
   - The developer provides a free-text description of the ticket they want to create.
   - Extract or infer the following from the instructions:
     - **Summary**: A concise title for the ticket (one line, imperative mood)
     - **Issue type**: Bug, Story, Task, Sub-task, etc. — infer from context (e.g., "fix" or "broken" suggests Bug, "add" or "new" suggests Story, etc.)
     - **Description**: A detailed description in JIRA-compatible markdown
     - **Priority**: If mentioned; otherwise omit (let JIRA use the default)
     - **Parent epic or ticket**: If the developer mentions a parent epic or references a ticket to create a sub-task under
     - **Figma URLs**: Any `https://www.figma.com/...` links included in the instructions
   - If the instructions are too vague to produce a meaningful summary or description, use `AskUserQuestion` to ask for clarification.

4. **Compose the ticket description:**
   - Write a well-structured JIRA description based on the developer's instructions.
   - For **Bugs**, use this structure when applicable:
     ```
     ## Description
     <What is happening>

     ## Steps to Reproduce
     1. <Step 1>
     2. <Step 2>

     ## Expected Behavior
     <What should happen>

     ## Actual Behavior
     <What happens instead>
     ```
   - For **Stories/Tasks**, use this structure when applicable:
     ```
     ## Description
     <What needs to be done and why>

     ## Acceptance Criteria
     - [ ] <Criterion 1>
     - [ ] <Criterion 2>
     ```
   - Adapt the structure to the content — not every section is needed for every ticket. Keep it concise and relevant.

5. **Preview the ticket:**
   - Display a preview of the ticket to the developer for review before creating it:
     ```
     ## Ticket Preview

     **Project:** PROJ
     **Type:** Story
     **Summary:** Add bulk export for reports
     **Priority:** Medium (or "Default" if not specified)
     **Parent:** PROJ-42 (if applicable, otherwise omit this line)

     ### Description
     <The composed description from step 4>

     ### Figma Designs
     - <URL 1>
     - <URL 2>
     (or omit this section if no Figma URLs)
     ```
   - Use `AskUserQuestion` to ask the developer to confirm or request changes:
     - **"Create ticket"** — proceed with creation
     - **"Edit"** — the developer provides corrections, go back to step 4 with the feedback
   - Do NOT create the ticket until the developer confirms.

6. **Create the ticket:**
   - Use the JIRA MCP `createJiraIssue` tool to create the ticket with the confirmed details:
     - `projectKey`: the project key from step 2
     - `issueTypeName`: the issue type from step 3
     - `summary`: the summary from step 3
     - `description`: the description from step 4
     - `parent`: the parent key if creating a sub-task
   - If creation fails, display the error and STOP.

7. **Attach Figma designs (if provided):**
   - If the developer included Figma URLs in their instructions, attach them to the newly created ticket using the Figma for Jira "Add Design" mechanism.
   - Figma designs attached via "Add Design" are stored as **issue-level entity properties**, not as standard fields or remote links. To set them via the REST API:
     1. **Determine the Figma property key:** List the issue's entity properties to check if a Figma property key already exists:
        ```bash
        curl -s -H "Authorization: Bearer $ATLASSIAN_TOKEN" \
          "https://<site>.atlassian.net/rest/api/3/issue/<JIRA-ID>/properties/"
        ```
     2. **Set the Figma design property:** Use a PUT request to set the design link as an entity property. The property key and value format depend on the Figma for Jira app installation, but typically:
        ```bash
        curl -s -X PUT -H "Authorization: Bearer $ATLASSIAN_TOKEN" \
          -H "Content-Type: application/json" \
          "https://<site>.atlassian.net/rest/api/3/issue/<JIRA-ID>/properties/<figma-property-key>" \
          -d '{"figmaDesigns": [{"url": "<figma-url>", "name": "<design-name>"}]}'
        ```
   - If the REST API calls fail (auth issues, property key unknown, etc.), fall back to including the Figma URLs as links in the ticket description and notify the developer:
     ```
     ⚠️ Could not attach Figma designs via the "Add Design" integration.
     Figma URLs have been included in the ticket description instead.
     You can manually attach them using the "Add Design" button in JIRA.
     ```

8. **Show success message:**

   Display a summary with all relevant information:

   ```
   ## Ticket Created

   - Key: PROJ-456
   - Type: Story
   - Summary: Add bulk export for reports
   - URL: https://<site>.atlassian.net/browse/PROJ-456
   - Figma: 2 design(s) attached (or "None" if no Figma URLs)
   ```

9. **Handle edge cases:**
   - If `$ARGUMENTS` is empty, use `AskUserQuestion` to ask the developer to describe the ticket they want to create
   - If the JIRA project has required custom fields that weren't provided, display them and ask the developer to fill them in before retrying
   - If the developer cancels at the preview step, display "Ticket creation cancelled." and STOP
