---
name: screenshots
version: 1.2.0
description: Take screenshots of components affected by recent changes, from the running app or Storybook. Supports custom instructions for pages to visit and actions to perform.
argument-hint: "[custom instructions]"
---

Take screenshots of components affected by recent changes, either from the running application (with e2e authentication) or from Storybook.

**Usage:**
- `/screenshots` - Detect changed components and take screenshots automatically
- `/screenshots navigate to /settings, open the "Profile" tab, screenshot the form` - Follow custom instructions to take screenshots

**Instructions:**

1. **Check for custom instructions:**
   - If `$ARGUMENTS` is provided and non-empty, run step 2 (prerequisites), then jump to **step 6 (Custom instructions mode)**
   - If `$ARGUMENTS` is empty, continue with the automatic detection flow below (steps 2–5, then 7–10)

2. **Check prerequisites:**
   - Run `npx playwright --version` to verify Playwright is available
   - If the command fails (not found or errors), display the following message and **STOP**:
     ```
     ## Missing Prerequisite: Playwright

     Playwright is not installed. This skill requires Playwright for taking screenshots.

     Install it with: npm install -D playwright
     ```

3. **Determine the base branch:**
   - Check if a `.agent` file exists in the current directory. If it contains a `baseBranch=<value>` line, use that value as the base branch
   - If no `.agent` file or no `baseBranch` key, default to `main`

4. **Identify changed components:**
   - Run `git diff --name-only $(git merge-base HEAD <base-branch>)..HEAD` to find recently changed files compared to the base branch
   - Filter for component files: `.tsx`, `.jsx`, `.vue`, `.svelte` extensions
   - Exclude test files (`*.test.*`, `*.spec.*`), story files (`*.stories.*`), and type definition files (`*.d.ts`)
   - If no component files are found in the changes, inform the developer and **STOP**
   - Present the list of changed components to the developer

5. **Ask the developer: App or Storybook?**
   - Use `AskUserQuestion` to ask for each component (or batch if many):
     - **Storybook** — component has stories, screenshot from Storybook
     - **App** — component is visible in the running application
     - **Skip** — don't screenshot this component

6. **Custom instructions mode (when `$ARGUMENTS` is provided):**

   This mode gives the developer full control over what to screenshot. The developer's instructions in `$ARGUMENTS` describe which pages to visit, which actions to perform (click buttons, fill forms, open menus, etc.), and when to take screenshots.

   a. **Authenticate if needed:**
      - Look for the project's e2e authentication setup (e.g., search for `auth.setup.ts`, `global-setup.ts`, or similar Playwright auth files)
      - Use Playwright MCP browser tools to navigate to the app, fill in credentials, and authenticate
      - If no auth setup is found, ask the developer if authentication is needed and how to proceed

   b. **Follow the developer's instructions:**
      - Parse and execute the instructions from `$ARGUMENTS` step by step
      - Use Playwright MCP browser tools to:
        - Navigate to the specified pages/routes
        - Perform any requested actions (click elements, fill inputs, select options, hover, scroll, wait, etc.)
        - Take a screenshot with `browser_take_screenshot` whenever the instructions indicate (explicitly or implicitly after completing an action sequence)
      - Save all screenshots to the `.tmp/` directory (`mkdir -p .tmp` first)
      - Use descriptive filenames based on the page/action context (e.g., `.tmp/settings-profile-tab.png`, `.tmp/dashboard-after-filter.png`)

   c. **View results:**
      - Use the `Read` tool to view each generated screenshot and present them to the developer

   d. **Summary:**
      - After all screenshots are taken, present a summary listing saved files and what each one shows
      - Then **STOP** (do not continue to the automatic detection steps)

7. **For components using the Storybook path:**

   a. **Find the corresponding story file:**
      - Look for a `.stories.tsx`, `.stories.jsx`, `.stories.ts`, or `.stories.js` file next to the component or in the same directory
      - If no story file is found, inform the developer and skip this component

   b. **Extract story metadata:**
      - Read the story file
      - Extract the `meta.title` (or `default.title`) from the default export
      - Extract all named exports (these are the story names), excluding the default export and any non-story exports (like `args`, `argTypes`, etc.)

   c. **Construct story URLs:**
      - Convert the title to kebab-case: replace spaces, `/`, and special characters with `-`, lowercase everything
      - Convert each story name to kebab-case
      - Build the story ID: `<title-kebab-case>--<story-name-kebab-case>`
      - Build the iframe URL: `http://localhost:6006/iframe.html?id=<story-id>&viewMode=story`

   d. **Verify Storybook is running:**
      - Try to reach `http://localhost:6006` (e.g., `curl -s -o /dev/null -w "%{http_code}" http://localhost:6006`)
      - If Storybook is not running (connection refused or non-200 response), ask the developer to start it and wait for confirmation

   e. **Take screenshots:**
      - Create the `.tmp/` directory if it doesn't exist: `mkdir -p .tmp`
      - For each story, run:
        ```
        npx playwright screenshot --browser chromium --wait-for-timeout 2000 "<iframe-URL>" .tmp/<component-name>-<story-name>.png
        ```
      - Run screenshots in parallel when there are multiple stories (use `&` and `wait` in Bash)
      - Inform the developer that `--wait-for-timeout 2000` is the default; they can ask to increase it for heavier components

   f. **View results:**
      - Use the `Read` tool to view each generated screenshot and present them to the developer

8. **For components using the App path:**

   a. **Ask the developer which URL/route to navigate to:**
      - Use `AskUserQuestion` to get the URL or route where the component is visible in the running app

   b. **Authenticate if needed:**
      - Look for the project's e2e authentication setup (e.g., search for `auth.setup.ts`, `global-setup.ts`, or similar Playwright auth files)
      - Use Playwright MCP browser tools to navigate to the app, fill in credentials, and authenticate
      - If no auth setup is found, ask the developer if authentication is needed and how to proceed

   c. **Take the screenshot:**
      - Use Playwright MCP browser tools for the app path: navigate to the URL, wait for the page to load, and take a screenshot
      - Save screenshots to the `.tmp/` directory
      - Use the `Read` tool to view each generated screenshot and present them to the developer

9. **Summary:**
   - After all screenshots are taken, present a summary:
     ```
     ## Screenshots Complete

     Saved to `.tmp/`:
     - .tmp/ComponentA-Default.png (Storybook)
     - .tmp/ComponentA-WithProps.png (Storybook)
     - .tmp/ComponentB-app.png (App - /dashboard)

     Screenshots are stored in the .tmp/ directory of your project.
     ```

10. **Handle edge cases:**
   - If a screenshot command fails, show the error and continue with the remaining screenshots
   - If the `.tmp/` directory cannot be created, show the error and **STOP**
   - If a story file has no named exports (no stories), skip it and inform the developer
   - If the developer skips all components, inform them and **STOP**
