# Project Rules

## Skills

- Skills are stored in `skills/<skill-name>/SKILL.md` in this repository.
- Each skill has a `version` field in its YAML frontmatter using semantic versioning (e.g., `version: 1.0.0`).
- **When modifying a skill, always increment its version:**
  - **Patch** (`x.y.Z`): Minor fixes, wording changes, small tweaks to instructions.
  - **Minor** (`x.Y.0`): New steps, new capabilities, or meaningful behavior changes.
  - **Major** (`X.0.0`): Breaking changes to the skill's interface, arguments, or fundamental workflow.
- When creating, modifying, or deleting a skill, **always** update `claude-skills.html` to reflect the change (including the version badge). The HTML page documents all available skills with their descriptions, usage instructions, and raw file content.
- Follow the existing skill card structure in `claude-skills.html` (skill-card div with header, version badge, description, usage, collapsible raw content).
