---
name: merge-base-branch
version: 1.1.0
description: Merge the branch the current branch was branched out from into the current branch. Determines the base branch automatically and asks for confirmation before merging.
argument-hint: ""
---

Merge the base branch (the branch this branch was created from) into the current branch. Useful for keeping a feature branch up to date with its parent.

**Usage:**
- `/merge-base-branch` - Detect the base branch and merge it into the current branch

**Instructions:**

1. **Determine the current branch:**
   - Run `git branch --show-current` to get the current branch name
   - If in detached HEAD state (no branch name), inform the user and **STOP**

2. **Determine the base branch:**
   - **First**, check if a `.agent` file exists in the repository root. If it does, read it and look for a `baseBranch=<value>` line. Use that value as the base branch.
   - **If no `.agent` file or no `baseBranch` entry**, use `git log --oneline --merges` and `git reflog` heuristics:
     - Run `git merge-base --fork-point main HEAD` to check if the branch forked from `main`
     - Run `git merge-base --fork-point master HEAD` to check if the branch forked from `master`
     - Run `git merge-base --fork-point develop HEAD` to check if the branch forked from `develop`
     - Use the branch that returns a valid merge-base commit. If multiple match, prefer in order: `main`, `master`, `develop`.
   - **If none of the above works**, ask the user to provide the base branch name using `AskUserQuestion` with common options (`main`, `master`, `develop`) and **STOP** waiting for their answer.

3. **Verify the base branch exists:**
   - Run `git rev-parse --verify origin/<base-branch>` to confirm the remote base branch exists
   - If it does not exist, try `git rev-parse --verify <base-branch>` for a local-only branch
   - If neither exists, inform the user that the base branch `<base-branch>` was not found and **STOP**

4. **Fetch the latest from origin:**
   - Run `git fetch origin <base-branch>` to get the latest commits
   - If the fetch fails, show the error and **STOP**

5. **Show merge preview and ask for confirmation:**
   - Run `git log --oneline HEAD..origin/<base-branch>` to list the commits that will be merged in
   - Count the number of incoming commits
   - If there are **no new commits**, inform the user that the current branch is already up to date with `<base-branch>` and **STOP**
   - Display a summary:
     ```
     ## Merge Preview

     Base branch: <base-branch>
     Current branch: <current-branch>
     Incoming commits: <count>

     <list of commits from git log --oneline>
     ```
   - Use `AskUserQuestion` to ask: "Proceed with merging origin/<base-branch> into <current-branch>?"
     - Option 1: "Yes, merge" (description: "Merge the commits listed above into the current branch")
     - Option 2: "No, cancel" (description: "Cancel the merge operation")
   - If the user selects "No, cancel", display "Merge cancelled." and **STOP**

6. **Perform the merge:**
   - Run `git merge origin/<base-branch> --no-edit`
   - If the merge succeeds, display:
     ```
     ## Merge Complete

     Successfully merged origin/<base-branch> into <current-branch>.
     <count> commits merged.
     ```
   - If the merge fails due to **conflicts**:
     - Run `git diff --name-only --diff-filter=U` to list conflicting files
     - Display the list of conflicting files
     - **Resolve each conflict yourself:**
       - Read each conflicting file
       - Analyze the conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) and understand the intent of both sides
       - Choose the correct resolution: keep both changes merged together when they don't contradict, prefer the base branch for upstream fixes, and preserve the current branch's feature work
       - Edit the file to remove all conflict markers and produce the correct merged content
       - After resolving, run `git add <file>` for each resolved file
     - Once all conflicts are resolved, run `git merge --continue --no-edit`
     - Display:
       ```
       ## Merge Complete (conflicts resolved)

       Successfully merged origin/<base-branch> into <current-branch>.
       <count> commits merged.
       Resolved conflicts in:
       - <file1>
       - <file2>
       ...
       ```
     - Ask the user to **review the conflict resolutions** before proceeding further
