---
name: workie
description: Manage git worktree workflows for Phoenix/Elixir applications. Supports three commands — `/workie bootstrap` sets up branch-isolated databases, env files, and hooks; `/workie begin <branch>` creates a new worktree with its own database; `/workie finish [branch]` tears down a worktree and cleans up databases. Use when the user mentions "workie", "worktree", "branch database", "isolated dev environment", "parallel branch development", or wants to create/remove feature worktrees.
---

# Workie — Git Worktree Lifecycle Manager for Phoenix/Elixir

Manage the full lifecycle of branch-isolated worktrees: bootstrap the workflow, begin work on a new branch, and finish by tearing down the worktree and its databases.

## Shared Concepts

- **`.branch` file**: Written into each worktree root. Contains a sanitized branch identifier (conventional prefix stripped, alphanumeric + underscore, max 24 chars). Config files read this to select the correct database.
- **Branch-aware DB naming**: Each worktree gets its own `APP_NAME_<branch_id>_dev` and `APP_NAME_<branch_id>_test` databases. The main worktree (no `.branch` file) uses default names.
- **Workie CLI**: The [workie](https://github.com/agoodway/workie) CLI automates worktree creation/removal and runs hooks defined in `.workie.yaml`. When the CLI is not installed, the skill falls back to manual `git worktree` commands + hook steps.
- **Prerequisites**: Phoenix app with Ecto + PostgreSQL, Git, PostgreSQL running locally. Workie CLI recommended but not required.

---

## Commands

### `/workie bootstrap`

Set up the workie workflow in a Phoenix project so that every future worktree gets its own directory and isolated database.

#### What This Creates

- Environment secret files (format depends on detected strategy)
- `.workie.yaml` — Workie configuration with hooks
- `scripts/setup_branch_db.sh` — Creates branch-specific dev + test databases, runs migrations and seeds
- `scripts/cleanup_branch_db.sh` — Drops branch databases on worktree removal
- Branch-aware database naming in config
- `.gitignore` entries for env files and `.branch`

#### Workflow

1. **Detect environment loading strategy** — Inspect `mix.exs`, `config/runtime.exs`, `config/config.exs`, and the root directory to determine which strategy the project uses. See `references/bootstrap-strategies.md` for full detection logic and implementation for each strategy:
   - **Strategy A: Dotenvy** — `.env` files loaded via `Dotenvy.source!/2` in `runtime.exs`. Preferred for new setups.
   - **Strategy B: Elixir Script Import** — `.env.dev.exs` / `.env.test.exs` files with `System.put_env` calls, imported via `import_config`.
   - **Strategy C: Plain System.get_env** — Secrets managed externally (shell, direnv). Only needs `.branch` + database scripts.

2. **Implement the detected strategy** — Follow the steps in `references/bootstrap-strategies.md` for the detected strategy (env files, config changes, branch-aware DB naming).

3. **Create shared scripts and config** — Database setup/cleanup scripts, `.workie.yaml`, and gitignore entries. See `references/shared-scripts.md` for all templates.

4. **Replace placeholders** — Substitute all placeholder values in the generated files:

| Placeholder | Replace With | Example |
|---|---|---|
| `APP_NAME` | Your app's database prefix (snake_case) | `my_app` |
| `app_name` | Your OTP app name (atom) | `my_app` |
| `AppName` | Your app module name | `MyApp` |
| `GITHUB_OWNER` | GitHub org or username | `myorg` |
| `GITHUB_REPO` | GitHub repository name | `my_app` |

---

### `/workie begin <branch-name>`

Create a new worktree for a feature branch with its own isolated database.

#### Workflow

1. **Pre-flight checks**
   - Verify this is a git repository
   - Check that `.workie.yaml` exists in the project root. If missing, offer to run `/workie bootstrap` first.
   - Check PostgreSQL is available: `pg_isready`

2. **Determine branch name**
   - Use the provided `<branch-name>` argument
   - If none provided, ask the user for a branch name

3. **Create worktree** (Workie CLI path)
   - Run `workie begin <branch-name>`
   - The CLI handles: creating the git worktree, copying `files_to_copy`, writing `.branch`, running `post_create` hooks (`mix deps.get`, `mix compile`, `setup_branch_db.sh`)

4. **Manual fallback** (if workie CLI is not installed)
   - `git worktree add ../<project>-<branch-name> -b <branch-name>` (or use existing branch with `-B`)
   - Copy files listed in `.workie.yaml` `files_to_copy` into the new worktree
   - `cd` into the new worktree directory
   - Generate `.branch` file: `branch_name=$(git branch --show-current); branch_name=${branch_name#*/}; echo "${branch_name//[^a-zA-Z0-9]/_}" | cut -c1-24 > .branch`
   - Run `mix deps.get && mix compile`
   - Run `./scripts/setup_branch_db.sh`

5. **Verify**
   - Confirm worktree appears in `git worktree list`
   - Confirm databases were created (check `psql -l` output for the branch DB names)
   - Report to user: worktree path, dev DB name, test DB name

---

### `/workie finish [branch-name]`

Tear down a worktree and clean up its databases.

#### Workflow

1. **Determine target branch**
   - Use the provided `[branch-name]` argument if given
   - Otherwise, detect from `.branch` file in the current directory
   - If neither available, list worktrees with `git worktree list` and ask the user which one to remove

2. **Safety checks**
   - Check for uncommitted changes in the target worktree: `git -C <worktree-path> status --porcelain`
   - If changes exist, warn the user and offer options: commit, stash, or discard
   - Check for unpushed commits: `git -C <worktree-path> log @{u}.. --oneline 2>/dev/null`
   - If unpushed commits exist, warn the user

3. **Optional PR check**
   - Check if a PR already exists for this branch: `gh pr list --head <branch-name> --state open`
   - If no PR exists, offer to create one before finishing

4. **Clean up** (Workie CLI path)
   - Run `workie finish <branch-name>`
   - The CLI handles: running `pre_remove` hook (`cleanup_branch_db.sh`), removing the git worktree

5. **Manual fallback** (if workie CLI is not installed)
   - `cd` to the worktree directory and run `./scripts/cleanup_branch_db.sh`
   - `cd` back to the main worktree
   - `git worktree remove <worktree-path>` (use `--force` only if user confirmed discarding changes)
   - Optionally delete the branch: `git branch -d <branch-name>` (or `-D` if unmerged and user confirms)

6. **Verify**
   - Confirm worktree no longer appears in `git worktree list`
   - Confirm databases were dropped (check `psql -l`)
   - Report cleanup summary to user

---

## Rules

- Run each `git`, `workie`, `mix`, `psql`, `createdb`, `dropdb`, `pg_isready`, and `gh` command as its own separate Bash call. Do not combine commands into multi-line scripts.
- Always check for the workie CLI first (`which workie`). Use CLI path when available, manual fallback otherwise.
- Never force-remove a worktree without user confirmation if there are uncommitted changes.
- When running bootstrap, detect the existing strategy before making any changes — do not blindly install Dotenvy if the project already uses a different approach.

$ARGUMENTS
