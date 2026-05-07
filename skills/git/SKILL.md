---
name: git
description: Git workflow commands for committing changes and managing pull requests. Use when the user says '/git commit', '/git commit-all', '/git pr', '/git pr-update', '/git pr-pull-review', or '/git help'. Supports atomic commits, conventional commit format, and PR creation/updates without AI attribution.
---

# Git Workflow Skill

This skill is runtime-neutral and works in Claude Code, OpenCode, and Codex. Use the current runtime's shell, read, edit/write, search, and question tools. Do not add any AI attribution footer for any runtime.

## Runtime Notes

- **Claude Code**: use `AskUserQuestion` for choices when available.
- **OpenCode**: use the question tool for choices when available.
- **Codex**: ask the user directly when interactive input is required.
- If an interactive git command would be required, avoid it and use non-interactive alternatives. Do not use `git add -p` unless the runtime can safely drive the interaction; otherwise stage explicit files or ask the user which files to include.

## Atomic Commits

Before committing, review all changes and organize into logical units:

- **Group related changes** - Same feature, bug fix, or refactor belongs together
- **Separate unrelated changes** - Different fixes or features get separate commits
- **Single responsibility** - Each commit should be independently revertible
- **Don't mix concerns** - Keep formatting separate from logic changes

When changes span multiple concerns, stage specific files to create separate commits. Use partial staging only when the runtime supports it safely; otherwise ask the user how to split the changes.

## Commands

### `/git` (no subcommand)

When invoked without a subcommand, default to the commit workflow below.

### `/git help`

Display a list of all available subcommands. Output the following exactly:

```
/git subcommands:

  commit [message]   — Commit staged/unstaged changes with conventional format
  commit-all         — Commit all changes as logical atomic commits, skipping junk files
  pr [context]       — Create a draft pull request for the current branch
  pr-update          — Push and update an existing PR description
  pr-pull-review     — Fetch PR review comments and address them
  help               — Show this help message
```

### `/git commit [message]`

Commit changes without AI attribution.

1. Run `git status` to see what needs to be committed (including untracked files)
2. Run `git diff` to review the changes
3. Analyze changes for logical grouping - create multiple commits if changes are unrelated
4. Stage related changes together:
   - For specific files: `git add <file1> <file2>`
   - For partial staging: use a runtime-supported non-interactive patch workflow, or ask the user how to split the changes
   - Include any new/untracked files shown in git status
5. Create commit with conventional format: `type: description`
6. **DO NOT include AI attribution footer**
7. If user provided a message in $ARGUMENTS, use it as context for the commit
8. After committing, ask user about pushing using the runtime's question mechanism
9. If they push and aren't on main branch, ask if they want to open a PR
10. If yes, use `gh pr create --draft` with appropriate title and description

### `/git commit-all`

Commit all working tree changes as logical, atomic commits — but skip files that look unneeded.

1. Run `git status` to see all staged, unstaged, and untracked changes
2. **Filter out junk files** — do NOT stage or commit any of the following:
   - OS artifacts: `.DS_Store`, `Thumbs.db`, `Desktop.ini`, `._*`
   - Editor/IDE files: `.idea/`, `.vscode/settings.json`, `*.swp`, `*.swo`, `*~`
   - Build artifacts: `_build/`, `deps/`, `node_modules/`, `dist/`, `*.beam`
   - Temp/debug files: `*.log`, `*.tmp`, `*.bak`, `*.orig`, `dump.rdb`
   - Secrets: `.env`, `.env.*` (except `.env.sample`, `.env.example`), `credentials.*`
   - Any file already covered by `.gitignore` patterns
   - If unsure whether a file is needed, ask the user with the runtime's question mechanism
3. Run `git diff` and `git diff --cached` to review all changes
4. **Group changes into logical commits** following the atomic commit rules:
   - Analyze every changed file and determine which concern it belongs to
   - Group by feature, fix, refactor, or area — each group becomes one commit
   - Separate formatting/style changes from logic changes
   - Migrations, schema changes, and their corresponding code go together
   - Test files go with the code they test
5. For each logical group (in dependency order — e.g., migrations before code that uses them):
   - Stage only the files for that group: `git add <file1> <file2> ...`
   - Commit with conventional format: `type: description`
    - **DO NOT include AI attribution footer**
6. After all commits, show a summary of what was committed (commit count, files, short log)
7. Ask user about pushing using the runtime's question mechanism
8. If they push and aren't on main branch, ask if they want to open a PR

### `/git pr [context]`

Create a pull request for the current branch.

1. Check `git status` for uncommitted changes
2. If uncommitted changes exist:
   - Run `git diff` to review
   - Follow atomic commit rules - create multiple commits if needed
   - Stage and commit with conventional format
    - **DO NOT include AI attribution**
3. Verify current branch and recent commits with `git log`
4. Push any unpushed commits to remote
5. Determine base branch (check `git remote show origin` for default, fallback to 'main')
6. Create PR using `gh pr create --draft` with:
   - Clear title in conventional commit format
   - Detailed body including:
     - Summary section with bullet points
     - Detailed changes organized by area
     - Test plan with checklist items
     - Breaking changes or migration notes if applicable
    - **DO NOT include AI attribution or generated-by footer**
7. If user provided context in $ARGUMENTS, use it for PR title/description
8. Return the PR URL to the user

### `/git pr-update`

Push current branch and update PR description.

1. Verify we're in a git repository and get current branch name
2. Check for uncommitted changes - alert user if any exist
3. Push current branch to origin (use `-u` flag if branch doesn't exist on remote)
4. Check if PR exists using `gh pr view`
5. If PR exists:
   - Get current PR number and details
   - Analyze commits since PR creation with `git log`
   - Generate updated description with:
     - Summary of all changes
     - List of commits included
     - Test plan updates if relevant
   - Update PR using `gh pr edit`
6. If no PR exists:
   - Ask user if they want to create one
   - If yes, analyze all commits since diverging from main/master
   - Create comprehensive PR with `gh pr create --draft`
7. Show PR URL and summary of what was updated

### `/git pr-pull-review`

Pull PR review comments and address them.

1. Get the current branch name and find the associated PR:
   - Run `gh pr view --json number,url,title` to get PR details
   - If no PR exists, tell the user and stop
2. Fetch all review comments:
   - Run `gh pr view --json reviews,comments` to get top-level PR comments
   - Run `gh api repos/{owner}/{repo}/pulls/{number}/comments` to get inline review comments (these are file-specific)
   - Filter to only **unresolved** and **actionable** comments — skip:
     - Already-resolved comment threads
     - Pure approvals or "LGTM" comments
     - Bot comments (CI, linters, etc.)
3. Present a numbered summary of each review comment to the user:
   - For inline comments: show file, line, and the comment body
   - For general comments: show the comment body
   - Ask the user which comments to address (all, specific numbers, or skip any) using the runtime's question mechanism
4. For each comment the user wants addressed:
   - Read the referenced file to understand the context
   - Implement the requested change
   - If a comment is ambiguous or you disagree with the suggestion, ask the user with the runtime's question mechanism before making the change
5. After all changes are made:
   - Follow atomic commit rules — group related review fixes together
   - Commit with format: `fix: address PR review — <brief summary>`
    - **DO NOT include AI attribution footer**
6. Reply to each addressed comment on the PR:
   - Run `gh api repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies -f body="Addressed in <commit-sha>"`
   - For top-level comments, use `gh pr comment --body "Addressed: <summary of what was fixed>"`
7. Push the changes and show a summary of what was addressed

## Commit Message Format

```
type: concise description

Optional body for context
```

**Types:** `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `style`

## Error Handling

If any errors occur:
- Clearly explain what went wrong
- Suggest fixes or alternatives
- Ask if user wants to retry or handle manually

$ARGUMENTS
