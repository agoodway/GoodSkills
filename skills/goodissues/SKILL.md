---
name: goodissues
description: "Manage projects and track issues using the GoodIssues CLI. Dispatches subcommands via `/goodissues [subcommand]`. Use when the user says '/goodissues', 'create issue', 'file a bug', 'list issues', 'create project', 'track issues', 'bug report', 'feature request', or wants to install, configure, or use the goodissues CLI."
---

# GoodIssues

CLI client for [goodissues.dev](https://goodissues.dev) — manage projects and track bugs, incidents, and feature requests from the command line. Single static binary (~1MB), zero dependencies.

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `install` | Install the goodissues CLI |
| `configure` | Set up API key and environment |
| `projects` | List, create, get, or delete projects |
| `issues` | List, create, get, or delete issues |

### `/goodissues help`

Display a list of all available subcommands. Output the following exactly:

```
/goodissues subcommands:

  install                — Install the goodissues CLI
  configure              — Set up API key and environment
  projects <action>      — Manage projects
  issues <action>        — Manage issues (bugs, incidents, feature requests)
  help                   — Show this help message
```

If `/goodissues` is invoked without a subcommand, show the help output above.

## Dispatch

1. Parse the subcommand and args from the user's invocation. Examples:
   - `/goodissues install` → subcommand `install`
   - `/goodissues configure` → subcommand `configure`
   - `/goodissues projects list` → subcommand `projects`, action `list`
   - `/goodissues issues create ...` → subcommand `issues`, action `create`
   - `/goodissues help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Before running any subcommand except `install` and `help`, check if `goodissues` is installed (`which goodissues`). If not, tell the user to run `/goodissues install` first and stop.
4. Follow the matching workflow below.

---

## `/goodissues install`

Install the goodissues CLI binary.

1. Check if `goodissues` is already installed: `which goodissues`
2. If already installed, show the current version (`goodissues --version`) and ask if the user wants to reinstall.
3. Detect the platform:
   - **macOS / Linux**:
     ```sh
     curl -fsSL https://raw.githubusercontent.com/agoodway/goodissues_cli/main/install.sh | sh
     ```
   - **Windows**: tell the user to run in PowerShell:
     ```powershell
     irm https://raw.githubusercontent.com/agoodway/goodissues_cli/main/install.ps1 | iex
     ```
4. Verify installation: `goodissues --version`
5. Suggest running `/goodissues configure` to set up an API key.

---

## `/goodissues configure`

Set up or manage API key and environment configuration.

Config is stored at `~/.goodissues.json` (Windows: `%USERPROFILE%\.goodissues.json`).

### Workflow

1. **If the user provided flags**, pass them through directly:
   ```sh
   goodissues configure --env <name> --url <url> --api-key <key>
   ```

2. **If no flags provided**, guide the user interactively:
   - Ask for the base URL. Default: `https://goodissues.dev`. For local development: `http://localhost:4000`.
   - Ask for the API key. Keys starting with `sk_` are read-write (required for create/delete). Keys starting with `pk_` are read-only.
   - Optionally ask for an environment name (e.g., `production`, `dev`, `staging`).
   - Run: `goodissues configure --url <url> --api-key <key>` (add `--env <name>` if specified)

3. **Show current config**: `goodissues configure show` (keys are masked).

4. **Show specific environment**: `goodissues configure show --env <name>`.

### Notes

- The first configured environment becomes the default.
- Re-running with the same `--env` updates existing values.
- Use `--env <name>` on any command to switch environments.

---

## `/goodissues projects`

Manage projects within your account.

### Actions

| Action | Command |
|--------|---------|
| `list` | List all projects (default) |
| `get` | Get a single project by ID |
| `create` | Create a new project |
| `delete` | Delete a project |

### List

```sh
goodissues projects list
goodissues projects list --json
```

If no action is specified, default to `list`.

### Get

```sh
goodissues projects get <project-id>
goodissues projects get <project-id> --json
```

Parse the project ID from the user's message. If not provided, run `goodissues projects list` first to show available projects, then ask which one.

### Create

```sh
goodissues projects create --name <name> [--description <desc>]
```

Parse the project name from the user's message. Examples:
- `/goodissues projects create My App` → `goodissues projects create --name "My App"`
- `/goodissues projects create --name "Backend API" --description "REST API service"` → pass through

### Delete

```sh
goodissues projects delete <project-id>
```

Always confirm with the user before deleting. Requires an `sk_*` key.

---

## `/goodissues issues`

Track bugs, incidents, and feature requests.

### Actions

| Action | Command |
|--------|---------|
| `list` | List issues (default) |
| `get` | Get a single issue by ID |
| `create` | Create a new issue |
| `delete` | Delete an issue |

### List

```sh
goodissues issues list
goodissues issues list --project <project-id>
goodissues issues list --status <status>
goodissues issues list --project <project-id> --status <status>
goodissues issues list --json
```

If no action is specified, default to `list`.

**Statuses:** `new`, `in_progress`, `archived`

### Get

```sh
goodissues issues get <issue-id>
goodissues issues get <issue-id> --json
```

### Create

```sh
goodissues issues create --project <project-id> --title <title> --type <type> [options]
```

**Required flags:**
- `--project <id>` — project to create the issue in
- `--title <title>` — issue title
- `--type <type>` — one of: `bug`, `incident`, `feature_request`

**Optional flags:**
- `--priority <priority>` — `low`, `medium` (default), `high`, `critical`
- `--description <desc>` — detailed description

When parsing the user's natural language:
- "file a bug" / "bug report" → `--type bug`
- "feature request" / "new feature" → `--type feature_request`
- "incident" / "outage" → `--type incident`
- If no project is specified, run `goodissues projects list` first to show available projects, then ask which one.

Examples:
- `/goodissues issues create Login broken on Safari in project abc123` → `goodissues issues create --project abc123 --title "Login broken on Safari" --type bug`
- `/goodissues issues create --project abc123 --title "Add dark mode" --type feature_request --priority medium` → pass through

### Delete

```sh
goodissues issues delete <issue-id>
```

Always confirm with the user before deleting. Requires an `sk_*` key.

---

## Global Options

All commands support these options:

| Flag | Description |
|------|-------------|
| `--env <name>` | Use a specific configured environment |
| `--json` | Output raw JSON response |

---

## API Key Types

- `sk_*` keys are **read-write** — required for create and delete operations
- `pk_*` keys are **read-only** — sufficient for listing and viewing

Get your API key at [goodissues.dev](https://goodissues.dev).

---

## Issue Reference

| Field | Values |
|-------|--------|
| Type | `bug`, `incident`, `feature_request` |
| Priority | `low`, `medium` (default), `high`, `critical` |
| Status | `new` (default), `in_progress`, `archived` |

Each issue belongs to a project and has a key (e.g., `PROJ-1`) with a sequential number.

$ARGUMENTS
