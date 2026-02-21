---
name: team
version: 1.0.0
description: Set up a multi-agent team to implement a new functionality. Spawns a product owner, optional designers, developers, and testers based on the task. Provide a description of what to build.
argument-hint: "<task description>"
---

Assemble a multi-agent team and implement the functionality described in `$ARGUMENTS`.

**Usage:**
- `/team <task description>` — Spawn a full team and implement the described functionality

**Instructions:**

1. **Read the task description from `$ARGUMENTS`.**
   - If `$ARGUMENTS` is empty, ask the user to describe the functionality to implement before continuing.

2. **Assess the task to determine team composition:**
   - Does the task involve any UI or user-facing interface? → include 1–2 designers
   - How complex is the implementation? → 1 developer for simple tasks, up to 3 for complex ones
   - Always include at least 1 tester

3. **Create the team** using `TeamCreate` with a short kebab-case name derived from the task (e.g. `user-auth`, `dashboard-filters`).

4. **Create a task list** using `TaskCreate` to track deliverables for each role before spawning agents:
   - One task for the product owner: "Write requirements and acceptance criteria"
   - One task per designer (if applicable): "Design UI/UX for <feature>"
   - One task per developer: "Implement <feature area>"
   - One task per tester: "Write tests for <feature>"

5. **Spawn the Product Owner** using the Task tool (`subagent_type: general-purpose`):
   - Provide the full task description from `$ARGUMENTS` and the team name
   - Their job:
     - Write detailed requirements and acceptance criteria for the feature
     - Check for a project lore file (`LORE.md`, `docs/lore.md`, `.agent/lore.md`, or similar) and update it with any relevant context about the project decisions or domain knowledge this feature introduces
     - Mark their task as completed via `TaskUpdate`
     - Message the team lead when done

6. **Wait for the Product Owner** to finish before continuing.

7. **If the task involves any UI**, spawn 1–2 Designers (`subagent_type: general-purpose`) in parallel:
   - Provide the team name and the PO's requirements
   - Their job:
     - Design the UI/UX: component structure, layout, interactions, and any visual decisions
     - Document design decisions in a design note or inline comments
     - Mark their task as completed via `TaskUpdate`
     - Message the team lead when done
   - Wait for all designers to finish before starting development.

8. **Spawn 1–3 Developers** (`subagent_type: general-purpose`) based on complexity:
   - Provide the team name, PO requirements, and design notes (if any)
   - If multiple developers are spawned, divide the work clearly (e.g. by layer: frontend/backend, or by feature area)
   - Their job:
     - Implement the functionality according to requirements and designs
     - Mark their task as completed via `TaskUpdate`
     - Message the team lead when done
   - Wait for all developers to finish before starting testing.

9. **Spawn 1–2 Testers** (`subagent_type: general-purpose`):
   - Provide the team name, PO requirements, and a summary of what was implemented
   - Their job:
     - Test the implemented functionality manually and/or via automated tests
     - Write or update e2e tests and/or unit tests to cover the new behaviour
     - Report any bugs or regressions found to the team lead
     - Mark their task as completed via `TaskUpdate`
     - Message the team lead when done

10. **Collect results** and present a final summary to the user covering:
    - What was implemented
    - Design decisions made (if any)
    - Tests added or updated
    - Any issues, bugs, or recommended follow-ups

11. **Shut down the team** gracefully:
    - Send a `shutdown_request` to each teammate via `SendMessage`
    - Once all have confirmed, call `TeamDelete`
