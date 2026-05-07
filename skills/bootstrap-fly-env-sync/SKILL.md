---
name: bootstrap-fly-env-sync
description: >
  Bootstrap a shell script that syncs environment variables from a .env file to Fly.io secrets
  in configurable batches. Creates the script at scripts/env-to-fly-secrets.sh, ensures .env.prod
  is gitignored, and optionally adds a justfile recipe. Use when the user says "bootstrap fly env",
  "add fly secrets sync", "env to fly", "sync env to fly", or wants to push .env vars to Fly.io.
---

# Bootstrap Fly.io Env Sync Script

Create a script that reads a `.env` file and converts it into batched `fly secrets set` commands.

## What Gets Created

1. **`scripts/env-to-fly-secrets.sh`** — The sync script (from template)
2. **`.env.prod`** — Created from `.env.sample` if it exists and `.env.prod` doesn't (user fills in real values)
3. **`.gitignore` update** — Ensures `.env.prod` is ignored
4. **Justfile recipe** (optional) — If a `justfile` exists, adds a `fly-secrets` recipe

## Features of the Script

- Parses `.env` files (skips comments, blank lines, handles `export` prefix)
- Validates keys match `[A-Za-z_][A-Za-z0-9_]*`
- Strips surrounding quotes from values
- Batches secrets into groups (default 10) to avoid Fly CLI limits
- **Dry-run by default** — prints commands without executing
- `--execute` flag to actually run `fly secrets set`
- Configurable app name (`-a`) and batch size (`-n`)

## Phase 0: Discovery

Check the target project before creating anything:

1. **Existing script** — `Glob("**/env-to-fly*")` or `Glob("**/fly-secrets*")`
   - If found: show it and ask if user wants to replace

2. **Scripts directory** — Check if `scripts/` exists
   - If not: will create it

3. **`.env.sample`** — Check if an env template exists
   - Could be `.env.sample`, `.env.example`, or `.env.template`
   - If found: offer to copy it to `.env.prod` as a starting point

4. **`.env.prod`** — Check if it already exists
   - If found: leave it alone

5. **`.gitignore`** — Check if `.env.prod` is already ignored
   - `Grep("\.env\.prod", path: ".gitignore")`

6. **`justfile`** — Check if a justfile exists for adding a recipe
   - `Glob("justfile")` or `Glob("Justfile")`

7. **`fly.toml`** — Check if Fly is configured to detect the app name
   - `Grep("^app = ", path: "fly.toml")`

### Discovery Report

Present what will be created/modified and confirm.

## Phase 1: Implementation

### Step 1: Create Scripts Directory

```bash
mkdir -p scripts
```

### Step 2: Create the Script

Read [references/script-template.sh](references/script-template.sh) and write it to `scripts/env-to-fly-secrets.sh`.

Make it executable:
```bash
chmod +x scripts/env-to-fly-secrets.sh
```

### Step 3: Create .env.prod (if needed)

If `.env.sample` (or equivalent) exists and `.env.prod` does not:
- Copy the sample file to `.env.prod`
- Tell the user to fill in production values

If no sample exists, skip this step.

### Step 4: Update .gitignore

Add `.env.prod` to `.gitignore` if not already present. Place it near other `.env*` entries if they exist, otherwise append to the end.

### Step 5: Justfile Recipe (if justfile exists)

Add a recipe like:

```makefile
# Sync .env.prod to Fly secrets (dry-run by default, pass --execute to apply)
fly-secrets *args:
    ./scripts/env-to-fly-secrets.sh -f .env.prod {{args}}
```

If the app name is known from `fly.toml`, include `-a <app-name>`:

```makefile
fly-secrets *args:
    ./scripts/env-to-fly-secrets.sh -f .env.prod -a <app-name> {{args}}
```

## Phase 2: Verification

1. Run `./scripts/env-to-fly-secrets.sh --help` to verify the script works
2. If `.env.prod` exists with content, do a dry-run: `./scripts/env-to-fly-secrets.sh -f .env.prod` to show what would be set

## Usage

Tell the user:

```bash
# Preview what will be set (dry-run)
./scripts/env-to-fly-secrets.sh -f .env.prod -a my-app

# Actually set the secrets
./scripts/env-to-fly-secrets.sh -f .env.prod -a my-app --execute

# Custom batch size
./scripts/env-to-fly-secrets.sh -f .env.prod -a my-app -n 5 --execute
```

If justfile was configured:
```bash
# Dry-run
just fly-secrets

# Execute
just fly-secrets --execute
```
