---
name: goodverify
description: "Verify emails, phones, and addresses using the GoodVerify CLI. Dispatches subcommands via `/goodverify [subcommand]`. Use when the user says '/goodverify', 'verify email', 'verify phone', 'verify address', 'batch verification', 'check email deliverability', or wants to install, configure, or use the goodverify CLI."
---

# GoodVerify

CLI client for [goodverify.dev](https://goodverify.dev) — verify emails, phones, and addresses from the command line. Single static binary (~1MB), zero dependencies.

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `install` | Install the goodverify CLI |
| `configure` | Set up API key and environment |
| `verify` | Verify an email, phone, or address |
| `batch` | Manage batch verification jobs |
| `usage` | Show API usage and credit balance |
| `health` | Check API health status |

### `/goodverify help`

Display a list of all available subcommands. Output the following exactly:

```
/goodverify subcommands:

  install                — Install the goodverify CLI
  configure              — Set up API key and environment
  verify <type>          — Verify an email, phone, or address
  batch <action>         — Manage batch verification jobs
  usage                  — Show API usage and credit balance
  health                 — Check API health status
  help                   — Show this help message
```

If `/goodverify` is invoked without a subcommand, show the help output above.

## Dispatch

1. Parse the subcommand and args from the user's invocation. Examples:
   - `/goodverify install` → subcommand `install`
   - `/goodverify configure` → subcommand `configure`
   - `/goodverify verify email user@example.com` → subcommand `verify`, type `email`
   - `/goodverify batch list` → subcommand `batch`, action `list`
   - `/goodverify usage` → subcommand `usage`
   - `/goodverify health` → subcommand `health`
   - `/goodverify help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Before running any subcommand except `install` and `help`, check if `goodverify` is installed (`which goodverify`). If not, tell the user to run `/goodverify install` first and stop.
4. Follow the matching workflow below.

---

## `/goodverify install`

Install the goodverify CLI binary.

1. Check if `goodverify` is already installed: `which goodverify`
2. If already installed, show the current version (`goodverify --version`) and ask if the user wants to reinstall.
3. Detect the platform:
   - **macOS / Linux**: install via curl:
     ```sh
     curl -fsSL https://raw.githubusercontent.com/agoodway/goodverify_cli/main/install.sh | sh
     ```
   - **Windows**: tell the user to run in PowerShell:
     ```powershell
     irm https://raw.githubusercontent.com/agoodway/goodverify_cli/main/install.ps1 | iex
     ```
4. Verify installation: `goodverify --version`
5. Suggest running `/goodverify configure` to set up an API key.

---

## `/goodverify configure`

Set up or manage API key and environment configuration.

Config is stored at `~/.goodverify.json` (Windows: `%USERPROFILE%\.goodverify.json`).

### Workflow

1. **If the user provided flags**, pass them through directly:
   ```sh
   goodverify configure --env <name> --url <url> --key <key>
   ```

2. **If no flags provided**, guide the user interactively:
   - Ask for the environment name (e.g., `production`, `dev`, `staging`). Default: `production`.
   - Ask for the API key. Keys starting with `sk_` are read-write (required for batch operations). Keys starting with `pk_` are read-only (sufficient for single verifications).
   - Ask for the base URL. Default: `https://goodverify.dev`. For local development: `http://localhost:4000`.
   - Run: `goodverify configure --env <name> --url <url> --key <key>`

3. **Show current config**: `goodverify configure --show` (keys are masked).

### Notes

- The first configured environment becomes the default.
- Re-running with the same `--env` updates existing values.
- Use `--env <name>` on any command to switch environments.

---

## `/goodverify verify`

Verify an email, phone number, or mailing address.

### Email

```sh
goodverify verify email --email <address>
```

Parse the email from the user's message. Examples:
- `/goodverify verify email user@example.com` → `goodverify verify email --email user@example.com`
- `/goodverify verify email --email user@example.com --json` → pass through

### Phone

```sh
goodverify verify phone --phone <number> [--country <code>]
```

Parse the phone number from the user's message. If the number doesn't include a country code prefix, ask for the country code or default to `US`.

Examples:
- `/goodverify verify phone +15551234567` → `goodverify verify phone --phone "+15551234567"`
- `/goodverify verify phone 5551234567` → `goodverify verify phone --phone "5551234567" --country US`

### Address

```sh
# Single string
goodverify verify address --address "<full address>"

# Structured fields
goodverify verify address --street "<street>" --city <city> --state <state> --zip <zip>
```

Parse the address from the user's message. If the user provides a single string, use `--address`. If they provide structured fields, use the individual flags.

Examples:
- `/goodverify verify address 123 Main St, Springfield, IL 62701` → `goodverify verify address --address "123 Main St, Springfield, IL 62701"`

### Output

- By default, results are pretty-printed. Add `--json` for raw JSON output.
- After showing results, briefly summarize the key findings (deliverable/undeliverable, valid/invalid, standardized address, etc.).

---

## `/goodverify batch`

Manage batch verification jobs.

### Actions

| Action | Command |
|--------|---------|
| `create` | Create a batch job from JSON or CSV |
| `list` | List all batch jobs |
| `get` | Get details of a specific job |
| `results` | Download results of a completed job |
| `sample` | Download sample CSV template |

### Create

```sh
# From a JSON file
goodverify batch create --file <request.json>

# From a CSV file
goodverify batch create --csv <data.csv>

# From inline JSON
goodverify batch create --json-body '<json>'
```

If the user wants to create a batch but doesn't have a file ready:
1. Run `goodverify batch sample > template.csv` to get the CSV template.
2. Tell the user to fill in the template.
3. Then run `goodverify batch create --csv template.csv`.

### List

```sh
goodverify batch list
goodverify batch list --json
```

### Get / Results

```sh
goodverify batch get --id <batch_id>
goodverify batch results --id <batch_id>
```

If the user doesn't provide a batch ID, run `goodverify batch list` first to show available jobs, then ask which one.

---

## `/goodverify usage`

Show API usage and credit balance.

```sh
goodverify usage
goodverify usage --json
```

Summarize the output: plan name, credits remaining, usage stats.

---

## `/goodverify health`

Check API health status. Does not require authentication.

```sh
goodverify health
goodverify health --url <url>
```

If the health check fails, suggest:
- Check the URL is correct
- Check network connectivity
- For local dev: ensure the server is running

---

## Global Options

All commands support these options:

| Flag | Description |
|------|-------------|
| `--env <name>` | Use a specific configured environment |
| `--key <key>` | Override API key for this request |
| `--url <url>` | Override base URL for this request |
| `--json` | Output raw JSON response |

---

## API Key Types

- `sk_*` keys are **read-write** — required for batch operations
- `pk_*` keys are **read-only** — sufficient for single verifications

Get your API key at [goodverify.dev](https://goodverify.dev).

$ARGUMENTS
